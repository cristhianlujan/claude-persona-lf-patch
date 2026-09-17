-- LF_ASSURANCE_EVALUATOR_TRANSVERSAL_V1_HARDENING
-- Same solution/PR as 20260917190500. Tightens independent-review provenance
-- and grants the private resolver core only to service_role so the public wrapper
-- can call it under SECURITY INVOKER. No runtime activation or data mutation.

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

      select j.* into v_judge
      from public.lf_test_judge_results j
      where j.test_run_id=v_run.test_run_id
        and j.verdict='PASS'
        and nullif(btrim(coalesce(j.created_by_execution_id,'')),'') is not null
        and j.created_by_execution_id <> 'UNKNOWN'
        and v_run.execution_id is not null
        and j.created_by_execution_id <> v_run.execution_id
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

revoke all on function public.lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.lf_assurance_claim_resolve_core_v1(text,text,text,text,integer,integer) to service_role;
