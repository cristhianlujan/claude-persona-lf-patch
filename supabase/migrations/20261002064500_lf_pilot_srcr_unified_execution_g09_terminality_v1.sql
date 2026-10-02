-- CANDIDATE SOURCE. PILOT-SRCR-UNIFIED-EXECUTION-V1 / G09 TERMINALITY.
-- Authorized for isolated candidate/CI only by lf_eventos.id=15197.
-- NO LIVE SUPABASE APPLY / NO MERGE / NO PRODUCTION ACTIVATION.
-- G09 owns normal COMPLETED terminalization for unified executions.
-- It consumes G07 NO_NEXT_TASK, the canonical execution judge and the current lease fence.

create or replace view public.v_lf_operation_execution_checklist as
with resolved as (
  select
    e.execution_id,
    e.operation_code,
    e.target_type,
    e.target_code,
    e.target_repo,
    e.target_path,
    s.step_order,
    s.step_id,
    s.required,
    s.evidence_required,
    b.status as binding_status,
    b.clean_result_value,
    b.blocked_result_value,
    case
      when es.execution_id is not null then coalesce(es.status,'MISSING')
      when ur.execution_id is null then 'MISSING'
      when ur.outcome='SUCCEEDED' then coalesce(b.clean_result_value,'PASS')
      when ur.outcome='BLOCKED' then coalesce(b.blocked_result_value,'BLOCKED')
      when ur.outcome in ('FAILED','RETRYABLE_FAILURE') then 'FAIL'
      else 'MISSING'
    end as execution_step_status,
    case
      when es.execution_id is not null then es.evidence_ref
      when ur.execution_id is not null and jsonb_array_length(ur.evidence_refs)>0
        then ur.evidence_refs->>0
      else null
    end as evidence_ref,
    case
      when es.execution_id is not null then es.evidence_payload
      when ur.execution_id is not null then jsonb_build_object(
        'source','lf_operation_task_result',
        'task_id',ur.task_id,
        'step_id',ur.step_id,
        'attempt_no',ur.attempt_no,
        'outcome',ur.outcome,
        'result_digest',ur.result_digest,
        'evidence_refs',ur.evidence_refs,
        'lease_fence',ur.lease_fence,
        'submitted_at',ur.submitted_at
      )
      else null
    end as evidence_payload
  from public.lf_operation_execution e
  join public.lf_operation_steps s
    on s.operation_code=e.operation_code
   and s.active is true
  left join public.lf_operation_execution_steps es
    on es.execution_id=e.execution_id
   and es.step_order=s.step_order
   and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings b
    on b.operation_code=e.operation_code
   and b.step_order=s.step_order
   and b.step_id=s.step_id
   and b.status='ACTIVE_ENFORCEMENT'
  left join lateral (
    select r.*
    from public.lf_operation_task_result r
    where r.execution_id=e.execution_id
      and r.step_id=s.step_id
    order by r.attempt_no desc, r.submitted_at desc, r.task_id
    limit 1
  ) ur on es.execution_id is null
)
select
  execution_id,
  operation_code,
  target_type,
  target_code,
  target_repo,
  target_path,
  step_order,
  step_id,
  required,
  evidence_required,
  execution_step_status,
  evidence_ref,
  evidence_payload,
  case
    when required is true and execution_step_status='MISSING'
      then 'FAIL_MISSING_REQUIRED_STEP'
    when required is true and not (
      execution_step_status in ('PASS','NO_APLICA_CON_MOTIVO')
      or (binding_status='ACTIVE_ENFORCEMENT' and execution_step_status=clean_result_value)
    ) then 'FAIL_STEP_NOT_PASS'
    when required is false and execution_step_status='MISSING'
      then 'OPTIONAL_NOT_RECORDED'
    else 'OK'
  end as checklist_result
from resolved;

comment on view public.v_lf_operation_execution_checklist is
  'Canonical operation checklist. Legacy execution-step evidence remains authoritative when present; unified immutable task results are a fallback read-model source only. No second judge authority is introduced.';

