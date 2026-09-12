create table if not exists programacion.agent_task_delivery_contracts (
  id bigint generated always as identity primary key,
  task_id bigint not null unique references programacion.agent_tasks(id) on delete restrict,
  schema_version smallint not null default 2 check (schema_version = 2),
  expected_change text not null,
  in_scope jsonb not null default '[]'::jsonb,
  out_of_scope jsonb not null default '[]'::jsonb,
  must_not_change jsonb not null default '[]'::jsonb,
  positive_cases jsonb not null default '[]'::jsonb,
  edge_cases jsonb not null default '[]'::jsonb,
  regression_cases jsonb not null default '[]'::jsonb,
  dependency_resolution jsonb not null default '[]'::jsonb,
  required_tests jsonb not null default '[]'::jsonb,
  required_evidence jsonb not null default '[]'::jsonb,
  blocked_if jsonb not null default '[]'::jsonb,
  semantic_ambiguities jsonb not null default '[]'::jsonb,
  generated_from_functional_sha256 text not null check (generated_from_functional_sha256 ~ '^[0-9a-f]{64}$'),
  generated_from_task_sha256 text not null check (generated_from_task_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'DRAFT' check (status in ('DRAFT','SEALED')),
  contract_sha256 text check (contract_sha256 is null or contract_sha256 ~ '^[0-9a-f]{64}$'),
  sealed_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function programacion.fn_guard_agent_task_delivery_contract()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','programacion'
as $function$
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
  if tg_op='DELETE' then
    raise exception 'agent task delivery contracts are append-only';
  end if;
  if tg_op='UPDATE' and old.status='SEALED' then
    raise exception 'sealed delivery contract % is immutable; supersede the Agent Task',old.id;
  end if;
  if tg_op='INSERT' and new.status<>'DRAFT' then
    raise exception 'delivery contract must be born DRAFT';
  end if;

  select * into v_task from programacion.agent_tasks where id=new.task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then
    raise exception 'delivery contract requires SEALED Agent Task';
  end if;
  select * into v_functional from public.lf_functional_versions where id=v_task.functional_version_id;
  if v_functional.id is null or v_functional.status<>'SEALED' then
    raise exception 'delivery contract requires SEALED functional version';
  end if;
  select * into v_story from public.lf_user_stories where story_code=v_functional.story_code;
  if v_story.story_code is null then
    raise exception 'delivery contract requires source Story %',v_functional.story_code;
  end if;
  select * into v_test from programacion.test_contracts where task_id=v_task.id and status='SEALED';
  if v_test.id is null then
    raise exception 'delivery contract requires SEALED Test Contract';
  end if;

  if new.generated_from_functional_sha256<>v_functional.content_sha256
     or new.generated_from_task_sha256<>v_task.task_sha256 then
    raise exception 'delivery contract source SHA mismatch';
  end if;
  if length(btrim(new.expected_change))<10 then
    raise exception 'expected_change must be explicit and non-trivial';
  end if;

  if jsonb_typeof(new.in_scope)<>'array'
     or jsonb_typeof(new.out_of_scope)<>'array'
     or jsonb_typeof(new.must_not_change)<>'array'
     or jsonb_typeof(new.positive_cases)<>'array'
     or jsonb_typeof(new.edge_cases)<>'array'
     or jsonb_typeof(new.regression_cases)<>'array'
     or jsonb_typeof(new.dependency_resolution)<>'array'
     or jsonb_typeof(new.required_tests)<>'array'
     or jsonb_typeof(new.required_evidence)<>'array'
     or jsonb_typeof(new.blocked_if)<>'array'
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
  if v_task.acceptance_refs is distinct from v_ac
     or v_task.invariant_refs is distinct from v_inv
     or v_task.negative_refs is distinct from v_neg then
    raise exception 'TASK_SEMANTIC_COVERAGE_INCOMPLETE: Agent Task must reference the complete AC/INV/NEG universe of its functional version';
  end if;
  v_valid_refs:=coalesce(v_ac,'{}'::text[])||coalesce(v_inv,'{}'::text[])||coalesce(v_neg,'{}'::text[])||coalesce(v_functional.source_rule_codes,'{}'::text[]);

  for v_case in
    select value from jsonb_array_elements(new.positive_cases)
    union all select value from jsonb_array_elements(new.edge_cases)
    union all select value from jsonb_array_elements(new.regression_cases)
  loop
    if jsonb_typeof(v_case)<>'object'
       or length(btrim(coalesce(v_case->>'code','')))=0
       or length(btrim(coalesce(v_case->>'statement','')))=0
       or jsonb_typeof(v_case->'source_refs') is distinct from 'array' then
      raise exception 'case entries require code, statement and source_refs[]';
    end if;
    if jsonb_array_length(v_case->'source_refs')=0 then
      raise exception 'case % must trace to at least one source ref',v_case->>'code';
    end if;
    for v_ref in select jsonb_array_elements_text(v_case->'source_refs') loop
      if not (v_ref=any(v_valid_refs)) then
        raise exception 'case % references unknown semantic source %',v_case->>'code',v_ref;
      end if;
    end loop;
  end loop;

  select coalesce(array_agg(value order by value),'{}'::text[])
    into v_expected_deps
  from jsonb_array_elements_text(coalesce(v_story.dependencies,'[]'::jsonb));
  select coalesce(array_agg(value order by value),'{}'::text[])
    into v_resolved_deps
  from (
    select distinct e->>'source_dependency' as value
    from jsonb_array_elements(new.dependency_resolution) e
    where length(btrim(coalesce(e->>'source_dependency','')))>0
  ) q;
  if v_expected_deps is distinct from v_resolved_deps then
    raise exception 'STORY_DEPENDENCY_RESOLUTION_INCOMPLETE: expected %, resolved %',v_expected_deps,v_resolved_deps;
  end if;

  for v_dep in select value from jsonb_array_elements(new.dependency_resolution) loop
    if jsonb_typeof(v_dep)<>'object' then raise exception 'dependency_resolution entries must be objects'; end if;
    v_resolution_type:=v_dep->>'resolution_type';
    v_resolution_ref:=v_dep->>'resolution_ref';
    if v_resolution_type not in ('TASK_EDGE','INTERFACE_REF','CONTEXT_REF','BLOCKER','NOT_APPLICABLE') then
      raise exception 'invalid dependency resolution type %',v_resolution_type;
    end if;
    if v_resolution_type='TASK_EDGE' then
      if coalesce(v_resolution_ref,'')!~'^agent-task://[1-9][0-9]*$'
         or not exists(
           select 1 from programacion.task_dependencies d
           where d.task_id=v_task.id
             and ('agent-task://'||d.depends_on_task_id::text)=v_resolution_ref
         ) then raise exception 'TASK_EDGE resolution is not backed by task_dependencies: %',v_resolution_ref; end if;
    elsif v_resolution_type='INTERFACE_REF' then
      if not (v_resolution_ref=any(v_task.interface_refs)) then raise exception 'INTERFACE_REF not present in Agent Task: %',v_resolution_ref; end if;
    elsif v_resolution_type='CONTEXT_REF' then
      if not (v_resolution_ref=any(v_task.context_path_patterns)) then raise exception 'CONTEXT_REF not present in context_path_patterns: %',v_resolution_ref; end if;
    elsif v_resolution_type='BLOCKER' then
      if not exists(
        select 1 from programacion.task_blockers b
        where b.task_id=v_task.id and b.status='OPEN'
          and v_resolution_ref in (b.blocker_code,b.owner_ref,b.source_ref)
      ) then raise exception 'BLOCKER resolution is not backed by an OPEN task blocker: %',v_resolution_ref; end if;
    elsif v_resolution_type='NOT_APPLICABLE' then
      if length(btrim(coalesce(v_dep->>'reason','')))<10 then raise exception 'NOT_APPLICABLE dependency resolution requires reason'; end if;
    end if;
  end loop;

  for v_case in select value from jsonb_array_elements(new.required_tests) loop
    if jsonb_typeof(v_case)<>'object'
       or length(btrim(coalesce(v_case->>'test_ref','')))=0
       or length(btrim(coalesce(v_case->>'purpose','')))=0
       or jsonb_typeof(v_case->'covers_refs') is distinct from 'array'
       or jsonb_array_length(v_case->'covers_refs')=0 then
      raise exception 'required_tests entries require test_ref, purpose and covers_refs[]';
    end if;
    for v_ref in select jsonb_array_elements_text(v_case->'covers_refs') loop
      if not (v_ref=any(v_valid_refs)) then raise exception 'required test references unknown semantic source %',v_ref; end if;
    end loop;
  end loop;

  for v_case in select value from jsonb_array_elements(new.required_evidence) loop
    if jsonb_typeof(v_case)<>'object'
       or length(btrim(coalesce(v_case->>'evidence_type','')))=0
       or length(btrim(coalesce(v_case->>'source_ref','')))=0
       or jsonb_typeof(v_case->'covers_refs') is distinct from 'array' then
      raise exception 'required_evidence entries require evidence_type, source_ref and covers_refs[]';
    end if;
  end loop;

  for v_case in select value from jsonb_array_elements(new.blocked_if) loop
    if jsonb_typeof(v_case)<>'object'
       or length(btrim(coalesce(v_case->>'code','')))=0
       or length(btrim(coalesce(v_case->>'condition','')))=0 then
      raise exception 'blocked_if entries require code and condition';
    end if;
  end loop;

  if new.status='DRAFT' then
    if new.contract_sha256 is not null or new.sealed_at is not null then
      raise exception 'DRAFT delivery contract cannot carry seal';
    end if;
  else
    if tg_op<>'UPDATE' or old.status<>'DRAFT' then
      raise exception 'SEALED delivery contract requires DRAFT -> SEALED transition';
    end if;
    if jsonb_array_length(new.semantic_ambiguities)>0 then
      raise exception 'SEMANTIC_AMBIGUITIES_UNRESOLVED: %',new.semantic_ambiguities;
    end if;
    v_payload:=jsonb_build_object(
      'schema_version',new.schema_version,
      'task_id',new.task_id,
      'task_sha256',v_task.task_sha256,
      'functional_sha256',v_functional.content_sha256,
      'test_contract_sha256',v_test.contract_sha256,
      'expected_change',new.expected_change,
      'in_scope',new.in_scope,
      'out_of_scope',new.out_of_scope,
      'must_not_change',new.must_not_change,
      'positive_cases',new.positive_cases,
      'edge_cases',new.edge_cases,
      'regression_cases',new.regression_cases,
      'dependency_resolution',new.dependency_resolution,
      'required_tests',new.required_tests,
      'required_evidence',new.required_evidence,
      'blocked_if',new.blocked_if
    );
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);
    if new.contract_sha256 is not null and new.contract_sha256<>v_digest then
      raise exception 'delivery contract digest mismatch';
    end if;
    new.contract_sha256:=v_digest;
    new.sealed_at:=coalesce(new.sealed_at,now());
  end if;
  return new;
end;
$function$;

create trigger trg_agent_task_delivery_contract_guard
before insert or update or delete on programacion.agent_task_delivery_contracts
for each row execute function programacion.fn_guard_agent_task_delivery_contract();

create or replace function programacion.fn_task_readiness(p_task_id bigint)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  t programacion.agent_tasks%rowtype;
  f public.lf_functional_versions%rowtype;
  tc programacion.test_contracts%rowtype;
  dc programacion.agent_task_delivery_contracts%rowtype;
  b record;
  d record;
  v_ready boolean:=true;
  v_exec boolean:=true;
  v_sizing text:='EXECUTABLE';
  v_blockers jsonb:='[]'::jsonb;
  v_waiting jsonb:='[]'::jsonb;
  v_metrics jsonb;
  v_rule_authority jsonb;
  v_sizing_cfg jsonb;
  v_policy_ok boolean:=false;
  v_dep_count integer;
begin
  select * into t from programacion.agent_tasks where id=p_task_id;
  if t.id is null then raise exception 'agent task % not found',p_task_id; end if;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  select * into dc from programacion.agent_task_delivery_contracts where task_id=t.id and status='SEALED';
  v_metrics:=programacion.fn_task_dag_metrics(t.functional_version_id);
  v_rule_authority:=programacion.fn_source_rule_authority(f.source_rule_codes);
  select count(*) into v_dep_count from programacion.task_dependencies where task_id=t.id;

  v_sizing_cfg:=programacion.fn_task_sizing_profile(t.id);
  v_policy_ok := v_sizing_cfg is not null
    and v_sizing_cfg->>'threshold_status'='CALIBRATED'
    and coalesce(v_sizing_cfg->>'max_files_expected','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_dependency_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_platform_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_interface_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_attempts','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_patch_bytes','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_changed_files','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_context_bytes','') ~ '^[0-9]+$';

  if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=t.id) then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_SUPERSEDED','owner_type','TASK_PREPARATION','required_action','USE_CURRENT_TASK_VERSION','source_ref','agent-task://'||t.id));
  end if;
  if f.status<>'SEALED' then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','FUNCTIONAL_VERSION_NOT_SEALED','owner_type','FUNCTIONAL_OWNER','required_action','SEAL_FUNCTIONAL_VERSION','source_ref','functional-version://'||t.functional_version_id)); end if;
  if coalesce((v_rule_authority->>'authoritative')::boolean,false) is not true then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SOURCE_RULE_AUTHORITY_BLOCKED','owner_type','FUNCTIONAL_RULE_OWNER','required_action','PROMOTE_SOURCE_RULES_TO_APROBADO_OR_VIGENTE','source_ref','functional-version://'||t.functional_version_id,'details',v_rule_authority->'problems')); end if;
  if t.definition_status<>'SEALED' then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_NOT_SEALED','owner_type','TASK_PREPARATION','required_action','SEAL_AGENT_TASK','source_ref','agent-task://'||t.id)); end if;
  if tc.id is null then v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TEST_CONTRACT_NOT_SEALED','owner_type','TEST_CONTRACT_GENERATOR','required_action','GENERATE_AND_SEAL_BLIND_TEST_CONTRACT','source_ref','agent-task://'||t.id)); end if;
  if dc.id is null then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','AGENT_TASK_DELIVERY_CONTRACT_NOT_SEALED','owner_type','TASK_PREPARATION',
      'required_action','GENERATE_RESOLVE_AND_SEAL_AGENT_TASK_DELIVERY_CONTRACT_V2','source_ref','agent-task://'||t.id,
      'details',coalesce((select jsonb_build_object('semantic_ambiguities',semantic_ambiguities,'dependency_resolution',dependency_resolution) from programacion.agent_task_delivery_contracts where task_id=t.id),'{}'::jsonb)
    ));
  end if;

  if cardinality(t.unknown_refs)>0 then v_ready:=false; v_sizing:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','UNKNOWN_SCOPE_REFS','owner_type','TASK_PREPARATION','required_action','RESOLVE_UNKNOWNS','source_ref','agent-task://'||t.id)); end if;

  if not v_policy_ok then
    v_ready:=false; v_sizing:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_POLICY_MISSING','owner_type','HUMAN_PLAN','required_action','CALIBRATE_MATCHING_G_TASK_SIZING_MIN_PROFILE','source_ref','gate://G_TASK_SIZING_MIN'));
  elsif cardinality(t.unknown_refs)=0 and (
       cardinality(t.files_expected)>(v_sizing_cfg->>'max_files_expected')::integer
       or v_dep_count>(v_sizing_cfg->>'max_dependency_count')::integer
       or cardinality(t.platform_refs)>(v_sizing_cfg->>'max_platform_count')::integer
       or cardinality(t.interface_refs)>(v_sizing_cfg->>'max_interface_count')::integer
  ) then
    v_ready:=false; v_sizing:='DECOMPOSE_REQUIRED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_DECOMPOSE_REQUIRED','owner_type','TASK_PREPARATION','required_action','SPLIT_OR_REDUCE_SCOPE','source_ref','agent-task://'||t.id));
  end if;

  if coalesce((v_metrics->>'task_count')::integer,0)>1 and v_metrics->>'pure_chain_policy_status'='MISSING' then
    v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DAG_POLICY_MISSING','owner_type','HUMAN_PLAN','required_action','CALIBRATE_G_TASK_DAG_MAX_PURE_CHAIN_LENGTH','source_ref','gate://G_TASK_DAG'));
  elsif coalesce((v_metrics->>'pure_chain')::boolean,false) then
    v_ready:=false; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PURE_CHAIN_RECOMBINE_REQUIRED','owner_type','TASK_PREPARATION','required_action','RECOMBINE_TASKS','source_ref','functional-version://'||t.functional_version_id));
  end if;

  for b in select * from programacion.task_blockers where task_id=t.id and status='OPEN' loop
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code',b.blocker_code,'owner_type',b.owner_type,'owner_ref',b.owner_ref,'required_action',b.required_action,'source_ref',b.source_ref));
  end loop;

  for d in select depends_on_task_id from programacion.task_dependencies where task_id=t.id order by depends_on_task_id loop
    if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=d.depends_on_task_id)
       or not exists(select 1 from programacion.agent_tasks x where x.id=d.depends_on_task_id and x.definition_status='SEALED') then
      v_ready:=false;
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DEPENDENCY_TASK_NOT_CURRENT_SEALED','owner_type','TASK_PREPARATION','required_action','RESOLVE_DEPENDENCY_TASK','source_ref','agent-task://'||d.depends_on_task_id));
    end if;
    if not exists(select 1 from programacion.v_ejecucion_autoridad ea join programacion.ejecuciones ex on ex.id=ea.execution_id where ex.request_ref='agent-task://'||d.depends_on_task_id and ea.effective_verdict='PASS') then
      v_exec:=false;
      v_waiting:=v_waiting||jsonb_build_array(d.depends_on_task_id);
    end if;
  end loop;

  if not v_ready then v_exec:=false; end if;
  return jsonb_build_object(
    'task_id',t.id,'task_code',t.task_code,'task_version',t.task_version,
    'ready_for_development',v_ready,'executable_now',v_exec,'sizing',v_sizing,
    'delivery_contract_status',coalesce(dc.status,(select status from programacion.agent_task_delivery_contracts where task_id=t.id),'MISSING'),
    'delivery_contract_sha256',dc.contract_sha256,
    'sizing_metrics',jsonb_build_object('files_expected',cardinality(t.files_expected),'dependency_count',v_dep_count,'platform_count',cardinality(t.platform_refs),'interface_count',cardinality(t.interface_refs),'unknown_count',cardinality(t.unknown_refs)),
    'sizing_policy_status',case when v_policy_ok then 'CALIBRATED' else 'MISSING_PROFILE' end,
    'sizing_profile_code',v_sizing_cfg->>'profile_code',
    'dag',v_metrics,'source_rule_authority',v_rule_authority,'blockers',v_blockers,'waiting_on_task_ids',v_waiting
  );
