-- LF_ASSURANCE_EVALUATOR_TRANSVERSAL_V1_CONTROL_HARDENING
-- Same single solution/PR as 20260917190500/190501.
-- Control hardening only: no runtime activation, no data mutation, no consumer binding change.
-- Fail-closed goals:
--   * normalize canonical test run terminal aliases (PASS/PASSED, FAIL/FAILED);
--   * exact-revision and governed-execution provenance;
--   * assertion contradiction detection;
--   * expected/actual containment and durable evidence requirement;
--   * independent review with separate governed execution;
--   * defeaters close only from machine-resolvable negative/adversarial counterevidence;
--   * zero-effect and declared counterevidence requirements are enforced;
--   * evaluation recorder is execution-bound and concurrency-idempotent.

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
  v_run_status text;
  v_result text := 'UNPROVEN';
  v_reason text := null;
  v_mode text := 'DETERMINISTIC';
  v_assertion_total integer := 0;
  v_assertion_fail integer := 0;
  v_assertion_nonpass integer := 0;
  v_artifact_total integer := 0;
  v_zero_effect_proven boolean := false;
  v_expected_matches boolean := false;
  v_durable_evidence boolean := false;
  v_counterevidence jsonb := '[]'::jsonb;
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
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
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
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
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
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
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
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
      'evidence_refs','[]'::jsonb
    );
  end if;

  v_run_status := upper(btrim(coalesce(v_run.status,'')));
  v_evidence_refs := jsonb_build_array(
    format('supabase://public/lf_test_runs/%s',v_run.test_run_id)
  );

  if nullif(btrim(coalesce(v_run.execution_id,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'test_run_id',v_run.test_run_id,
      'test_run_status',v_run.status,
      'execution_mode',v_case.execution_mode,
      'result','UNPROVEN',
      'reason','RUN_EXECUTION_ID_MISSING',
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
      'evidence_refs',v_evidence_refs
    );
  end if;

  if not exists (
    select 1
    from public.lf_operation_execution oe
    where oe.execution_id=v_run.execution_id
  ) then
    return jsonb_build_object(
      'suite_code',p_suite_code,
      'test_code',p_test_code,
      'test_run_id',v_run.test_run_id,
      'test_run_status',v_run.status,
      'execution_mode',v_case.execution_mode,
      'result','UNPROVEN',
      'reason','RUN_EXECUTION_NOT_GOVERNED',
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'zero_effect_proven',false,
      'counterevidence','[]'::jsonb,
      'evidence_refs',v_evidence_refs
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (where upper(btrim(coalesce(status,'')))='FAIL')::integer,
    count(*) filter (where upper(btrim(coalesce(status,'')))<>'PASS')::integer
  into v_assertion_total,v_assertion_fail,v_assertion_nonpass
  from public.lf_test_assertion_results
  where test_run_id=v_run.test_run_id;

  select count(*)::integer
  into v_artifact_total
  from public.lf_test_artifacts
  where test_run_id=v_run.test_run_id;

  v_expected_matches := coalesce(v_run.actual_output,'{}'::jsonb) @> coalesce(v_case.expected_output,'{}'::jsonb);
  v_durable_evidence :=
    coalesce(v_run.evidence_payload,'{}'::jsonb) <> '{}'::jsonb
    or v_assertion_total > 0
    or v_artifact_total > 0;

  if jsonb_typeof(v_run.evidence_payload->'counterevidence')='array' then
    v_counterevidence := v_run.evidence_payload->'counterevidence';
  end if;

  v_zero_effect_proven :=
    coalesce(case when jsonb_typeof(v_run.actual_output->'zero_effect')='boolean' then (v_run.actual_output->>'zero_effect')::boolean end,false)
    or coalesce(case when jsonb_typeof(v_run.actual_output->'zero_effect_on_fail')='boolean' then (v_run.actual_output->>'zero_effect_on_fail')::boolean end,false)
    or coalesce(case when jsonb_typeof(v_run.actual_output->'zero_effect_on_failure')='boolean' then (v_run.actual_output->>'zero_effect_on_failure')::boolean end,false)
    or coalesce(case when jsonb_typeof(v_run.actual_output->'zero_effect_on_unproven')='boolean' then (v_run.actual_output->>'zero_effect_on_unproven')::boolean end,false)
    or coalesce(case when jsonb_typeof(v_run.evidence_payload->'zero_effect')='boolean' then (v_run.evidence_payload->>'zero_effect')::boolean end,false)
    or coalesce(case when jsonb_typeof(v_run.evidence_payload->'zero_effect_on_failure')='boolean' then (v_run.evidence_payload->>'zero_effect_on_failure')::boolean end,false);

  if v_run_status in ('FAIL','FAILED') then
    v_result := 'FAIL';
    v_reason := 'TEST_RUN_FAILED';
  elsif v_run_status in ('BLOCKED','PARTIAL_BLOCKED','REVIEW_REQUIRED','IN_PROGRESS','QUEUED','RUNNING','PENDING','PARTIAL_REHEARSAL') then
    v_result := 'OPEN';
    v_reason := format('TEST_RUN_NOT_CLOSED:%s',v_run_status);
  elsif v_run_status in ('PASS','PASSED') then
    if v_assertion_fail > 0 then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'PASS_RUN_CONTAINS_FAILED_ASSERTION';
    elsif v_assertion_nonpass > 0 then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'PASS_RUN_CONTAINS_NONPASS_ASSERTION';
    elsif not v_expected_matches then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'PASS_RUN_EXPECTED_OUTPUT_NOT_PROVEN';
    elsif not v_durable_evidence then
      v_result := 'UNPROVEN';
      v_reason := 'PASS_RUN_DURABLE_EVIDENCE_MISSING';
    elsif v_case.execution_mode='INDEPENDENT_REVIEW' then
      v_mode := 'INDEPENDENT_REVIEW';

      select j.* into v_judge
      from public.lf_test_judge_results j
      where j.test_run_id=v_run.test_run_id
        and j.verdict='PASS'
        and nullif(btrim(coalesce(j.created_by_execution_id,'')),'') is not null
        and j.created_by_execution_id <> 'UNKNOWN'
        and j.created_by_execution_id <> v_run.execution_id
        and coalesce(j.evidence_payload,'{}'::jsonb) <> '{}'::jsonb
        and exists (
          select 1
          from public.lf_operation_execution oe
          where oe.execution_id=j.created_by_execution_id
        )
      order by j.observed_at desc, j.created_at desc
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
    v_reason := format('TEST_RUN_STATUS_UNKNOWN:%s',coalesce(v_run_status,'NULL'));
  end if;

  return jsonb_build_object(
    'suite_code',p_suite_code,
    'test_code',p_test_code,
    'test_run_id',v_run.test_run_id,
    'test_run_status',v_run.status,
    'execution_id',v_run.execution_id,
    'execution_mode',v_case.execution_mode,
    'result',v_result,
    'reason',v_reason,
    'evaluator_mode',v_mode,
    'assertion_total',v_assertion_total,
    'assertion_fail',v_assertion_fail,
    'expected_output_proven',v_expected_matches,
    'durable_evidence_proven',v_durable_evidence,
    'zero_effect_proven',v_zero_effect_proven,
    'counterevidence',v_counterevidence,
    'evidence_refs',v_evidence_refs
  );
end;
$function$;

create or replace function public.lf_assurance_defeater_evidence_v1(
  p_suite_code text,
  p_subject_revision text,
  p_defeater_code text,
  p_defeater_version integer
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_def public.lf_assurance_defeater_catalog%rowtype;
  v_obl public.lf_assurance_obligation_catalog%rowtype;
  v_ref text;
  v_eval jsonb;
  v_mapped integer := 0;
  v_passed integer := 0;
  v_zero_effect_seen boolean := false;
  v_counterevidence jsonb := '[]'::jsonb;
  v_required_labels jsonb := '[]'::jsonb;
  v_required_label text;
  v_required_ok boolean := true;
  v_unknown_contract_keys integer := 0;
  v_case_results jsonb := '[]'::jsonb;
  v_evidence_refs jsonb := '[]'::jsonb;
begin
  select * into v_def
  from public.lf_assurance_defeater_catalog
  where defeater_code=p_defeater_code
    and version=p_defeater_version
    and status in ('ACTIVE','CANDIDATO')
  limit 1;

  if not found then
    return jsonb_build_object(
      'defeater_code',p_defeater_code,
      'closed',false,
      'reason','DEFEATER_NOT_REGISTERED',
      'evidence_refs','[]'::jsonb
    );
  end if;

  if v_def.obligation_code is null or p_suite_code is null then
    return jsonb_build_object(
      'defeater_code',v_def.defeater_code,
      'closed',false,
      'reason','DEFEATER_MACHINE_BINDING_MISSING',
      'evidence_refs','[]'::jsonb
    );
  end if;

  select * into v_obl
  from public.lf_assurance_obligation_catalog
  where obligation_code=v_def.obligation_code
    and claim_code=v_def.claim_code
    and claim_version=v_def.claim_version
    and status in ('ACTIVE','CANDIDATO')
  order by version desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'defeater_code',v_def.defeater_code,
      'closed',false,
      'reason','DEFEATER_OBLIGATION_MISSING',
      'evidence_refs','[]'::jsonb
    );
  end if;

  -- A defeater is countered only by negative/adversarial proof, never by the happy path.
  for v_ref in
    with raw_refs as (
      select negative_test_ref as raw_ref
      union all
      select adversarial_test_ref
    )
    select btrim(piece)
    from raw_refs r
    cross join lateral regexp_split_to_table(coalesce(r.raw_ref,''),',') piece
    where nullif(btrim(piece),'') is not null
  loop
    if exists (
      select 1
      from public.lf_test_suite_cases tc
      where tc.suite_code=p_suite_code
        and tc.test_code=v_ref
        and tc.status in ('ACTIVE','CANDIDATO')
    ) then
      v_mapped := v_mapped + 1;
      v_eval := public.lf_assurance_case_evidence_v1(
        p_suite_code,v_ref,p_subject_revision
      );
      v_case_results := v_case_results || jsonb_build_array(v_eval);
      v_evidence_refs := v_evidence_refs || coalesce(v_eval->'evidence_refs','[]'::jsonb);
      if v_eval->>'result'='PASS' then
        v_passed := v_passed + 1;
      end if;
      if coalesce((v_eval->>'zero_effect_proven')::boolean,false) then
        v_zero_effect_seen := true;
      end if;
      if jsonb_typeof(v_eval->'counterevidence')='array' then
        v_counterevidence := v_counterevidence || (v_eval->'counterevidence');
      end if;
    end if;
  end loop;

  -- Only a small declared contract is machine-resolvable. Unknown keys stay open.
  select count(*)::integer
  into v_unknown_contract_keys
  from jsonb_object_keys(coalesce(v_def.required_counterevidence,'{}'::jsonb)) k
  where k not in ('required','test','test_ref','tests');

  if v_unknown_contract_keys > 0 then
    v_required_ok := false;
  end if;

  if v_def.required_counterevidence ? 'required' then
    if jsonb_typeof(v_def.required_counterevidence->'required')='array' then
      v_required_labels := v_def.required_counterevidence->'required';
    elsif jsonb_typeof(v_def.required_counterevidence->'required')='string' then
      v_required_labels := jsonb_build_array(v_def.required_counterevidence->>'required');
    else
      v_required_ok := false;
    end if;
  end if;

  if v_def.required_counterevidence ? 'tests' then
    if jsonb_typeof(v_def.required_counterevidence->'tests')='array' then
      v_required_labels := v_required_labels || (v_def.required_counterevidence->'tests');
    else
      v_required_ok := false;
    end if;
  end if;

  if v_def.required_counterevidence ? 'test' then
    if jsonb_typeof(v_def.required_counterevidence->'test')='string' then
      v_required_labels := v_required_labels || jsonb_build_array(v_def.required_counterevidence->>'test');
    else
      v_required_ok := false;
    end if;
  end if;

  if v_def.required_counterevidence ? 'test_ref' then
    if jsonb_typeof(v_def.required_counterevidence->'test_ref')='string' then
      v_required_labels := v_required_labels || jsonb_build_array(v_def.required_counterevidence->>'test_ref');
    else
      v_required_ok := false;
    end if;
  end if;

  for v_required_label in
    select distinct value
    from jsonb_array_elements_text(v_required_labels)
  loop
    if not exists (
      select 1
      from jsonb_array_elements_text(v_counterevidence) ce(value)
      where ce.value=v_required_label
    ) then
      v_required_ok := false;
    end if;
  end loop;

  return jsonb_build_object(
    'defeater_code',v_def.defeater_code,
    'defeater_version',v_def.version,
    'closed',(
      v_mapped > 0
      and v_passed=v_mapped
      and v_required_ok
      and (not v_def.zero_effect_required or v_zero_effect_seen)
    ),
    'reason',case
      when v_mapped=0 then 'DEFEATER_NEGATIVE_ADVERSARIAL_CASE_UNMAPPED'
      when v_passed<>v_mapped then 'DEFEATER_COUNTERTEST_NOT_PASS'
      when not v_required_ok then 'DEFEATER_COUNTEREVIDENCE_CONTRACT_UNPROVEN'
      when v_def.zero_effect_required and not v_zero_effect_seen then 'DEFEATER_ZERO_EFFECT_UNPROVEN'
      else 'DEFEATER_COUNTEREVIDENCE_CLOSED'
    end,
    'zero_effect_required',v_def.zero_effect_required,
    'zero_effect_proven',v_zero_effect_seen,
    'mapped_countertests',v_mapped,
    'passed_countertests',v_passed,
    'required_counterevidence',v_def.required_counterevidence,
    'counterevidence_observed',v_counterevidence,
    'case_results',v_case_results,
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
  v_defeater_details jsonb := '[]'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
  v_result text := 'UNPROVEN';
  v_mode text := 'DETERMINISTIC';
  v_def record;
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

  if nullif(btrim(coalesce(p_subject_revision,'')),'') is null then
    return jsonb_build_object(
      'claim_code',p_claim_code,
      'claim_version',p_claim_version,
      'result','UNPROVEN',
      'reasons',jsonb_build_array('SUBJECT_REVISION_REQUIRED'),
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
    and b.required=true
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
      d.defeater_code,d.version
    from public.lf_assurance_defeater_catalog d
    where d.claim_code=p_claim_code
      and d.claim_version=p_claim_version
      and d.status in ('ACTIVE','CANDIDATO')
    order by d.defeater_code,d.version desc
  loop
    v_def_eval := public.lf_assurance_defeater_evidence_v1(
      v_suite_code,p_subject_revision,v_def.defeater_code,v_def.version
    );
    v_defeater_details := v_defeater_details || jsonb_build_array(v_def_eval);
    v_evidence_refs := v_evidence_refs || coalesce(v_def_eval->'evidence_refs','[]'::jsonb);

    if coalesce((v_def_eval->>'closed')::boolean,false) then
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
    'defeater_results',v_defeater_details,
    'required_case_results',v_case_details,
    'required_subclaim_results',v_child_details
  );
end;
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
  v_lock_key bigint;
begin
  if nullif(btrim(coalesce(p_subject_revision,'')),'') is null then
    raise exception 'LF_ASSURANCE_EVALUATOR_SUBJECT_REVISION_REQUIRED';
  end if;

  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception 'LF_ASSURANCE_EVALUATOR_EXECUTION_REQUIRED';
  end if;

  if nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null
     or p_actor_execution_id='UNKNOWN' then
    raise exception 'LF_ASSURANCE_EVALUATOR_ACTOR_EXECUTION_REQUIRED';
  end if;

  if not exists (
    select 1 from public.lf_operation_execution where execution_id=p_execution_id
  ) then
    raise exception 'LF_ASSURANCE_EVALUATOR_EXECUTION_NOT_FOUND:%',p_execution_id;
  end if;

  if not exists (
    select 1 from public.lf_operation_execution where execution_id=p_actor_execution_id
  ) then
    raise exception 'LF_ASSURANCE_EVALUATOR_ACTOR_EXECUTION_NOT_FOUND:%',p_actor_execution_id;
  end if;

  v_lock_key := hashtextextended(
    concat_ws('|',p_subject_type,p_subject_code,p_subject_revision,p_claim_code,p_claim_version::text,p_execution_id),
    0
  );
  perform pg_advisory_xact_lock(v_lock_key);

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
    and execution_id=p_execution_id
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
revoke all on function public.lf_assurance_defeater_evidence_v1(text,text,text,integer) from public,anon,authenticated;
revoke all on function public.lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer) from public,anon,authenticated;
revoke all on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) from public,anon,authenticated;

grant execute on function public.lf_assurance_case_evidence_v1(text,text,text) to service_role;
grant execute on function public.lf_assurance_defeater_evidence_v1(text,text,text,integer) to service_role;
grant execute on function public.lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer) to service_role;
grant execute on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) to service_role;

comment on function public.lf_assurance_case_evidence_v1(text,text,text) is
'LF assurance evidence resolver v1 hardened: exact revision, governed execution, assertion consistency, expected/actual proof, durable evidence and independent-review separation. PASS/PASSED and FAIL/FAILED aliases are normalized fail-closed.';

comment on function public.lf_assurance_defeater_evidence_v1(text,text,text,integer) is
'LF assurance defeater resolver v1: closes a defeater only from machine-resolvable negative/adversarial counterevidence, declared counterevidence labels and zero-effect proof when required.';

comment on function public.lf_assurance_claim_evaluate_and_record_v1(text,text,text,text,integer,text,text) is
'Append-only LF assurance recorder hardened with evaluated-execution and actor-execution existence checks plus transaction advisory locking for concurrent idempotency. Caller cannot declare PASS.';