create table if not exists public.lf_operation_terminal_receipt (
  execution_id text primary key references public.lf_operation_execution(execution_id)
    on update restrict on delete restrict,
  advance_seq bigint not null check (advance_seq >= 1),
  source_task_id text not null check (btrim(source_task_id)<>''),
  source_step_id text not null check (btrim(source_step_id)<>''),
  source_attempt_no integer not null check (source_attempt_no >= 1),
  source_result_digest text not null check (btrim(source_result_digest)<>''),
  source_lease_fence bigint not null check (source_lease_fence >= 0),
  operation_spec_digest text not null check (operation_spec_digest ~ '^[0-9a-f]{64}$'),
  required_steps bigint not null check (required_steps >= 0),
  required_steps_pass bigint not null check (required_steps_pass >= 0),
  fail_count bigint not null check (fail_count = 0),
  blocked_count bigint not null check (blocked_count = 0),
  judge_result text not null check (judge_result='PASS'),
  finalized_by_execution_id text not null check (btrim(finalized_by_execution_id)<>''),
  terminal_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint lf_operation_terminal_receipt_required_steps_ck
    check (required_steps_pass=required_steps)
);

create or replace function public.lf_operation_terminal_receipt_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  raise exception 'OPERATION_TERMINAL_RECEIPT_IMMUTABLE';
end;
$function$;

drop trigger if exists trg_lf_operation_terminal_receipt_immutable_v1
  on public.lf_operation_terminal_receipt;
create trigger trg_lf_operation_terminal_receipt_immutable_v1
before update or delete on public.lf_operation_terminal_receipt
for each row execute function public.lf_operation_terminal_receipt_immutable_v1();

alter table public.lf_operation_terminal_receipt enable row level security;
revoke all on public.lf_operation_terminal_receipt from public, anon, authenticated, service_role;
grant select on public.lf_operation_terminal_receipt to service_role;

create or replace function public.lf_operation_execution_terminal_state_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if old.status='IN_PROGRESS'
     and new.status='COMPLETED'
     and coalesce(new.advance_seq,0)>0
     and not exists (
       select 1
       from public.lf_operation_terminal_receipt tr
       where tr.execution_id=new.execution_id
         and tr.advance_seq=new.advance_seq
     ) then
    raise exception 'UNIFIED_EXECUTION_TERMINAL_RECEIPT_REQUIRED';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_lf_operation_execution_terminal_state_guard_v1
  on public.lf_operation_execution;
create trigger trg_lf_operation_execution_terminal_state_guard_v1
before update of status on public.lf_operation_execution
for each row execute function public.lf_operation_execution_terminal_state_guard_v1();

