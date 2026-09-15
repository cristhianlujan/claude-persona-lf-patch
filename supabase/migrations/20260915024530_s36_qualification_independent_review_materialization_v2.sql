-- S36 — qualification independent-review materialization repair v2
-- Defect: STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-FINALIZER-SUITE-STATE-GAP-001
-- Scope: qualification/test evidence only. No runtime, production, Golden, or business-effect activation.
-- Source-first branch: s36-qual-review-materialization-fix-20260914
-- Rollback: restore public.lf_finalize_qualification_independent_review_v1 from
--           20260914230317_s36_qualification_independent_review_finalizer_v1.sql.
-- Design: no new public helper is introduced. Materialization remains inside the existing finalizer
--         so reviewer-independence/currentness/suite-fingerprint checks are non-skippable.

create or replace function public.lf_finalize_qualification_independent_review_v1(
  p_qualification_id uuid,
  p_reviewer_execution_id text,
  p_review_ref jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  q public.lf_qualification_receipts%rowtype;
  reviewer public.lf_operation_execution%rowtype;
  v_current_revision text;
  v_current_fingerprint text;
  v_snapshot_id bigint;
  v_failed_suites integer := 0;
  v_review_total integer := 0;
  v_review_passed integer := 0;
  v_review_nonpass integer := 0;
  v_materialized_tests integer := 0;
  v_nonpassed_suites integer := 0;
  v_next_state text;
  v_review_type text;
begin
  if p_qualification_id is null or nullif(btrim(p_reviewer_execution_id),'') is null then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_IDENTITY_REQUIRED');
  end if;

  if p_review_ref is null or jsonb_typeof(p_review_ref) is distinct from 'object' then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_REF_INVALID');
  end if;

  v_review_type := upper(coalesce(p_review_ref->>'review_type',''));
  if v_review_type not in ('INDEPENDENT_HOLDOUT','S36_ASSURANCE') then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_TYPE_INVALID');
  end if;

  if (p_review_ref->>'assessor_execution_id') is distinct from p_reviewer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_ASSESSOR_BINDING_MISMATCH');
  end if;

  if jsonb_typeof(p_review_ref->'evidence_refs') is distinct from 'array'
     or jsonb_array_length(p_review_ref->'evidence_refs') = 0 then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_EVIDENCE_REFS_REQUIRED');
  end if;

  select * into q
  from public.lf_qualification_receipts
  where qualification_id=p_qualification_id
  for update;

  if not found then
    return jsonb_build_object('result','BLOCKED','code','QUALIFICATION_NOT_FOUND');
  end if;

  if q.lifecycle_state_code is distinct from 'QUAL_QUALIFYING' then
    return jsonb_build_object('result','BLOCKED','code','QUALIFICATION_NOT_QUALIFYING','state',q.lifecycle_state_code);
  end if;

  if q.created_by_execution_id is not distinct from p_reviewer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_NOT_INDEPENDENT');
  end if;

  select * into reviewer
  from public.lf_operation_execution e
  where e.execution_id=p_reviewer_execution_id;

  if not found then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_ASSESSOR_EXECUTION_NOT_FOUND');
  end if;

  if reviewer.status is distinct from 'COMPLETED' or reviewer.completed_at is null then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_ASSESSOR_NOT_COMPLETED','reviewer_status',reviewer.status);
  end if;

  if q.subject_type='OPERATION' and reviewer.operation_code is not distinct from q.subject_code then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_ASSESSOR_OPERATION_NOT_INDEPENDENT','operation_code',reviewer.operation_code);
  end if;

  if q.subject_type='OPERATION' then
    v_current_revision := public.lf_operation_revision_sha256_v1(q.subject_code);
  elsif q.subject_type='STRATEGY' then
    select id into v_snapshot_id
    from public.lf_strategy_snapshots
    where snapshot_code=q.subject_code
    order by id desc
    limit 1;
    if v_snapshot_id is null then
      return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_STRATEGY_NOT_FOUND');
    end if;
    v_current_revision := public.lf_strategy_revision_sha256_v1(v_snapshot_id);
  else
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_SUBJECT_TYPE_UNSUPPORTED','subject_type',q.subject_type);
  end if;

  if v_current_revision is distinct from q.revision_sha256 then
    return jsonb_build_object(
      'result','BLOCKED','code','QUAL_REVIEW_STALE_REVISION',
      'receipt_revision',q.revision_sha256,'current_revision',v_current_revision
    );
  end if;

  v_current_fingerprint := public.lf_required_test_suite_fingerprint_v1(q.subject_type,q.subject_code);
  if v_current_fingerprint is distinct from q.suite_set_fingerprint then
    return jsonb_build_object(
      'result','BLOCKED','code','QUAL_REVIEW_SUITE_SET_STALE',
      'receipt_fingerprint',q.suite_set_fingerprint,'current_fingerprint',v_current_fingerprint
    );
  end if;

  if coalesce(cardinality(q.suite_run_ids),0)=0 then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_NO_SUITE_RUNS');
  end if;

  select count(*) into v_failed_suites
  from public.lf_test_suite_runs sr
  where sr.suite_run_id=any(q.suite_run_ids)
    and sr.status='FAILED';

  if v_failed_suites>0 then
    v_next_state := public.lf_lifecycle_resolve_transition_v1(
      'QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'FAIL_QUALIFICATION'
    );
    update public.lf_qualification_receipts
    set lifecycle_state_code=v_next_state,
        independent_review_ref=p_review_ref || jsonb_build_object(
          'finalizer','lf_finalize_qualification_independent_review_v1',
          'reviewed_at',clock_timestamp(),
          'reviewer_operation_code',reviewer.operation_code,
          'failed_suite_count',v_failed_suites
        ),
        findings=findings || jsonb_build_array(jsonb_build_object('type','MATRIX_FAILED_BEFORE_INDEPENDENT_REVIEW')),
        updated_at=clock_timestamp(),
        updated_by_execution_id=p_reviewer_execution_id
    where qualification_id=p_qualification_id;
    return jsonb_build_object('result','FAILED','code','QUAL_REVIEW_MATRIX_FAILED','qualification_id',p_qualification_id,'state',v_next_state);
  end if;

  select count(*) into v_review_total
  from public.lf_test_runs tr
  where tr.suite_run_id=any(q.suite_run_ids)
    and tr.status='REVIEW_REQUIRED';

  if v_review_total=0 then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_NO_REVIEW_REQUIRED_CASES');
  end if;

  select count(distinct tr.test_run_id) into v_review_passed
  from public.lf_test_runs tr
  where tr.suite_run_id=any(q.suite_run_ids)
    and tr.status='REVIEW_REQUIRED'
    and exists (
      select 1
      from public.lf_test_judge_results jr
      where jr.test_run_id=tr.test_run_id
        and jr.created_by_execution_id=p_reviewer_execution_id
        and jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')
        and jr.verdict='PASS'
        and nullif(btrim(coalesce(jr.rationale_summary,'')),'') is not null
        and jsonb_typeof(jr.evidence_payload)='object'
        and jr.evidence_payload<>'{}'::jsonb
        and jr.metadata->>'recorder'='lf_record_test_judge_result_v1'
        and jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id
        and jr.observed_at>=reviewer.started_at
        and jr.observed_at<=reviewer.completed_at
    );

  select count(distinct tr.test_run_id) into v_review_nonpass
  from public.lf_test_runs tr
  where tr.suite_run_id=any(q.suite_run_ids)
    and tr.status='REVIEW_REQUIRED'
    and exists (
      select 1
      from public.lf_test_judge_results jr
      where jr.test_run_id=tr.test_run_id
        and jr.created_by_execution_id=p_reviewer_execution_id
        and jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')
        and jr.verdict<>'PASS'
        and jr.metadata->>'recorder'='lf_record_test_judge_result_v1'
        and jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id
        and jr.observed_at>=reviewer.started_at
        and jr.observed_at<=reviewer.completed_at
    );

  if v_review_nonpass>0 then
    v_next_state := public.lf_lifecycle_resolve_transition_v1(
      'QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'FAIL_QUALIFICATION'
    );
    update public.lf_qualification_receipts
    set lifecycle_state_code=v_next_state,
        independent_review_ref=p_review_ref || jsonb_build_object(
          'finalizer','lf_finalize_qualification_independent_review_v1',
          'reviewed_at',clock_timestamp(),
          'reviewer_operation_code',reviewer.operation_code,
          'review_required_count',v_review_total,
          'strict_pass_count',v_review_passed,
          'nonpass_count',v_review_nonpass
        ),
        findings=findings || jsonb_build_array(jsonb_build_object('type','INDEPENDENT_REVIEW_NONPASS')),
        updated_at=clock_timestamp(),
        updated_by_execution_id=p_reviewer_execution_id
    where qualification_id=p_qualification_id;
    return jsonb_build_object('result','FAILED','code','QUAL_REVIEW_NONPASS','qualification_id',p_qualification_id,'state',v_next_state);
  end if;

  if v_review_passed<>v_review_total then
    return jsonb_build_object(
      'result','BLOCKED','code','QUAL_REVIEW_INCOMPLETE',
      'review_required_count',v_review_total,
      'strict_pass_count',v_review_passed
    );
  end if;

  -- Only after every REVIEW_REQUIRED case has one strict PASS judge from this completed,
  -- independent reviewer do we materialize the test result. This closes the inconsistency
  -- between qualification receipt state and the canonical suite-run state consumed by
  -- lf_qualification_current_v1.
  update public.lf_test_runs tr
  set status='PASS',
      actual_output=coalesce(tr.actual_output,'{}'::jsonb) || jsonb_build_object(
        'passed',true,
        'probe_code',coalesce(tr.input_payload->>'probe_code','INDEPENDENT_REVIEW'),
        'review_required',false,
        'verdict','PASS',
        'materialized_by','lf_finalize_qualification_independent_review_v1',
        'reviewer_execution_id',p_reviewer_execution_id
      ),
      evidence_payload=coalesce(tr.evidence_payload,'{}'::jsonb) || jsonb_build_object(
        'independent_review_materialization',jsonb_build_object(
          'reviewer_execution_id',p_reviewer_execution_id,
          'materialized_at',clock_timestamp(),
          'strict_pass_judge_result_ids',(
            select coalesce(jsonb_agg(jr.judge_result_id::text order by jr.observed_at),'[]'::jsonb)
            from public.lf_test_judge_results jr
            where jr.test_run_id=tr.test_run_id
              and jr.created_by_execution_id=p_reviewer_execution_id
              and jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')
              and jr.verdict='PASS'
              and nullif(btrim(coalesce(jr.rationale_summary,'')),'') is not null
              and jsonb_typeof(jr.evidence_payload)='object'
              and jr.evidence_payload<>'{}'::jsonb
              and jr.metadata->>'recorder'='lf_record_test_judge_result_v1'
              and jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id
              and jr.observed_at>=reviewer.started_at
              and jr.observed_at<=reviewer.completed_at
          )
        )
      ),
      error_code=null,
      error_detail=null,
      completed_at=coalesce(tr.completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=p_reviewer_execution_id
  where tr.suite_run_id=any(q.suite_run_ids)
    and tr.status='REVIEW_REQUIRED'
    and exists (
      select 1
      from public.lf_test_judge_results jr
      where jr.test_run_id=tr.test_run_id
        and jr.created_by_execution_id=p_reviewer_execution_id
        and jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')
        and jr.verdict='PASS'
        and nullif(btrim(coalesce(jr.rationale_summary,'')),'') is not null
        and jsonb_typeof(jr.evidence_payload)='object'
        and jr.evidence_payload<>'{}'::jsonb
        and jr.metadata->>'recorder'='lf_record_test_judge_result_v1'
        and jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id
        and jr.observed_at>=reviewer.started_at
        and jr.observed_at<=reviewer.completed_at
    );

  get diagnostics v_materialized_tests = row_count;

  with agg as (
    select
      sr.suite_run_id,
      count(tr.test_run_id)::int as tests_total,
      count(*) filter (where tr.status='PASS')::int as tests_passed,
      count(*) filter (where tr.status='FAIL')::int as tests_failed,
      count(*) filter (where tr.status='BLOCKED')::int as tests_blocked,
      count(*) filter (where tr.status='REVIEW_REQUIRED')::int as tests_review_required
    from public.lf_test_suite_runs sr
    left join public.lf_test_runs tr on tr.suite_run_id=sr.suite_run_id
    where sr.suite_run_id=any(q.suite_run_ids)
    group by sr.suite_run_id
  )
  update public.lf_test_suite_runs sr
  set tests_total=a.tests_total,
      tests_passed=a.tests_passed,
      tests_failed=a.tests_failed,
      tests_blocked=a.tests_blocked,
      tests_review_required=a.tests_review_required,
      status=case
        when a.tests_failed>0 then 'FAILED'
        when a.tests_blocked>0 then 'BLOCKED'
        when a.tests_review_required>0 then 'REVIEW_REQUIRED'
        when a.tests_total>0 and a.tests_passed=a.tests_total then 'PASSED'
        else 'REVIEW_REQUIRED'
      end,
      completed_at=case
        when a.tests_failed>0 or a.tests_blocked>0
          or (a.tests_total>0 and a.tests_passed=a.tests_total)
          then coalesce(sr.completed_at,clock_timestamp())
        else sr.completed_at
      end,
      updated_at=clock_timestamp(),
      updated_by_execution_id=p_reviewer_execution_id
  from agg a
  where sr.suite_run_id=a.suite_run_id;

  select count(*) into v_nonpassed_suites
  from public.lf_test_suite_runs sr
  where sr.suite_run_id=any(q.suite_run_ids)
    and sr.status is distinct from 'PASSED';

  if v_nonpassed_suites>0 then
    return jsonb_build_object(
      'result','BLOCKED',
      'code','QUAL_REVIEW_REQUIRED_SUITES_NOT_PASSED',
      'review_required_count',v_review_total,
      'strict_pass_count',v_review_passed,
      'materialized_test_count',v_materialized_tests,
      'nonpassed_suite_count',v_nonpassed_suites
    );
  end if;

  v_next_state := public.lf_lifecycle_resolve_transition_v1(
    'QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'PASS_QUALIFICATION'
  );

  update public.lf_qualification_receipts
  set lifecycle_state_code=v_next_state,
      independent_review_ref=p_review_ref || jsonb_build_object(
        'finalizer','lf_finalize_qualification_independent_review_v1',
        'reviewed_at',clock_timestamp(),
        'reviewer_operation_code',reviewer.operation_code,
        'review_required_count',v_review_total,
        'strict_pass_count',v_review_passed,
        'materialized_test_count',v_materialized_tests,
        'all_required_suites_passed',true,
        'revision_sha256',v_current_revision,
        'suite_set_fingerprint',v_current_fingerprint
      ),
      qualified_at=clock_timestamp(),
      updated_at=clock_timestamp(),
      updated_by_execution_id=p_reviewer_execution_id
  where qualification_id=p_qualification_id;

  return jsonb_build_object(
    'result','QUALIFIED_WITH_INDEPENDENT_REVIEW',
    'qualification_id',p_qualification_id,
    'subject_type',q.subject_type,
    'subject_code',q.subject_code,
    'revision_sha256',v_current_revision,
    'suite_set_fingerprint',v_current_fingerprint,
    'reviewer_execution_id',p_reviewer_execution_id,
    'reviewer_operation_code',reviewer.operation_code,
    'review_required_count',v_review_total,
    'strict_pass_count',v_review_passed,
    'materialized_test_count',v_materialized_tests,
    'all_required_suites_passed',true,
    'state',v_next_state
  );
end;
$function$;

revoke all on function public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb) to postgres, service_role;
