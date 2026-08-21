create or replace view programacion.v_agent_task_progress_v1
with (security_invoker = true)
as
with evidence as (
  select
    b.*,
    tc.id as test_contract_id,
    tc.status as test_contract_status,
    tc.contract_sha256 as test_contract_sha256,
    cp.id as context_pack_id,
    cp.estado as context_pack_state,
    cp.digest_version as context_pack_digest_version,
    cp.context_sha256 as context_pack_sha256,
    coalesce(cp.estado='COMPLETE' and cp.digest_version=2,false) as context_complete,
    case
      when b.execution_id is null then false
      else programacion.fn_agent_task_worker_context_receipt_ok(b.execution_id)
    end as worker_receipt_verified,
    coalesce(cl.required_total,0::bigint) as required_test_total,
    coalesce(cl.required_pass,0::bigint) as required_test_pass,
    coalesce(cl.required_fail,0::bigint) as required_test_fail,
    coalesce(cl.required_blocked,0::bigint) as required_test_blocked,
    coalesce(cl.required_pending,0::bigint) as required_test_pending,
    cl.derived_status as closure_derived_status
  from programacion.v_agent_task_backlog_v1 b
  left join programacion.test_contracts tc on tc.task_id=b.task_id
  left join programacion.context_packs cp on cp.execution_id=b.execution_id
  left join programacion.v_ejecucion_cierre cl on cl.execution_id=b.execution_id
), normalized as (
  select
    e.*,
    (e.task_definition_status='SEALED') as task_sealed,
    coalesce(e.test_contract_status='SEALED',false) as test_contract_sealed,
    (
      e.task_definition_status='SEALED'
      and coalesce(e.test_contract_status='SEALED',false)
      and e.ready_for_development
      and e.executable_now
      and e.execution_id is not null
      and e.execution_state='COMPLETED'
      and e.context_complete
      and e.worker_receipt_verified
      and e.required_test_total>0
      and e.required_test_total=e.required_test_pass
      and e.required_test_fail=0
      and e.required_test_blocked=0
      and e.required_test_pending=0
      and e.closure_derived_status='ELIGIBLE_PASS'
      and e.execution_effective_verdict='PASS'
      and e.state_conflict_code is null
    ) as evidence_chain_complete
  from evidence e
), staged as (
  select
    n.*,
    case
      when n.state_conflict_code is not null then n.state_conflict_code
      when n.execution_effective_verdict='PASS' and not n.evidence_chain_complete
        then 'PASS_WITH_INCOMPLETE_EVIDENCE_CHAIN'::text
      else null::text
    end as progress_conflict_code,
    case
      when n.backlog_state='NEEDS_REWORK'
        or n.required_test_fail>0
        or n.required_test_blocked>0
        or n.execution_effective_verdict in ('FAIL','INVALIDATED')
        then 'NEEDS_REWORK'::text
      when n.backlog_state='BLOCKED' then 'BLOCKED'::text
      when n.backlog_state='WAITING_DEPENDENCY' then 'WAITING_DEPENDENCY'::text
      when n.execution_effective_verdict='PASS' and not n.evidence_chain_complete
        then 'EVIDENCE_CONFLICT'::text
      when n.evidence_chain_complete then 'DONE_VERIFIED'::text
      when n.execution_id is null then 'READY'::text
      when not n.context_complete then 'CONTEXT_PENDING'::text
      when not n.worker_receipt_verified then 'WORKER_RECEIPT_PENDING'::text
      when n.required_test_total=0 then 'TEST_EVIDENCE_PENDING'::text
      when n.required_test_pending>0 then 'TESTING'::text
      when n.required_test_total=n.required_test_pass and n.execution_effective_verdict is null
        then 'VERDICT_PENDING'::text
      else 'VERDICT_PENDING'::text
    end as progress_stage
  from normalized n
)
select
  s.task_id,
  s.task_code,
  s.task_version,
  s.functional_version_id,
  s.artifact_code,
  s.story_code,
  s.functional_objective,
  s.task_objective,
  s.task_definition_status,
  s.task_sealed,
  s.test_contract_id,
  s.test_contract_status,
  s.test_contract_sha256,
  s.test_contract_sealed,
  s.ready_for_development,
  s.executable_now,
  s.sizing,
  s.blockers,
  s.waiting_on_task_ids,
  s.execution_id,
  s.execution_state,
  s.execution_head_sha,
  s.execution_created_at,
  s.execution_started_at,
  s.execution_completed_at,
  s.context_pack_id,
  s.context_pack_state,
  s.context_pack_digest_version,
  s.context_pack_sha256,
  s.context_complete,
  s.worker_receipt_verified,
  s.required_test_total,
  s.required_test_pass,
  s.required_test_fail,
  s.required_test_blocked,
  s.required_test_pending,
  s.closure_derived_status,
  s.execution_effective_verdict,
  s.evidence_chain_complete,
  s.backlog_state,
  s.state_conflict_code,
  s.progress_conflict_code,
  s.progress_stage,
  case s.progress_stage
    when 'BLOCKED' then 'RESOLVE_CURRENT_BLOCKERS'
    when 'WAITING_DEPENDENCY' then 'SATISFY_DEPENDENCIES'
    when 'READY' then 'CREATE_AGENT_TASK_EXECUTION'
    when 'CONTEXT_PENDING' then 'COMPLETE_CONTEXT_PACK'
    when 'WORKER_RECEIPT_PENDING' then 'VERIFY_WORKER_CONTEXT_RECEIPT'
    when 'TEST_EVIDENCE_PENDING' then 'CREATE_REQUIRED_TEST_EVIDENCE'
    when 'TESTING' then 'COMPLETE_REQUIRED_TESTS'
    when 'VERDICT_PENDING' then 'FINALIZE_EFFECTIVE_VERDICT'
    when 'NEEDS_REWORK' then 'REMEDIATE_FAILED_OR_BLOCKED_EVIDENCE'
    when 'EVIDENCE_CONFLICT' then 'RECONCILE_CONFLICTING_EVIDENCE'
    when 'DONE_VERIFIED' then null
    else 'REVIEW_PROGRESS_EVIDENCE'
  end as next_required_evidence,
  'DERIVED_FROM_VERIFIED_EVIDENCE_CHAIN'::text as progress_authority_model
