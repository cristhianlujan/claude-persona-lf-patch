-- S36 WP06 — governed recorder + finalizer for qualification receipts with INDEPENDENT_REVIEW cases.
-- Reuses lf_test_judge_results and the canonical QUALIFICATION_LIFECYCLE.
-- Raw REVIEW_REQUIRED test/suite rows are preserved; qualification only advances after strict PASS judges.

create or replace function public.lf_record_test_judge_result_v1(
  p_test_run_id uuid,
  p_reviewer_execution_id text,
  p_judge_code text,
  p_judge_type text,
  p_verdict text,
  p_evidence_payload jsonb,
  p_rationale_summary text,
  p_findings jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  tr public.lf_test_runs%rowtype;
  reviewer public.lf_operation_execution%rowtype;
  existing public.lf_test_judge_results%rowtype;
  v_id uuid;
  v_judge_type text := upper(coalesce(p_judge_type,''));
  v_verdict text := upper(coalesce(p_verdict,''));
begin
  if p_test_run_id is null
     or nullif(btrim(p_reviewer_execution_id),'') is null
     or nullif(btrim(p_judge_code),'') is null then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_IDENTITY_REQUIRED');
  end if;

  if v_judge_type not in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE') then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_TYPE_NOT_ALLOWED','judge_type',v_judge_type);
  end if;

  if v_verdict not in ('PASS','FAIL','BLOCKED','PASS_WITH_RESTRICTIONS') then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_VERDICT_NOT_ALLOWED','verdict',v_verdict);
  end if;

  if p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload) is distinct from 'object'
     or p_evidence_payload='{}'::jsonb then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_EVIDENCE_REQUIRED');
  end if;

  if nullif(btrim(coalesce(p_rationale_summary,'')),'') is null then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_RATIONALE_REQUIRED');
  end if;

  if p_findings is null or jsonb_typeof(p_findings) is distinct from 'array' then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_FINDINGS_MUST_BE_ARRAY');
  end if;

  select * into tr
  from public.lf_test_runs
  where test_run_id=p_test_run_id;

  if not found then
    return jsonb_build_object('result','BLOCKED','code','TEST_RUN_NOT_FOUND');
  end if;

  if tr.status is distinct from 'REVIEW_REQUIRED' then
    return jsonb_build_object('result','BLOCKED','code','TEST_RUN_NOT_REVIEW_REQUIRED','status',tr.status);
  end if;

  select * into reviewer
  from public.lf_operation_execution
  where execution_id=p_reviewer_execution_id;

  if not found then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_REVIEWER_EXECUTION_NOT_FOUND');
  end if;

  if reviewer.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_REVIEWER_NOT_IN_PROGRESS','reviewer_status',reviewer.status);
  end if;

  if tr.execution_id is not null and reviewer.execution_id is not distinct from tr.execution_id then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_REVIEWER_SAME_AS_TEST_PRODUCER');
  end if;

  if tr.operation_code is not null and reviewer.operation_code is not distinct from tr.operation_code then
    return jsonb_build_object('result','BLOCKED','code','JUDGE_REVIEWER_OPERATION_NOT_INDEPENDENT','operation_code',reviewer.operation_code);
  end if;

  select * into existing
  from public.lf_test_judge_results
  where test_run_id=p_test_run_id and judge_code=p_judge_code;

  if found then
    if existing.created_by_execution_id is not distinct from p_reviewer_execution_id
       and existing.judge_type is not distinct from v_judge_type
       and existing.verdict is not distinct from v_verdict
       and existing.evidence_payload is not distinct from p_evidence_payload
       and existing.rationale_summary is not distinct from p_rationale_summary
       and existing.findings is not distinct from p_findings then
      return jsonb_build_object(
        'result','JUDGE_ALREADY_RECORDED_IDENTICAL',
        'judge_result_id',existing.judge_result_id,
        'test_run_id',p_test_run_id,
        'judge_code',p_judge_code,
        'verdict',v_verdict
      );
    end if;
    return jsonb_build_object('result','BLOCKED','code','JUDGE_RESULT_ALREADY_EXISTS_CONFLICT','judge_result_id',existing.judge_result_id);
  end if;

  insert into public.lf_test_judge_results(
    test_run_id,judge_code,judge_type,verdict,severity,findings,evidence_payload,
    rationale_summary,observed_at,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    p_test_run_id,p_judge_code,v_judge_type,v_verdict,
    case when v_verdict='PASS' then 'LOW' else 'HIGH' end,
    p_findings,p_evidence_payload,p_rationale_summary,clock_timestamp(),
    jsonb_build_object(
      'recorder','lf_record_test_judge_result_v1',
      'reviewer_execution_id',p_reviewer_execution_id,
      'reviewer_operation_code',reviewer.operation_code,
      'test_producer_execution_id',tr.execution_id,
      'test_subject_operation_code',tr.operation_code
    ),
    p_reviewer_execution_id,p_reviewer_execution_id
  ) returning judge_result_id into v_id;

  return jsonb_build_object(
    'result','JUDGE_RECORDED',
    'judge_result_id',v_id,
    'test_run_id',p_test_run_id,
    'judge_code',p_judge_code,
    'judge_type',v_judge_type,
    'verdict',v_verdict,
    'reviewer_execution_id',p_reviewer_execution_id,
    'reviewer_operation_code',reviewer.operation_code
  );
end;
$function$;

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
    'state',v_next_state
  );
end;
$function$;

revoke all on function public.lf_record_test_judge_result_v1(uuid,text,text,text,text,jsonb,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_record_test_judge_result_v1(uuid,text,text,text,text,jsonb,text,jsonb) to postgres, service_role;
revoke all on function public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb) to postgres, service_role;
