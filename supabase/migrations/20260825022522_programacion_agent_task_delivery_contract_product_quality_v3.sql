-- Product/Quality lane must be independently sealable from hidden-oracle authority.
-- schema_version <= 2 preserves the historical test-contract binding.
-- schema_version >= 3 validates the visible semantic delivery contract without requiring
-- a hidden Test Contract. Execution/readiness still requires the SEALED Test Contract.

create or replace function programacion.fn_guard_agent_task_delivery_contract()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  v_task programacion.agent_tasks%rowtype;
  v_functional public.lf_functional_versions%rowtype;
  v_story public.lf_user_stories%rowtype;
  v_test programacion.test_contracts%rowtype;
  v_expected_deps text[] := '{}'::text[];
  v_resolved_deps text[] := '{}'::text[];
  v_valid_refs text[] := '{}'::text[];
  v_ac text[] := '{}'::text[];
  v_inv text[] := '{}'::text[];
  v_neg text[] := '{}'::text[];
  v_case jsonb;
  v_ref text;
  v_dep jsonb;
  v_resolution_type text;
  v_resolution_ref text;
  v_payload jsonb;
  v_digest text;
begin
  if tg_op='DELETE' then raise exception 'agent task delivery contracts are append-only'; end if;
  if tg_op='UPDATE' and old.status='SEALED' then raise exception 'sealed delivery contract % is immutable; supersede the Agent Task',old.id; end if;
  if tg_op='INSERT' and new.status<>'DRAFT' then raise exception 'delivery contract must be born DRAFT'; end if;
  if new.schema_version not in (2,3) then raise exception 'unsupported delivery contract schema_version %',new.schema_version; end if;

  select * into v_task from programacion.agent_tasks where id=new.task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'delivery contract requires SEALED Agent Task'; end if;
  select * into v_functional from public.lf_functional_versions where id=v_task.functional_version_id;
  if v_functional.id is null or v_functional.status<>'SEALED' then raise exception 'delivery contract requires SEALED functional version'; end if;
  select * into v_story from public.lf_user_stories where story_code=v_functional.story_code;
  if v_story.story_code is null then raise exception 'delivery contract requires source Story %',v_functional.story_code; end if;

  select * into v_test from programacion.test_contracts where task_id=v_task.id and status='SEALED';
  if new.schema_version<=2 and v_test.id is null then
    raise exception 'delivery contract schema v2 requires SEALED Test Contract';
  end if;

  if new.generated_from_functional_sha256<>v_functional.content_sha256
     or new.generated_from_task_sha256<>v_task.task_sha256 then raise exception 'delivery contract source SHA mismatch'; end if;
  if length(btrim(new.expected_change))<10 then raise exception 'expected_change must be explicit and non-trivial'; end if;

  if jsonb_typeof(new.in_scope)<>'array' or jsonb_typeof(new.out_of_scope)<>'array'
     or jsonb_typeof(new.must_not_change)<>'array' or jsonb_typeof(new.positive_cases)<>'array'
     or jsonb_typeof(new.edge_cases)<>'array' or jsonb_typeof(new.regression_cases)<>'array'
     or jsonb_typeof(new.dependency_resolution)<>'array' or jsonb_typeof(new.required_tests)<>'array'
     or jsonb_typeof(new.required_evidence)<>'array' or jsonb_typeof(new.blocked_if)<>'array'
     or jsonb_typeof(new.semantic_ambiguities)<>'array' then
    raise exception 'delivery contract collection fields must be JSON arrays';
  end if;

  if jsonb_array_length(new.in_scope)=0 or jsonb_array_length(new.out_of_scope)=0
     or jsonb_array_length(new.must_not_change)=0 or jsonb_array_length(new.positive_cases)=0
     or jsonb_array_length(new.edge_cases)=0 or jsonb_array_length(new.regression_cases)=0
     or jsonb_array_length(new.required_tests)=0 or jsonb_array_length(new.required_evidence)=0
     or jsonb_array_length(new.blocked_if)=0 then
    raise exception 'delivery contract requires explicit scope, cases, tests, evidence and blocked_if; use NOT_APPLICABLE entries with reason when appropriate';
  end if;

  if exists(select 1 from jsonb_array_elements(new.in_scope) e where jsonb_typeof(e)<>'string' or length(btrim(e#>>'{}'))=0)
     or exists(select 1 from jsonb_array_elements(new.out_of_scope) e where jsonb_typeof(e)<>'string' or length(btrim(e#>>'{}'))=0)
     or exists(select 1 from jsonb_array_elements(new.must_not_change) e where jsonb_typeof(e)<>'string' or length(btrim(e#>>'{}'))=0) then
    raise exception 'scope and must_not_change entries must be non-empty strings';
  end if;

  v_ac:=programacion.fn_p0_json_codes(v_functional.acceptance_criteria,'AC');
  v_inv:=programacion.fn_p0_json_codes(v_functional.invariants,'INV');
  v_neg:=programacion.fn_p0_json_codes(v_functional.negative_controls,'NEG');
  if v_task.acceptance_refs is distinct from v_ac or v_task.invariant_refs is distinct from v_inv or v_task.negative_refs is distinct from v_neg then
    raise exception 'TASK_SEMANTIC_COVERAGE_INCOMPLETE: Agent Task must reference the complete AC/INV/NEG universe of its functional version';
  end if;
  v_valid_refs:=coalesce(v_ac,'{}'::text[])||coalesce(v_inv,'{}'::text[])||coalesce(v_neg,'{}'::text[])||coalesce(v_functional.source_rule_codes,'{}'::text[]);

  for v_case in
    select value from jsonb_array_elements(new.positive_cases)
    union all select value from jsonb_array_elements(new.edge_cases)
    union all select value from jsonb_array_elements(new.regression_cases)
  loop
    if jsonb_typeof(v_case)<>'object' or length(btrim(coalesce(v_case->>'code','')))=0
       or length(btrim(coalesce(v_case->>'statement','')))=0
       or jsonb_typeof(v_case->'source_refs') is distinct from 'array' then
      raise exception 'case entries require code, statement and source_refs[]';
    end if;
    if jsonb_array_length(v_case->'source_refs')=0 then raise exception 'case % must trace to at least one source ref',v_case->>'code'; end if;
    for v_ref in select jsonb_array_elements_text(v_case->'source_refs') loop
      if not (v_ref=any(v_valid_refs)) then raise exception 'case % references unknown semantic source %',v_case->>'code',v_ref; end if;
    end loop;
  end loop;

  select coalesce(array_agg(value order by value),'{}'::text[]) into v_expected_deps
  from jsonb_array_elements_text(coalesce(v_story.dependencies,'[]'::jsonb));
  select coalesce(array_agg(value order by value),'{}'::text[]) into v_resolved_deps
  from (select distinct e->>'source_dependency' as value from jsonb_array_elements(new.dependency_resolution) e where length(btrim(coalesce(e->>'source_dependency','')))>0) q;
  if v_expected_deps is distinct from v_resolved_deps then raise exception 'STORY_DEPENDENCY_RESOLUTION_INCOMPLETE: expected %, resolved %',v_expected_deps,v_resolved_deps; end if;

  for v_dep in select value from jsonb_array_elements(new.dependency_resolution) loop
    if jsonb_typeof(v_dep)<>'object' then raise exception 'dependency_resolution entries must be objects'; end if;
    v_resolution_type:=v_dep->>'resolution_type'; v_resolution_ref:=v_dep->>'resolution_ref';
    if v_resolution_type not in ('TASK_EDGE','INTERFACE_REF','CONTEXT_REF','BLOCKER','NOT_APPLICABLE','UNRESOLVED') then raise exception 'invalid dependency resolution type %',v_resolution_type; end if;
    if v_resolution_type='TASK_EDGE' then
      if coalesce(v_resolution_ref,'')!~'^agent-task://[1-9][0-9]*$' or not exists(select 1 from programacion.task_dependencies d where d.task_id=v_task.id and ('agent-task://'||d.depends_on_task_id::text)=v_resolution_ref) then raise exception 'TASK_EDGE resolution is not backed by task_dependencies: %',v_resolution_ref; end if;
    elsif v_resolution_type='INTERFACE_REF' then
      if not (v_resolution_ref=any(v_task.interface_refs)) then raise exception 'INTERFACE_REF not present in Agent Task: %',v_resolution_ref; end if;
    elsif v_resolution_type='CONTEXT_REF' then
      if not (v_resolution_ref=any(v_task.context_path_patterns)) then raise exception 'CONTEXT_REF not present in context_path_patterns: %',v_resolution_ref; end if;
    elsif v_resolution_type='BLOCKER' then
      if not exists(select 1 from programacion.task_blockers b where b.task_id=v_task.id and b.status='OPEN' and v_resolution_ref in (b.blocker_code,b.owner_ref,b.source_ref)) then raise exception 'BLOCKER resolution is not backed by an OPEN task blocker: %',v_resolution_ref; end if;
    elsif v_resolution_type='NOT_APPLICABLE' then
      if length(btrim(coalesce(v_dep->>'reason','')))<10 then raise exception 'NOT_APPLICABLE dependency resolution requires reason'; end if;
    elsif v_resolution_type='UNRESOLVED' then
      if length(btrim(coalesce(v_dep->>'reason','')))<10 then raise exception 'UNRESOLVED dependency resolution requires reason'; end if;
      if new.status='SEALED' then raise exception 'UNRESOLVED dependency cannot be SEALED: %',v_dep->>'source_dependency'; end if;
    end if;
  end loop;

  for v_case in select value from jsonb_array_elements(new.required_tests) loop
    if jsonb_typeof(v_case)<>'object' or length(btrim(coalesce(v_case->>'test_ref','')))=0
       or length(btrim(coalesce(v_case->>'purpose','')))=0
       or jsonb_typeof(v_case->'covers_refs') is distinct from 'array'
       or jsonb_array_length(v_case->'covers_refs')=0 then raise exception 'required_tests entries require test_ref, purpose and covers_refs[]'; end if;
    for v_ref in select jsonb_array_elements_text(v_case->'covers_refs') loop
      if not (v_ref=any(v_valid_refs)) then raise exception 'required test references unknown semantic source %',v_ref; end if;
    end loop;
  end loop;

  -- Every material AC/INV/NEG must be covered by at least one declared semantic/mutation test.
  for v_ref in select unnest(coalesce(v_ac,'{}'::text[])||coalesce(v_inv,'{}'::text[])||coalesce(v_neg,'{}'::text[])) loop
    if not exists(
      select 1 from jsonb_array_elements(new.required_tests) rt
      where (rt->>'test_ref' like 'SEMANTIC:%' or rt->>'test_ref' like 'MUTATION:%')
        and exists(select 1 from jsonb_array_elements_text(rt->'covers_refs') cr where cr=v_ref)
    ) then raise exception 'DELIVERY_TEST_COVERAGE_INCOMPLETE: semantic ref % has no SEMANTIC/MUTATION test coverage',v_ref; end if;
  end loop;

  for v_case in select value from jsonb_array_elements(new.required_evidence) loop
    if jsonb_typeof(v_case)<>'object' or length(btrim(coalesce(v_case->>'evidence_type','')))=0
       or length(btrim(coalesce(v_case->>'source_ref','')))=0
       or jsonb_typeof(v_case->'covers_refs') is distinct from 'array' then raise exception 'required_evidence entries require evidence_type, source_ref and covers_refs[]'; end if;
  end loop;
  for v_case in select value from jsonb_array_elements(new.blocked_if) loop
    if jsonb_typeof(v_case)<>'object' or length(btrim(coalesce(v_case->>'code','')))=0 or length(btrim(coalesce(v_case->>'condition','')))=0 then raise exception 'blocked_if entries require code and condition'; end if;
  end loop;

  if new.status='DRAFT' then
    if new.contract_sha256 is not null or new.sealed_at is not null then raise exception 'DRAFT delivery contract cannot carry seal'; end if;
  else
    if tg_op<>'UPDATE' or old.status<>'DRAFT' then raise exception 'SEALED delivery contract requires DRAFT -> SEALED transition'; end if;
    if jsonb_array_length(new.semantic_ambiguities)>0 then raise exception 'SEMANTIC_AMBIGUITIES_UNRESOLVED: %',new.semantic_ambiguities; end if;
    v_payload:=jsonb_build_object(
      'schema_version',new.schema_version,'task_id',new.task_id,'task_sha256',v_task.task_sha256,
      'functional_sha256',v_functional.content_sha256,
      'test_contract_binding',case when new.schema_version<=2 then coalesce(v_test.contract_sha256,'') else 'DEFERRED_TO_EXECUTION_READINESS' end,
      'expected_change',new.expected_change,'in_scope',new.in_scope,'out_of_scope',new.out_of_scope,'must_not_change',new.must_not_change,
      'positive_cases',new.positive_cases,'edge_cases',new.edge_cases,'regression_cases',new.regression_cases,
      'dependency_resolution',new.dependency_resolution,'required_tests',new.required_tests,'required_evidence',new.required_evidence,'blocked_if',new.blocked_if
    );
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);
    if new.contract_sha256 is not null and new.contract_sha256<>v_digest then raise exception 'delivery contract digest mismatch'; end if;
    new.contract_sha256:=v_digest; new.sealed_at:=coalesce(new.sealed_at,now());
  end if;
  return new;
end;
$$;
