-- CANDIDATE SOURCE. PILOT-SRCR-UNIFIED-EXECUTION-V1 / G06 SUBMIT_RESULT.
-- Authorized for isolated PR/local disposable CI only by lf_eventos.id=15197.
-- NO LIVE SUPABASE APPLY / NO MERGE / NO PRODUCTION ACTIVATION.
-- Persists accepted task results without advancing canonical execution state.

create table if not exists public.lf_operation_execution_task (
  execution_id text not null references public.lf_operation_execution(execution_id) on update restrict on delete restrict,
  task_id text not null check (btrim(task_id) <> '' and length(task_id) <= 200),
  step_id text not null check (btrim(step_id) <> '' and length(step_id) <= 200),
  attempt_no integer not null check (attempt_no >= 1),
  created_by_execution_id text not null check (btrim(created_by_execution_id) <> ''),
  created_at timestamptz not null default now(),
  primary key (execution_id, task_id, step_id, attempt_no),
  unique (execution_id, task_id, attempt_no)
);

comment on table public.lf_operation_execution_task is
  'Generic immutable task-identity ledger. It does not select next work. Future advance_execution is the only allowed producer of new canonical task identities; G06 only consumes exact rows to bind result submission.';

create table if not exists public.lf_operation_task_result (
  execution_id text not null,
  task_id text not null,
  step_id text not null,
  attempt_no integer not null check (attempt_no >= 1),
  lease_owner text not null check (btrim(lease_owner) <> '' and length(lease_owner) <= 200),
  lease_fence bigint not null check (lease_fence >= 0),
  outcome text not null check (outcome in ('SUCCEEDED','BLOCKED','FAILED','RETRYABLE_FAILURE')),
  result_digest text not null check (btrim(result_digest) <> '' and length(result_digest) <= 512),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  submitted_by_execution_id text not null check (btrim(submitted_by_execution_id) <> ''),
  submitted_at timestamptz not null default now(),
  primary key (execution_id, task_id, step_id, attempt_no),
  constraint lf_operation_task_result_task_fk
    foreign key (execution_id, task_id, step_id, attempt_no)
    references public.lf_operation_execution_task(execution_id, task_id, step_id, attempt_no)
    on update restrict on delete restrict
);

comment on table public.lf_operation_task_result is
  'Immutable accepted result ledger for LF_UNIFIED_EXECUTION_RESULT_V1. Rows are evidence inputs for advance_execution; this table never owns canonical execution state.';

create or replace function public.lf_operation_execution_task_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  raise exception 'EXECUTION_TASK_IDENTITY_IMMUTABLE';
end;
$function$;

drop trigger if exists trg_lf_operation_execution_task_immutable_v1 on public.lf_operation_execution_task;
create trigger trg_lf_operation_execution_task_immutable_v1
before update or delete on public.lf_operation_execution_task
for each row execute function public.lf_operation_execution_task_immutable_v1();

create or replace function public.lf_operation_task_result_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  raise exception 'OPERATION_TASK_RESULT_IMMUTABLE';
end;
$function$;

drop trigger if exists trg_lf_operation_task_result_immutable_v1 on public.lf_operation_task_result;
create trigger trg_lf_operation_task_result_immutable_v1
before update or delete on public.lf_operation_task_result
for each row execute function public.lf_operation_task_result_immutable_v1();

alter table public.lf_operation_execution_task enable row level security;
alter table public.lf_operation_task_result enable row level security;

revoke all on public.lf_operation_execution_task from public, anon, authenticated, service_role;
revoke all on public.lf_operation_task_result from public, anon, authenticated, service_role;
grant select on public.lf_operation_execution_task to service_role;
grant select on public.lf_operation_task_result to service_role;