from staged s;

create or replace view programacion.v_story_progress_v1
with (security_invoker = true)
as
select
  p.functional_version_id,
  p.artifact_code,
  p.story_code,
  p.functional_objective,
  count(*) as mandatory_task_count,
  count(*) filter (where p.task_sealed) as task_sealed_count,
  count(*) filter (where p.test_contract_sealed) as test_contract_sealed_count,
  count(*) filter (where p.ready_for_development) as ready_for_development_count,
  count(*) filter (where p.executable_now) as executable_now_count,
  count(*) filter (where p.execution_id is not null) as execution_count,
  count(*) filter (where p.context_complete) as context_complete_count,
  count(*) filter (where p.worker_receipt_verified) as worker_receipt_verified_count,
  sum(p.required_test_total) as required_test_total,
  sum(p.required_test_pass) as required_test_pass,
  sum(p.required_test_fail) as required_test_fail,
  sum(p.required_test_blocked) as required_test_blocked,
  sum(p.required_test_pending) as required_test_pending,
  count(*) filter (where p.evidence_chain_complete) as done_verified_task_count,
  count(*) filter (where p.progress_stage='BLOCKED') as blocked_task_count,
  count(*) filter (where p.progress_stage='WAITING_DEPENDENCY') as waiting_dependency_task_count,
  count(*) filter (where p.progress_stage='READY') as ready_task_count,
  count(*) filter (where p.progress_stage in ('CONTEXT_PENDING','WORKER_RECEIPT_PENDING','TEST_EVIDENCE_PENDING','TESTING','VERDICT_PENDING')) as active_task_count,
  count(*) filter (where p.progress_stage='NEEDS_REWORK') as needs_rework_task_count,
  count(*) filter (where p.progress_stage='EVIDENCE_CONFLICT' or p.progress_conflict_code is not null) as evidence_conflict_task_count,
  coalesce(array_agg(distinct p.next_required_evidence) filter (where p.next_required_evidence is not null),'{}'::text[]) as next_required_evidence,
  case
    when count(*) filter (where p.progress_stage='EVIDENCE_CONFLICT' or p.progress_conflict_code is not null)>0
      then 'EVIDENCE_CONFLICT'::text
    when count(*) filter (where p.progress_stage='NEEDS_REWORK')>0
      then 'NEEDS_REWORK'::text
    when count(*) filter (where p.progress_stage='DONE_VERIFIED')=count(*)
      then 'DONE_VERIFIED'::text
    when count(*) filter (where p.progress_stage='BLOCKED')>0
      then 'BLOCKED'::text
    when count(*) filter (where p.progress_stage='WAITING_DEPENDENCY')>0
      then 'WAITING_DEPENDENCY'::text
    when count(*) filter (where p.progress_stage in ('CONTEXT_PENDING','WORKER_RECEIPT_PENDING','TEST_EVIDENCE_PENDING','TESTING','VERDICT_PENDING'))>0
      then 'IN_PROGRESS'::text
    when count(*) filter (where p.progress_stage='DONE_VERIFIED')>0
      then 'IN_PROGRESS'::text
    when count(*) filter (where p.progress_stage='READY')=count(*)
      then 'READY'::text
    else 'IN_PROGRESS'::text
  end as story_progress_state,
  'DERIVED_FROM_AGENT_TASK_EVIDENCE'::text as progress_authority_model
from programacion.v_agent_task_progress_v1 p
group by p.functional_version_id,p.artifact_code,p.story_code,p.functional_objective;

revoke all on programacion.v_agent_task_progress_v1 from public;
revoke all on programacion.v_story_progress_v1 from public;
grant select on programacion.v_agent_task_progress_v1 to programacion_builder;
grant select on programacion.v_agent_task_progress_v1 to programacion_auditor;
grant select on programacion.v_agent_task_progress_v1 to programacion_human_authority;
grant select on programacion.v_story_progress_v1 to programacion_builder;
grant select on programacion.v_story_progress_v1 to programacion_auditor;
grant select on programacion.v_story_progress_v1 to programacion_human_authority;