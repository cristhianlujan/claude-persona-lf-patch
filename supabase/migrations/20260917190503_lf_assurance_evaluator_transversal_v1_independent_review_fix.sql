-- LF_ASSURANCE_EVALUATOR_TRANSVERSAL_V1_INDEPENDENT_REVIEW_FIX
-- Same T01 solution. Temporary source-layer correction before final consolidation.
-- Fixes the canonical independent-review flow: REVIEW_REQUIRED + governed PASS judge
-- can prove the case; materialized PASS/PASSED still requires that same judge lineage.
-- No data mutation, no runtime activation, no consumer binding change.

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
  v_nonpass_judge text;
begin
  if nullif(btrim(coalesce(p_suite_code,'')),'') is null
     or nullif(btrim(coalesce(p_test_code,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,'test_code',p_test_code,
      'result','UNPROVEN','reason','CASE_IDENTITY_MISSING',
      'evaluator_mode','DETERMINISTIC','zero_effect_proven',false,
      'counterevidence','[]'::jsonb,'evidence_refs','[]'::jsonb
    );
  end if;

  if nullif(btrim(coalesce(p_subject_revision,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,'test_code',p_test_code,
      'result','UNPROVEN','reason','SUBJECT_REVISION_REQUIRED',
      'evaluator_mode','DETERMINISTIC','zero_effect_proven',false,
      'counterevidence','[]'::jsonb,'evidence_refs','[]'::jsonb
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
      'suite_code',p_suite_code,'test_code',p_test_code,
      'result','UNPROVEN','reason','REQUIRED_CASE_NOT_REGISTERED',
      'evaluator_mode','DETERMINISTIC','zero_effect_proven',false,
      'counterevidence','[]'::jsonb,'evidence_refs','[]'::jsonb
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
      'suite_code',p_suite_code,'test_code',p_test_code,
      'result','UNPROVEN','reason','EXACT_REVISION_RUN_MISSING',
      'execution_mode',v_case.execution_mode,
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'zero_effect_proven',false,'counterevidence','[]'::jsonb,'evidence_refs','[]'::jsonb
    );
  end if;

  v_run_status := upper(btrim(coalesce(v_run.status,'')));
  v_evidence_refs := jsonb_build_array(format('supabase://public/lf_test_runs/%s',v_run.test_run_id));

  if nullif(btrim(coalesce(v_run.execution_id,'')),'') is null then
    return jsonb_build_object(
      'suite_code',p_suite_code,'test_code',p_test_code,'test_run_id',v_run.test_run_id,
      'test_run_status',v_run.status,'execution_mode',v_case.execution_mode,
      'result','UNPROVEN','reason','RUN_EXECUTION_ID_MISSING',
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'zero_effect_proven',false,'counterevidence','[]'::jsonb,'evidence_refs',v_evidence_refs
    );
  end if;

  if not exists (
    select 1 from public.lf_operation_execution oe where oe.execution_id=v_run.execution_id
  ) then
    return jsonb_build_object(
      'suite_code',p_suite_code,'test_code',p_test_code,'test_run_id',v_run.test_run_id,
      'test_run_status',v_run.status,'execution_mode',v_case.execution_mode,
      'result','UNPROVEN','reason','RUN_EXECUTION_NOT_GOVERNED',
      'evaluator_mode',case when v_case.execution_mode='INDEPENDENT_REVIEW' then 'INDEPENDENT_REVIEW' else 'DETERMINISTIC' end,
      'zero_effect_proven',false,'counterevidence','[]'::jsonb,'evidence_refs',v_evidence_refs
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (where upper(btrim(coalesce(status,'')))='FAIL')::integer,
    count(*) filter (where upper(btrim(coalesce(status,'')))<>'PASS')::integer
  into v_assertion_total,v_assertion_fail,v_assertion_nonpass
  from public.lf_test_assertion_results
  where test_run_id=v_run.test_run_id;

  select count(*)::integer into v_artifact_total
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

  elsif v_case.execution_mode='INDEPENDENT_REVIEW'
        and v_run_status in ('REVIEW_REQUIRED','PASS','PASSED') then
    v_mode := 'INDEPENDENT_REVIEW';

    if v_assertion_fail > 0 then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'INDEPENDENT_RUN_CONTAINS_FAILED_ASSERTION';
    elsif v_assertion_nonpass > 0 then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'INDEPENDENT_RUN_CONTAINS_NONPASS_ASSERTION';
    elsif not v_expected_matches then
      v_result := 'FALSE_PASS_RISK';
      v_reason := 'INDEPENDENT_RUN_EXPECTED_OUTPUT_NOT_PROVEN';
    elsif not v_durable_evidence then
      v_result := 'UNPROVEN';
      v_reason := 'INDEPENDENT_RUN_DURABLE_EVIDENCE_MISSING';
    else
      select j.verdict into v_nonpass_judge
      from public.lf_test_judge_results j
      where j.test_run_id=v_run.test_run_id
        and j.verdict<>'PASS'
        and j.metadata->>'recorder'='lf_record_test_judge_result_v1'
        and j.metadata->>'reviewer_execution_id'=j.created_by_execution_id
        and nullif(btrim(coalesce(j.created_by_execution_id,'')),'') is not null
        and j.created_by_execution_id<>'UNKNOWN'
      order by case j.verdict when 'FAIL' then 0 else 1 end,j.observed_at desc,j.created_at desc
      limit 1;

      if v_nonpass_judge='FAIL' then
        v_result := 'FAIL';
        v_reason := 'INDEPENDENT_REVIEW_FAIL_JUDGE_PRESENT';
      elsif v_nonpass_judge is not null then
        v_result := 'OPEN';
        v_reason := format('INDEPENDENT_REVIEW_NONPASS_JUDGE:%s',v_nonpass_judge);
      else
        select j.* into v_judge
        from public.lf_test_judge_results j
        join public.lf_operation_execution reviewer
          on reviewer.execution_id=j.created_by_execution_id
        where j.test_run_id=v_run.test_run_id
          and j.verdict='PASS'
          and j.judge_type in ('INDEPENDENT_HOLDOUT','S36_ASSURANCE')
          and j.metadata->>'recorder'='lf_record_test_judge_result_v1'
          and j.metadata->>'reviewer_execution_id'=j.created_by_execution_id
          and j.metadata->>'test_producer_execution_id'=v_run.execution_id
          and j.created_by_execution_id<>v_run.execution_id
          and coalesce(j.evidence_payload,'{}'::jsonb)<>'{}'::jsonb
          and (
            v_run.operation_code is null
            or reviewer.operation_code is distinct from v_run.operation_code
          )
          and (
            j.metadata->>'reviewer_operation_code' is null
            or j.metadata->>'reviewer_operation_code'=reviewer.operation_code
          )
        order by j.observed_at desc,j.created_at desc
        limit 1;

        if found then
          v_result := 'PASS';
          v_reason := case when v_run_status='REVIEW_REQUIRED'
            then 'REVIEW_REQUIRED_WITH_CANONICAL_INDEPENDENT_PASS'
            else 'MATERIALIZED_PASS_WITH_CANONICAL_INDEPENDENT_PASS'
          end;
          v_evidence_refs := v_evidence_refs || jsonb_build_array(
            format('supabase://public/lf_test_judge_results/%s',v_judge.judge_result_id)
          );
        elsif v_run_status in ('PASS','PASSED') then
          v_result := 'FALSE_PASS_RISK';
          v_reason := 'MATERIALIZED_INDEPENDENT_PASS_WITHOUT_CANONICAL_JUDGE';
        else
          v_result := 'OPEN';
          v_reason := 'INDEPENDENT_REVIEW_PENDING';
        end if;
      end if;
    end if;

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
    else
      v_result := 'PASS';
      v_reason := 'EXACT_REVISION_TEST_PASS';
    end if;

  else
    v_result := 'UNPROVEN';
    v_reason := format('TEST_RUN_STATUS_UNKNOWN:%s',coalesce(v_run_status,'NULL'));
  end if;

  return jsonb_build_object(
    'suite_code',p_suite_code,'test_code',p_test_code,'test_run_id',v_run.test_run_id,
    'test_run_status',v_run.status,'execution_id',v_run.execution_id,
    'execution_mode',v_case.execution_mode,'result',v_result,'reason',v_reason,
    'evaluator_mode',v_mode,'assertion_total',v_assertion_total,'assertion_fail',v_assertion_fail,
    'expected_output_proven',v_expected_matches,'durable_evidence_proven',v_durable_evidence,
    'zero_effect_proven',v_zero_effect_proven,'counterevidence',v_counterevidence,
    'evidence_refs',v_evidence_refs
  );
end;
$function$;

revoke all on function public.lf_assurance_case_evidence_v1(text,text,text) from public,anon,authenticated;
grant execute on function public.lf_assurance_case_evidence_v1(text,text,text) to service_role;

comment on function public.lf_assurance_case_evidence_v1(text,text,text) is
'LF assurance evidence resolver v1: exact-revision governed evidence with PASS/PASSED and FAIL/FAILED normalization. INDEPENDENT_REVIEW requires canonical lf_record_test_judge_result_v1 lineage, distinct reviewer execution/operation and durable PASS evidence; REVIEW_REQUIRED remains valid pre-materialization state when the canonical independent PASS exists.';