create or replace function public.fn_lf_operation_finalize_execution_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_exec_json jsonb;
  v_frozen_spec_digest text;
  v_current_spec_digest text;
  v_advance public.lf_operation_advance_receipt%rowtype;
  v_existing public.lf_operation_terminal_receipt%rowtype;
  v_judge record;
  v_unresolved_tasks bigint;
  v_receipt public.lf_operation_terminal_receipt%rowtype;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_lease_owner,''))='' then raise exception 'INVALID_LEASE_OWNER'; end if;
  if p_lease_fence is null or p_lease_fence<0 then raise exception 'INVALID_LEASE_FENCE'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;

  select * into v_existing
  from public.lf_operation_terminal_receipt
  where execution_id=p_execution_id;

  if v_exec.status='COMPLETED' then
    if v_existing.execution_id is null then
      raise exception 'TERMINAL_STATE_WITHOUT_G09_RECEIPT';
    end if;
    if v_existing.advance_seq is distinct from v_exec.advance_seq
       or v_exec.completed_at is distinct from v_existing.terminal_at then
      raise exception 'TERMINAL_REPLAY_STATE_RECEIPT_MISMATCH';
    end if;
    return to_jsonb(v_existing)||jsonb_build_object('result','REPLAY_ACCEPTED_TERMINALITY');
  end if;

  if v_exec.status is distinct from 'IN_PROGRESS' then
    raise exception 'EXECUTION_NOT_TERMINALIZABLE';
  end if;

  if v_exec.lease_owner is distinct from p_lease_owner
     or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null
     or v_exec.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  if v_exec.current_task_id is not null
     or v_exec.current_step_id is not null
     or v_exec.current_attempt_no is not null then
    raise exception 'EXECUTABLE_CURRENT_TASK_REMAINS';
  end if;
  if coalesce(v_exec.advance_seq,0)<1 then raise exception 'ADVANCE_RECEIPT_REQUIRED'; end if;

  select * into v_advance
  from public.lf_operation_advance_receipt
  where execution_id=p_execution_id
    and advance_seq=v_exec.advance_seq;
  if v_advance.execution_id is null then raise exception 'ADVANCE_RECEIPT_REQUIRED'; end if;
  if v_advance.disposition is distinct from 'NO_NEXT_TASK' then
    raise exception 'TERMINALITY_REQUIRES_NO_NEXT_TASK';
  end if;
  if v_advance.transition_kind is distinct from 'RESULT'
     or v_advance.source_outcome is distinct from 'SUCCEEDED' then
    raise exception 'TERMINALITY_REQUIRES_SUCCESSFUL_FINAL_RESULT';
  end if;
  if v_advance.source_lease_fence is distinct from p_lease_fence then
    raise exception 'TERMINALITY_SOURCE_FENCE_MISMATCH';
  end if;

  v_exec_json:=to_jsonb(v_exec);
  v_frozen_spec_digest:=v_exec_json->>'operation_spec_digest';
  if coalesce(v_frozen_spec_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'EXECUTION_OPERATION_SPEC_IDENTITY_MISSING';
  end if;
  v_current_spec_digest:=public.fn_lf_operation_spec_digest_v1(v_exec.operation_code);
  if v_current_spec_digest is distinct from v_frozen_spec_digest
     or v_advance.operation_spec_digest is distinct from v_frozen_spec_digest then
    raise exception 'FROZEN_OPERATION_SPEC_DIGEST_MISMATCH';
  end if;

  select count(*) into v_unresolved_tasks
  from public.lf_operation_execution_task t
  left join public.lf_operation_task_result r
    on r.execution_id=t.execution_id
   and r.task_id=t.task_id
   and r.step_id=t.step_id
   and r.attempt_no=t.attempt_no
  where t.execution_id=p_execution_id
    and r.execution_id is null;
  if v_unresolved_tasks<>0 then
    raise exception 'EXECUTABLE_PENDING_TASK_REMAINS:%',v_unresolved_tasks;
  end if;

  select * into v_judge
  from public.v_lf_operation_execution_judge
  where execution_id=p_execution_id;
  if not found then raise exception 'CANONICAL_OPERATION_JUDGE_MISSING'; end if;
  if v_judge.required_steps_pass is distinct from v_judge.required_steps
     or v_judge.fail_count<>0
     or v_judge.blocked_count<>0
     or v_judge.judge_result is distinct from 'PASS' then
    raise exception 'CANONICAL_OPERATION_JUDGE_NOT_CLEAN';
  end if;

  insert into public.lf_operation_terminal_receipt(
    execution_id,advance_seq,
    source_task_id,source_step_id,source_attempt_no,source_result_digest,source_lease_fence,
    operation_spec_digest,
    required_steps,required_steps_pass,fail_count,blocked_count,judge_result,
    finalized_by_execution_id,terminal_at
  ) values (
    p_execution_id,v_exec.advance_seq,
    v_advance.source_task_id,v_advance.source_step_id,v_advance.source_attempt_no,
    v_advance.source_result_digest,v_advance.source_lease_fence,
    v_frozen_spec_digest,
    v_judge.required_steps,v_judge.required_steps_pass,v_judge.fail_count,v_judge.blocked_count,
    v_judge.judge_result,
    p_actor_execution_id,v_now
  ) returning * into v_receipt;

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=v_now,
      updated_by_execution_id=p_actor_execution_id,
      updated_at=v_now
  where execution_id=p_execution_id
    and status='IN_PROGRESS';
  if not found then raise exception 'TERMINAL_STATE_UPDATE_LOST'; end if;

  return to_jsonb(v_receipt)||jsonb_build_object(
    'result','TERMINALITY_ACCEPTED',
    'execution_status','COMPLETED',
    'pending_task_count',v_unresolved_tasks
  );
end;
$function$;

revoke all on function public.fn_lf_operation_finalize_execution_v1(text,text,bigint,text)
  from public, anon, authenticated;
grant execute on function public.fn_lf_operation_finalize_execution_v1(text,text,bigint,text)
  to service_role;

comment on function public.fn_lf_operation_finalize_execution_v1(text,text,bigint,text) is
  'G09 generic terminality owner for unified executions. It can derive only COMPLETED, only from a current fenced SUCCEEDED result whose G07 disposition is NO_NEXT_TASK, with zero unresolved tasks and the canonical operation judge clean. It does not route, retry, checkpoint, dispatch runtime work or introduce profile-specific logic.';