end;
$function$;

create or replace function programacion.fn_agent_task_execution_bundle(p_task_id bigint,p_base_head_sha text,p_source_snapshot_sha256 text)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  t programacion.agent_tasks%rowtype;
  f public.lf_functional_versions%rowtype;
  s public.lf_user_stories%rowtype;
  tc programacion.test_contracts%rowtype;
  dc programacion.agent_task_delivery_contracts%rowtype;
  r jsonb;
  v_spec jsonb;
  v_preimage jsonb;
  v_bundle_sha text;
  v_dep_ids bigint[];
begin
  if p_base_head_sha!~'^[0-9a-f]{40}$' or p_source_snapshot_sha256!~'^[0-9a-f]{64}$' then raise exception 'invalid source identity';end if;
  r:=programacion.fn_task_readiness(p_task_id);
  if not coalesce((r->>'ready_for_development')::boolean,false)then raise exception 'TASK_NOT_READY: %',r->'blockers';end if;
  if not coalesce((r->>'executable_now')::boolean,false)then raise exception 'TASK_WAITING_DEPENDENCIES: %',r->'waiting_on_task_ids';end if;
  select * into t from programacion.agent_tasks where id=p_task_id;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into s from public.lf_user_stories where story_code=f.story_code;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  select * into dc from programacion.agent_task_delivery_contracts where task_id=t.id and status='SEALED';
  select coalesce(array_agg(depends_on_task_id order by depends_on_task_id),'{}'::bigint[]) into v_dep_ids from programacion.task_dependencies where task_id=t.id;

  v_spec:=jsonb_build_object(
    'schema_version',2,
    'task_id',t.task_code||'.v'||t.task_version,
    'objective',t.objective,
    'expected_change',dc.expected_change,
    'human_story',jsonb_build_object('story_code',s.story_code,'title',s.title,'persona',s.persona,'need',s.need_statement,'benefit',s.benefit_statement),
    'functional_contract',jsonb_build_object('acceptance_criteria',f.acceptance_criteria,'invariants',f.invariants,'negative_controls',f.negative_controls,'source_rule_codes',to_jsonb(f.source_rule_codes)),
    'scope',jsonb_build_object('in_scope',dc.in_scope,'out_of_scope',dc.out_of_scope,'must_not_change',dc.must_not_change),
    'cases',jsonb_build_object('positive',dc.positive_cases,'edge',dc.edge_cases,'regression',dc.regression_cases),
    'dependency_resolution',dc.dependency_resolution,
    'dependency_task_ids',to_jsonb(v_dep_ids),
    'required_tests',dc.required_tests,
    'required_evidence',dc.required_evidence,
    'blocked_if',dc.blocked_if,
    'base_head_sha',p_base_head_sha,
    'source_snapshot_sha256',p_source_snapshot_sha256,
    'context_path_patterns',to_jsonb(t.context_path_patterns),
    'write_path_patterns',to_jsonb(t.write_path_patterns),
    'protected_path_patterns',to_jsonb(t.protected_path_patterns),
    'files_expected',to_jsonb(t.files_expected),
    'platform_refs',to_jsonb(t.platform_refs),
    'interface_refs',to_jsonb(t.interface_refs),
    'acceptance_commands',tc.visible_commands,
    'hidden_oracle_ref',tc.hidden_oracle_ref,
    'max_attempts',t.max_attempts,
    'max_patch_bytes',t.max_patch_bytes,
    'max_changed_files',t.max_changed_files,
    'max_context_bytes',t.max_context_bytes,
    'allow_deletions',t.allow_deletions
  );
  v_preimage:=jsonb_build_object(
    'request_ref','agent-task://'||t.id,
    'worker_task_spec',v_spec,
    'hidden_oracle_ref',tc.hidden_oracle_ref,
    'hidden_oracle_sha256',tc.hidden_oracle_sha256,
    'functional_version_sha256',f.content_sha256,
    'task_sha256',t.task_sha256,
    'delivery_contract_sha256',dc.contract_sha256,
    'test_contract_sha256',tc.contract_sha256,
    'readiness',r
  );
  v_bundle_sha:=programacion.fn_v09_sha256_jsonb(v_preimage);
  return v_preimage||jsonb_build_object('bundle_sha256',v_bundle_sha);
end;
$function$;

revoke all on programacion.agent_task_delivery_contracts from public;
revoke all on programacion.agent_task_delivery_contracts from anon;
revoke all on programacion.agent_task_delivery_contracts from authenticated;
grant select,insert,update on programacion.agent_task_delivery_contracts to programacion_builder;
grant select on programacion.agent_task_delivery_contracts to programacion_auditor;
grant select on programacion.agent_task_delivery_contracts to programacion_human_authority;
grant select on programacion.agent_task_delivery_contracts to programacion_verifier;
grant usage,select on sequence programacion.agent_task_delivery_contracts_id_seq to programacion_builder;