create or replace function public.fn_lf_operation_submit_result_v1(
  p_execution_id text,
  p_task_id text,
  p_step_id text,
  p_attempt_no integer,
  p_lease_owner text,
  p_lease_fence bigint,
  p_outcome text,
  p_result_digest text,
  p_evidence_refs jsonb,
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
  v_result public.lf_operation_task_result%rowtype;
  v_inserted boolean := false;
begin
  if btrim(coalesce(p_execution_id,'')) = '' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_task_id,'')) = '' or length(p_task_id) > 200 then raise exception 'INVALID_TASK_ID'; end if;
  if btrim(coalesce(p_step_id,'')) = '' or length(p_step_id) > 200 then raise exception 'INVALID_STEP_ID'; end if;
  if p_attempt_no is null or p_attempt_no < 1 then raise exception 'INVALID_ATTEMPT_NO'; end if;
  if btrim(coalesce(p_lease_owner,'')) = '' or length(p_lease_owner) > 200 then raise exception 'INVALID_LEASE_OWNER'; end if;
  if p_lease_fence is null or p_lease_fence < 0 then raise exception 'INVALID_LEASE_FENCE'; end if;
  if p_outcome is null or p_outcome not in ('SUCCEEDED','BLOCKED','FAILED','RETRYABLE_FAILURE') then
    raise exception 'INVALID_RESULT_OUTCOME';
  end if;
  if btrim(coalesce(p_result_digest,'')) = '' or length(p_result_digest) > 512 then
    raise exception 'INVALID_RESULT_DIGEST';
  end if;
  if p_evidence_refs is null or jsonb_typeof(p_evidence_refs) <> 'array' then
    raise exception 'INVALID_EVIDENCE_REFS';
  end if;
  if btrim(coalesce(p_actor_execution_id,'')) = '' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id = p_execution_id
  for update;

  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.lease_owner is distinct from p_lease_owner
     or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null
     or v_exec.lease_expires_at <= v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  if not exists (
    select 1
    from public.lf_operation_execution_task t
    where t.execution_id = p_execution_id
      and t.task_id = p_task_id
      and t.step_id = p_step_id
      and t.attempt_no = p_attempt_no
  ) then
    raise exception 'RESULT_TASK_IDENTITY_MISMATCH';
  end if;

  insert into public.lf_operation_task_result(
    execution_id, task_id, step_id, attempt_no,
    lease_owner, lease_fence, outcome, result_digest, evidence_refs,
    submitted_by_execution_id
  ) values (
    p_execution_id, p_task_id, p_step_id, p_attempt_no,
    p_lease_owner, p_lease_fence, p_outcome, p_result_digest, p_evidence_refs,
    p_actor_execution_id
  )
  on conflict (execution_id, task_id, step_id, attempt_no) do nothing
  returning * into v_result;

  if v_result.execution_id is not null then
    v_inserted := true;
  else
    select * into v_result
    from public.lf_operation_task_result
    where execution_id = p_execution_id
      and task_id = p_task_id
      and step_id = p_step_id
      and attempt_no = p_attempt_no;
  end if;

  if v_result.execution_id is null then raise exception 'RESULT_SUBMISSION_UNAVAILABLE'; end if;

  if v_result.lease_owner is distinct from p_lease_owner
     or v_result.lease_fence is distinct from p_lease_fence
     or v_result.outcome is distinct from p_outcome
     or v_result.result_digest is distinct from p_result_digest
     or v_result.evidence_refs is distinct from p_evidence_refs then
    raise exception 'RESULT_IDENTITY_REUSED_WITH_DIFFERENT_PAYLOAD';
  end if;

  return jsonb_build_object(
    'result', case when v_inserted then 'RESULT_ACCEPTED' else 'REPLAY_ACCEPTED_RESULT' end,
    'schema', 'LF_UNIFIED_EXECUTION_RESULT_V1',
    'execution_id', v_result.execution_id,
    'task_id', v_result.task_id,
    'step_id', v_result.step_id,
    'attempt_no', v_result.attempt_no,
    'lease_owner', v_result.lease_owner,
    'lease_fence', v_result.lease_fence,
    'outcome', v_result.outcome,
    'result_digest', v_result.result_digest,
    'evidence_refs', v_result.evidence_refs,
    'execution_state_advanced', false
  );
end;
$function$;

revoke all on function public.fn_lf_operation_submit_result_v1(
  text,text,text,integer,text,bigint,text,text,jsonb,text
) from public, anon, authenticated;
grant execute on function public.fn_lf_operation_submit_result_v1(
  text,text,text,integer,text,bigint,text,text,jsonb,text
) to service_role;

comment on function public.fn_lf_operation_submit_result_v1(
  text,text,text,integer,text,bigint,text,text,jsonb,text
) is 'G06 candidate: accepts an exact claimed task result only under the current non-expired lease fence; exact replays are idempotent, mismatched task identity or payload is rejected, and canonical execution state is never advanced.';
