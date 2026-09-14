create or replace function public.lf_apply_independent_strategy_review_v1(
  p_qualification_id uuid,
  p_suite_run_id uuid,
  p_test_run_id uuid,
  p_snapshot_id bigint,
  p_expected_revision_sha256 text,
  p_review_receipt jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  q public.lf_qualification_receipts%rowtype;
  sr public.lf_test_suite_runs%rowtype;
  tr public.lf_test_runs%rowtype;
  s public.lf_strategy_snapshots%rowtype;
  v_verdict text;
  v_review_context text;
  v_current_revision text;
  v_suite_status text;
  v_total int;
  v_pass int;
  v_fail int;
  v_blocked int;
  v_review int;
  v_all_suites_pass boolean;
  v_any_suite_fail boolean;
  v_target_state text;
begin
  if p_qualification_id is null or p_suite_run_id is null or p_test_run_id is null or p_snapshot_id is null
     or coalesce(p_expected_revision_sha256,'') !~ '^[0-9a-f]{64}$'
     or p_review_receipt is null or jsonb_typeof(p_review_receipt) <> 'object'
     or btrim(coalesce(p_actor_execution_id,'')) = '' then
    raise exception 'LF_INDEPENDENT_REVIEW_INPUT_INVALID';
  end if;

  v_verdict := upper(coalesce(p_review_receipt->>'verdict',''));
  v_review_context := coalesce(p_review_receipt->>'review_context','');
  if v_verdict not in ('PASS','FAIL') then
    raise exception 'LF_INDEPENDENT_REVIEW_VERDICT_INVALID';
  end if;
  if v_review_context <> 'INDEPENDENT_CHAT_CONTEXT' then
    raise exception 'LF_INDEPENDENT_REVIEW_CONTEXT_INVALID';
  end if;
  if jsonb_typeof(coalesce(p_review_receipt->'semantic_findings','[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_review_receipt->'blocking_findings','[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_review_receipt->'evidence_refs','[]'::jsonb)) <> 'array' then
    raise exception 'LF_INDEPENDENT_REVIEW_RECEIPT_SHAPE_INVALID';
  end if;

  select * into s from public.lf_strategy_snapshots where id=p_snapshot_id;
  if not found then raise exception 'LF_INDEPENDENT_REVIEW_SNAPSHOT_MISSING'; end if;
  v_current_revision := public.lf_strategy_revision_sha256_v1(p_snapshot_id);
  if v_current_revision <> p_expected_revision_sha256 then
    raise exception 'LF_INDEPENDENT_REVIEW_STALE_TARGET:%:%',p_expected_revision_sha256,v_current_revision;
  end if;

  select * into q from public.lf_qualification_receipts where qualification_id=p_qualification_id for update;
  if not found or q.subject_type <> 'STRATEGY' or q.subject_code <> s.snapshot_code
     or q.revision_sha256 <> p_expected_revision_sha256
     or q.lifecycle_state_code <> 'QUAL_QUALIFYING'
     or not (p_suite_run_id = any(q.suite_run_ids)) then
    raise exception 'LF_INDEPENDENT_REVIEW_QUALIFICATION_BINDING_INVALID';
  end if;

  select * into sr from public.lf_test_suite_runs where suite_run_id=p_suite_run_id for update;
  if not found or sr.suite_code <> 'TS-STRATEGY-MODEL-HOLDOUT-V1'
     or coalesce(sr.metadata->>'subject_code',sr.manifest->>'subject_code','') <> s.snapshot_code
     or coalesce(sr.metadata->>'revision_sha256',sr.manifest->>'revision_sha256','') <> p_expected_revision_sha256
     or sr.status <> 'REVIEW_REQUIRED' then
    raise exception 'LF_INDEPENDENT_REVIEW_SUITE_BINDING_INVALID';
  end if;

  select * into tr from public.lf_test_runs where test_run_id=p_test_run_id for update;
  if not found or tr.suite_run_id <> p_suite_run_id or tr.test_code <> 'A03'
     or tr.status <> 'REVIEW_REQUIRED'
     or tr.input_payload->>'probe_code' <> 'INDEPENDENT_REVIEW'
     or tr.metadata->>'revision_sha256' <> p_expected_revision_sha256 then
    raise exception 'LF_INDEPENDENT_REVIEW_TEST_BINDING_INVALID';
  end if;

  if p_review_receipt->>'review_case' is distinct from 'S37-MODEL-HOLDOUT-A03'
     or (p_review_receipt->>'snapshot_id')::bigint is distinct from p_snapshot_id
     or p_review_receipt->>'snapshot_code' is distinct from s.snapshot_code
     or p_review_receipt->>'revision_sha256' is distinct from p_expected_revision_sha256
     or (p_review_receipt->>'qualification_id')::uuid is distinct from p_qualification_id
     or (p_review_receipt->>'suite_run_id')::uuid is distinct from p_suite_run_id
     or (p_review_receipt->>'test_run_id')::uuid is distinct from p_test_run_id then
    raise exception 'LF_INDEPENDENT_REVIEW_RECEIPT_IDENTITY_MISMATCH';
  end if;

  if v_verdict='PASS' and jsonb_array_length(coalesce(p_review_receipt->'blocking_findings','[]'::jsonb))>0 then
    raise exception 'LF_INDEPENDENT_REVIEW_PASS_WITH_BLOCKERS';
  end if;

  update public.lf_test_runs
     set status = case when v_verdict='PASS' then 'PASS' else 'FAIL' end,
         actual_output = jsonb_build_object(
           'passed', v_verdict='PASS',
           'probe_code','INDEPENDENT_REVIEW',
           'review_required',false,
           'verdict',v_verdict,
           'review_context',v_review_context
         ),
         evidence_payload = jsonb_build_object(
           'passed', v_verdict='PASS',
           'probe_code','INDEPENDENT_REVIEW',
           'review_required',false,
           'independent_review_receipt',p_review_receipt
         ),
         error_code = case when v_verdict='FAIL' then 'INDEPENDENT_REVIEW_FAILED' else null end,
         error_detail = case when v_verdict='FAIL' then 'Independent semantic review returned FAIL' else null end,
         completed_at = clock_timestamp(),
         updated_by_execution_id = p_actor_execution_id
   where test_run_id=p_test_run_id;

  select count(*),
         count(*) filter(where status='PASS'),
         count(*) filter(where status='FAIL'),
         count(*) filter(where status='BLOCKED'),
         count(*) filter(where status='REVIEW_REQUIRED')
    into v_total,v_pass,v_fail,v_blocked,v_review
    from public.lf_test_runs where suite_run_id=p_suite_run_id;

  v_suite_status := case
    when v_fail>0 then 'FAILED'
    when v_blocked>0 then 'BLOCKED'
    when v_review>0 then 'REVIEW_REQUIRED'
    when v_pass=v_total and v_total>0 then 'PASSED'
    else 'REVIEW_REQUIRED' end;

  update public.lf_test_suite_runs
     set status=v_suite_status,
         tests_total=v_total,
         tests_passed=v_pass,
         tests_failed=v_fail,
         tests_blocked=v_blocked,
         tests_review_required=v_review,
         completed_at=case when v_suite_status in ('PASSED','FAILED','BLOCKED') then clock_timestamp() else completed_at end,
         updated_by_execution_id=p_actor_execution_id
   where suite_run_id=p_suite_run_id;

  select bool_and(status='PASSED'), bool_or(status='FAILED')
    into v_all_suites_pass,v_any_suite_fail
    from public.lf_test_suite_runs
   where suite_run_id = any(q.suite_run_ids);

  if coalesce(v_any_suite_fail,false) then
    v_target_state:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'FAIL_QUALIFICATION');
    update public.lf_qualification_receipts
       set lifecycle_state_code=v_target_state,
           findings=coalesce(findings,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','INDEPENDENT_REVIEW_FAILED','test_run_id',p_test_run_id)),
           updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id
     where qualification_id=p_qualification_id;
  elsif coalesce(v_all_suites_pass,false) then
    v_target_state:=public.lf_lifecycle_resolve_transition_v1('QUALIFICATION_LIFECYCLE',q.lifecycle_state_code,'PASS_QUALIFICATION');
    update public.lf_qualification_receipts
       set lifecycle_state_code=v_target_state,
           qualified_at=clock_timestamp(),
           findings=coalesce(findings,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','INDEPENDENT_REVIEW_PASS','test_run_id',p_test_run_id,'review_case',p_review_receipt->>'review_case')),
           updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id
     where qualification_id=p_qualification_id;
  end if;

  return jsonb_build_object(
    'result','INDEPENDENT_REVIEW_APPLIED',
    'verdict',v_verdict,
    'test_run_id',p_test_run_id,
    'test_status',case when v_verdict='PASS' then 'PASS' else 'FAIL' end,
    'suite_run_id',p_suite_run_id,
    'suite_status',v_suite_status,
    'qualification_id',p_qualification_id,
    'qualification_state',(select lifecycle_state_code from public.lf_qualification_receipts where qualification_id=p_qualification_id),
    'revision_sha256',p_expected_revision_sha256
  );
end;
$$;