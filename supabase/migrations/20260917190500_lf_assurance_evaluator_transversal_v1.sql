-- LF_ASSURANCE_EVALUATOR_TRANSVERSAL_V1
-- One transversal closure evaluator for the existing LF Assurance Method.
-- Reuses the canonical claim/obligation/defeater catalogs, subject bindings,
-- LF Test Matrix runs and append-only lf_assurance_evaluations.
-- No new assurance table, no second matrix, no capability-specific hardcode.
-- Candidate/source only until a separately governed Supabase apply is authorized.

create or replace function public.lf_assurance_case_evidence_v1(
  p_suite_code text,
  p_test_code text,
  p_subject_revision text
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_case public.lf_test_suite_cases%rowtype;
  v_run public.lf_test_runs%rowtype;
  v_judge public.lf_test_judge_results%rowtype;
  v_result text := 'UNPROVEN';
  v_reason text := null;
  v_mode text := 'DETERMINISTIC';
  v_evidence_refs jsonb := '[]'::jsonb;
begin
  if nullif(btrim(coalesce(p_suite_code,'')),'') is null
     or nullif(btrim(coalesce(p_test_code,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'result','UNPROVEN',
      'reason','CASE_IDENTITY_MISSING',
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb
    );
  end if;

  if nullif(btrim(coalesce(p_subject_revision,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'result','UNPROVEN',
      'reason','SUBJECT_REVISION_REQUIRED',
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb
    );
  end if;

  select * into v_case
  from public.lf_test_suite_cases
  where suite_code=p_suite_code
    and test_code=p_test_code
    and status in ('ACTIVE','CANDIDATO')
  limit 1;

  if not found then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'result','UNPROVEN',
      'reason','REQUIRED_CASE_NOT_REGISTERED',
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb
    );
  end if;

  select * into v_run
  from public.lf_test_runs
  where suite_code=p_suite_code
    and test_code=p_test_code
    and commit_sha=p_subject_revision
  order by coalesce(completed_at,updated_at,started_at,created_at) desc, attempt_no desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'result','UNPROVEN',
      'reason','EXACT_REVISION_RUN_MISSING',
      'execution_mode',v_case.execution_mode,
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'evidence_refs','[]'::jsonb
    );
  end if;

  v_evidence_refs := jsonb_build_array(
    format('supabase://public/lf_test_runs/%s',v_run.test_run_id)
  );

  if v_run.status='FAILED' then
    v_result := 'FAIL';
    v_reason := 'TEST_RUN_FAILED';
  elsif v_run.status in ('BLOCKED','PARTIAL_BLOCKED') then
    v_result := 'OPEN';
    v_reason := 'TEST_RUN_BLOCKED';
  elsif v_run.status='PASSED' then
    if v_case.execution_mode='INDEPENDENT_REVIEW' then
      v_mode := 'INDEPENDENT_REVIEW';

      select * into v_judge
      from public.lf_test_judge_results
      where test_run_id=v_run.test_run_id
        and verdict='PASS'
        and created_by_execution_id is distinct from v_run.execution_id
      order by observed_at desc, created_at desc
      limit 1;

      if found then
        v_result := 'PASS';
        v_reason := 'EXACT_REVISION_TEST_AND_INDEPENDENT_REVIEW_PASS';
        v_evidence_refs := v_evidence_refs || jsonb_build_array(
          format('supabase://public/lf_test_judge_results/%s',v_judge.judge_result_id)
        );
      else
        v_result := 'UNPROVEN';
        v_reason := 'INDEPENDENT_REVIEW_EVIDENCE_MISSING_OR_NOT_SEPARATE';
      end if;
    else
      v_result := 'PASS';
      v_reason := 'EXACT_REVISION_TEST_PASS';
    end if;
  else
    v_result := 'UNPROVEN';
    v_reason := format('TEST_RUN_NOT_TERMINAL:%s',coalesce(v_run.status,'NULL'));
  end if;

  return jsonb_build_object(
    'suite_code',p_suite_code,
    'test_code',p_test_code,
    'test_run_id',v_run.test_run_id,
    'test_run_status',v_run.status,
    'execution_mode',v_case.execution_mode,
    'result',v_result,
    'reason',v_reason,
    'evaluator_mode',v_mode,
    'evidence_refs',v_evidence_refs
  );
end;
$function$;

create or replace function public.lf_assurance_claim_resolve_core_v1(
  p_subject_type text,
  p_subject_code text,
  p_subject_revision text,
  p_claim_code text,
  p_claim_version integer,
  p_depth integer
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_claim public.lf_assurance_claim_catalog%rowtype;
  v_suite_code text;
  v_required_cases jsonb;
  v_pass_requires jsonb;
  v_case_code text;
  v_case_eval jsonb;
  v_child_code text;
  v_child_version integer;
  v_child_eval jsonb;
  v_expected_children integer := 0;
  v_mapped_children integer := 0;
  v_machine_resolved boolean := false;
  v_has_fail boolean := false;
  v_has_open boolean := false;
  v_has_unproven boolean := false;
  v_has_false_pass boolean := false;
  v_has_deterministic boolean := false;
  v_has_independent boolean := false;
  v_case_details jsonb := '[]'::jsonb;
  v_child_details jsonb := '[]'::jsonb;
  v_evidence_refs jsonb := '[]'::jsonb;
  v_gate_check_refs jsonb := '[]'::jsonb;
  v_open_defeaters jsonb := '[]'::jsonb;
  v_closed_defeaters jsonb := '[]'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
  v_result text := 'UNPROVEN';
  v_mode text := 'DETERMINISTIC';
  v_def record;
  v_obl public.lf_assurance_obligation_catalog%rowtype;
  v_ref text;
  v_def_mapped integer;
  v_def_pass integer;
  v_def_eval jsonb;
begin
  if p_depth is null or p_depth < 0 or p_depth > 16 then
    return jsonb_build_object(
      'result','UNPROVEN',
      'reasons',jsonb_build_array('CLAIM_RECURSION_DEPTH_EXCEEDED'),
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb,
      'gate_check_refs','[]'::jsonb,
      'open_defeaters','[]'::jsonb,
      'closed_defeaters','[]'::jsonb
    );
  end if;

  select * into v_claim
  from public.lf_assurance_claim_catalog
  where claim_code=p_claim_code
    and version=p_claim_version
    and status in ('ACTIVE','CANDIDATO')
  limit 1;

  if not found then
    return jsonb_build_object(
      'claim_code',p_claim_code,
      'claim_version',p_claim_version,
      'result','UNPROVEN',
      'reasons',jsonb_build_array('CLAIM_NOT_REGISTERED_OR_RETIRED'),
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb,
      'gate_check_refs','[]'::jsonb,
      'open_defeaters','[]'::jsonb,
      'closed_defeaters','[]'::jsonb
    );
  end if;

  if v_claim.subject_type is distinct from p_subject_type
     or (v_claim.subject_code <> '*' and v_claim.subject_code is distinct from p_subject_code) then
    return jsonb_build_object(
      'claim_code',p_claim_code,
      'claim_version',p_claim_version,
      'result','UNPROVEN',
      'reasons',jsonb_build_array('CLAIM_SUBJECT_BINDING_MISMATCH'),
      'evaluator_mode','DETERMINISTIC',
      'evidence_refs','[]'::jsonb,
      'gate_check_refs','[]'::jsonb,
      'open_defeaters','[]'::jsonb,
      'closed_defeaters','[]'::jsonb
    );
  end if;

  with recursive lineage as (
    select c.claim_code,c.version,c.parent_claim_code,c.parent_claim_version,0 as depth
    from public.lf_assurance_claim_catalog c
    where c.claim_code=p_claim_code and c.version=p_claim_version
    union all
    select p.claim_code,p.version,p.parent_claim_code,p.parent_claim_version,l.depth+1
    from lineage l
    join public.lf_assurance_claim_catalog p
      on p.claim_code=l.parent_claim_code
     and p.version=l.parent_claim_version
    where l.depth < 16
  )
  select b.benchmark_suite_code
    into v_suite_code
  from lineage l
  join public.lf_assurance_subject_bindings b
    on b.standard_claim_code=l.claim_code
   and b.standard_claim_version=l.version
  where b.subject_type=p_subject_type
    and b.subject_code in (p_subject_code,'*')
    and b.status in ('ACTIVE','CANDIDATO')
    and b.benchmark_suite_code is not null
  order by l.depth asc, case b.status when 'ACTIVE' then 0 else 1 end, b.created_at desc
  limit 1;

  v_required_cases := v_claim.closure_rule->'required_cases';
  if jsonb_typeof(v_required_cases)='array' and jsonb_array_length(v_required_cases)>0 then
    v_machine_resolved := true;

    if v_suite_code is null then
      v_has_unproven := true;
      v_reasons := v_reasons || jsonb_build_array('BENCHMARK_SUITE_BINDING_MISSING');
    else
      for v_case_code in
        select jsonb_array_elements_text(v_required_cases)
      loop
        v_case_eval := public.lf_assurance_case_evidence_v1(
          v_suite_code,v_case_code,p_subject_revision
        );
        v_case_details := v_case_details || jsonb_build_array(v_case_eval);
        v_evidence_refs := v_evidence_refs || coalesce(v_case_eval->'evidence_refs','[]'::jsonb);

        if v_case_eval->>'evaluator_mode'='INDEPENDENT_REVIEW' then
          v_has_independent := true;
        else
          v_has_deterministic := true;
        end if;

        case coalesce(v_case_eval->>'result','UNPROVEN')
          when 'FAIL' then v_has_fail := true;
          when 'FALSE_PASS_RISK' then v_has_false_pass := true;
          when 'OPEN' then v_has_open := true;
          when 'UNPROVEN' then v_has_unproven := true;
          when 'PASS' then null;
          else v_has_unproven := true;
        end case;
      end loop;
    end if;
  end if;

  v_pass_requires := v_claim.closure_rule->'pass_requires';
  if jsonb_typeof(v_pass_requires)='array' and jsonb_array_length(v_pass_requires)>0 then
    v_expected_children := jsonb_array_length(v_pass_requires);

    select count(*) into v_mapped_children
    from jsonb_array_elements_text(v_pass_requires) req(code)
    join public.lf_assurance_claim_catalog c
      on c.claim_code=req.code
     and c.parent_claim_code=p_claim_code
     and c.parent_claim_version=p_claim_version
     and c.status in ('ACTIVE','CANDIDATO');

    if v_mapped_children=v_expected_children then
      v_machine_resolved := true;

      for v_child_code in
        select jsonb_array_elements_text(v_pass_requires)
      loop
        select max(version) into v_child_version
        from public.lf_assurance_claim_catalog
        where claim_code=v_child_code
          and parent_claim_code=p_claim_code
          and parent_claim_version=p_claim_version
          and status in ('ACTIVE','CANDIDATO');

        v_child_eval := public.lf_assurance_claim_resolve_core_v1(
          p_subject_type,
          p_subject_code,
          p_subject_revision,
          v_child_code,
          v_child_version,
          p_depth+1
        );
        v_child_details := v_child_details || jsonb_build_array(v_child_eval);
        v_evidence_refs := v_evidence_refs || coalesce(v_child_eval->'evidence_refs','[]'::jsonb);
        v_gate_check_refs := v_gate_check_refs || coalesce(v_child_eval->'gate_check_refs','[]'::jsonb);
        v_open_defeaters := v_open_defeaters || coalesce(v_child_eval->'open_defeaters','[]'::jsonb);
        v_closed_defeaters := v_closed_defeaters || coalesce(v_child_eval->'closed_defeaters','[]'::jsonb);

        if v_child_eval->>'evaluator_mode' in ('INDEPENDENT_REVIEW','HYBRID') then
          v_has_independent := true;
        end if;
        if v_child_eval->>'evaluator_mode' in ('DETERMINISTIC','HYBRID') then
          v_has_deterministic := true;
        end if;

        case coalesce(v_child_eval->>'result','UNPROVEN')
          when 'FAIL' then v_has_fail := true;
          when 'FALSE_PASS_RISK' then v_has_false_pass := true;
          when 'OPEN' then v_has_open := true;
          when 'UNPROVEN' then v_has_unproven := true;
          when 'PASS' then null;
          else v_has_unproven := true;
        end case;
      end loop;
    elsif not v_machine_resolved then
      v_has_unproven := true;
      v_reasons := v_reasons || jsonb_build_array('PASS_REQUIRES_NOT_BOUND_TO_CHILD_CLAIMS');
    end if;
  end if;

  if not v_machine_resolved then
    v_has_unproven := true;
    v_reasons := v_reasons || jsonb_build_array('CLOSURE_RULE_NOT_MACHINE_RESOLVABLE');
  end if;

  for v_def in
    select distinct on (d.defeater_code)
      d.defeater_code,d.version,d.obligation_code,d.zero_effect_required
    from public.lf_assurance_defeater_catalog d
    where d.claim_code=p_claim_code
      and d.claim_version=p_claim_version
      and d.status in ('ACTIVE','CANDIDATO')
    order by d.defeater_code,d.version desc
  loop
    v_def_mapped := 0;
    v_def_pass := 0;

    if v_def.obligation_code is not null and v_suite_code is not null then
      select * into v_obl
      from public.lf_assurance_obligation_catalog
      where obligation_code=v_def.obligation_code
        and claim_code=p_claim_code
        and claim_version=p_claim_version
        and status in ('ACTIVE','CANDIDATO')
      order by version desc
      limit 1;

      if found then
        for v_ref in
          select ref
          from unnest(array[
            v_obl.positive_test_ref,
            v_obl.negative_test_ref,
            v_obl.adversarial_test_ref
          ]) ref
          where ref is not null
        loop
          if exists (
            select 1
            from public.lf_test_suite_cases tc
            where tc.suite_code=v_suite_code
              and tc.test_code=v_ref
              and tc.status in ('ACTIVE','CANDIDATO')
          ) then
            v_def_mapped := v_def_mapped + 1;
            v_def_eval := public.lf_assurance_case_evidence_v1(
              v_suite_code,v_ref,p_subject_revision
            );
            v_evidence_refs := v_evidence_refs || coalesce(v_def_eval->'evidence_refs','[]'::jsonb);
            if v_def_eval->>'evaluator_mode'='INDEPENDENT_REVIEW' then
              v_has_independent := true;
            else
              v_has_deterministic := true;
            end if;
            if v_def_eval->>'result'='PASS' then
              v_def_pass := v_def_pass + 1;
            end if;
          end if;
        end loop;
      end if;
    end if;

    if v_def_mapped>0 and v_def_pass=v_def_mapped then
      v_closed_defeaters := v_closed_defeaters || jsonb_build_array(v_def.defeater_code);
    else
      v_open_defeaters := v_open_defeaters || jsonb_build_array(v_def.defeater_code);
    end if;
  end loop;

  if v_has_independent and v_has_deterministic then
    v_mode := 'HYBRID';
  elsif v_has_independent then
    v_mode := 'INDEPENDENT_REVIEW';
  else
    v_mode := 'DETERMINISTIC';
  end if;

  if v_has_fail then
    v_result := 'FAIL';
  elsif v_has_false_pass then
    v_result := 'FALSE_PASS_RISK';
  elsif v_has_open then
    v_result := 'OPEN';
  elsif v_has_unproven then
    v_result := 'UNPROVEN';
  elsif jsonb_array_length(v_open_defeaters)>0 then
    v_result := 'FALSE_PASS_RISK';
    v_reasons := v_reasons || jsonb_build_array('MANDATORY_DEFEATER_NOT_CLOSED');
  else
    v_result := 'PASS';
  end if;

  return jsonb_build_object(
    'subject_type',p_subject_type,
    'subject_code',p_subject_code,
    'subject_revision',p_subject_revision,
    'claim_code',p_claim_code,
    'claim_version',p_claim_version,
    'benchmark_suite_code',v_suite_code,
    'result',v_result,
    'evaluator_mode',v_mode,
    'reasons',v_reasons,
    'evidence_refs',v_evidence_refs,
    'gate_check_refs',v_gate_check_refs,
    'open_defeaters',v_open_defeaters,
    'closed_defeaters',v_closed_defeaters,
    'required_case_results',v_case_details,
    'required_subclaim_results',v_child_details
  );
end;
$function$;

create or replace function public.lf_assurance_claim_evaluate_v1(
  p_subject_type text,
  p_subject_code text,
  p_subject_revision text,
  p_claim_code text,
  p_claim_version integer default 1
)
returns jsonb
language sql
stable
security invoker
set search_path to 'pg_catalog','public'
as $function$
  select public.lf_assurance_claim_resolve_core_v1(
    p_subject_type,
    p_subject_code,
    p_subject_revision,
    p_claim_code,
    p_claim_version,
    0
  );
$function$;

create or replace function public.lf_assurance_claim_evaluate_and_record_v1(
  p_subject_type text,
  p_subject_code text,
  p_subject_revision text,
  p_claim_code text,
  p_claim_version integer,
  p_execution_id text,
  p_actor_execution_id text
)
returns uuid
language plpgsql
volatile
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_eval jsonb;
  v_result text;
  v_mode text;
  v_existing uuid;
  v_inserted uuid;
begin
  if nullif(btrim(coalesce(p_subject_revision,'')),'') is null then
    raise exception 'LF_ASSURANCE_EVALUATOR_SUBJECT_REVISION_REQUIRED';
  end if;

  if nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null then
    raise exception 'LF_ASSURANCE_EVALUATOR_ACTOR_EXECUTION_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id=p_actor_execution_id
  ) then
    raise exception 'LF_ASSURANCE_EVALUATOR_ACTOR_EXECUTION_NOT_FOUND:%',p_actor_execution_id;
  end if;

  v_eval := public.lf_assurance_claim_evaluate_v1(
    p_subject_type,
    p_subject_code,
    p_subject_revision,
    p_claim_code,
    p_claim_version
  );

  v_result := coalesce(v_eval->>'result','UNPROVEN');
  v_mode := coalesce(v_eval->>'evaluator_mode','DETERMINISTIC');

  select evaluation_id into v_existing
  from public.lf_assurance_evaluations
  where subject_type=p_subject_type
    and subject_code=p_subject_code
    and subject_revision is not distinct from p_subject_revision
    and claim_code=p_claim_code
    and claim_version=p_claim_version
    and obligation_code is null
    and execution_id is not distinct from p_execution_id
    and result=v_result
    and evidence_refs=coalesce(v_eval->'evidence_refs','[]'::jsonb)
    and gate_check_refs=coalesce(v_eval->'gate_check_refs','[]'::jsonb)
    and open_defeaters=coalesce(v_eval->'open_defeaters','[]'::jsonb)
    and closed_defeaters=coalesce(v_eval->'closed_defeaters','[]'::jsonb)
    and evaluator_mode=v_mode
  order by observed_at desc
  limit 1;

  if found then
    return v_existing;
  end if;

  insert into public.lf_assurance_evaluations (
    subject_type,
    subject_code,
    subject_revision,
    claim_code,
    claim_version,
    obligation_code,
    execution_id,
    result,
    evidence_refs,
    gate_check_refs,
    open_defeaters,
    closed_defeaters,
    failure_type,
    evaluator_mode,
    rationale,
    created_by_execution_id
  ) values (
    p_subject_type,
    p_subject_code,
    p_subject_revision,
    p_claim_code,
    p_claim_version,
    null,
    p_execution_id,
    v_result,
    coalesce(v_eval->'evidence_refs','[]'::jsonb),
    coalesce(v_eval->'gate_check_refs','[]'::jsonb),
    coalesce(v_eval->'open_defeaters','[]'::jsonb),
    coalesce(v_eval->'closed_defeaters','[]'::jsonb),
    case when v_result='PASS' then null else coalesce(v_eval->'reasons'->>0,v_result) end,
    v_mode,
    coalesce((v_eval->'reasons')::text,'[]'),
    p_actor_execution_id
  )
  returning evaluation_id into v_inserted;

  return v_inserted;
end;
$function$;

revoke all on function public.lf_assurance_case_evidence_v1(text,text,text) from public,anon,authenticated;
revoke all on function public.lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer) from public,anon,authenticated;
revoke all on function public.lf_assurance_claim_evaluate_v1(text,text,text,text,integer) from public,anon,authenticated;
revoke all on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) from public,anon,authenticated;

grant execute on function public.lf_assurance_case_evidence_v1(text,text,text) to service_role;
grant execute on function public.lf_assurance_claim_evaluate_v1(text,text,text,text,integer) to service_role;
grant execute on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) to service_role;

comment on function public.lf_assurance_claim_evaluate_v1(text,text,text,text,integer) is
'LF transversal assurance evaluator v1. Resolves machine-readable required_cases and child-claim pass_requires from canonical test evidence at exact subject revision; missing evidence remains UNPROVEN and open defeaters prevent PASS.';

comment on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) is
'Append-only recorder for a deterministic/hybrid assurance evaluation derived by lf_assurance_claim_evaluate_v1. Does not accept caller-declared PASS.';
