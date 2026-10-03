-- CANDIDATE SOURCE. PILOT-SRCR-UNIFIED-EXECUTION-V1 / G10 RETRY_ATTEMPT_POLICY.
-- Authorized for isolated candidate/CI only by lf_eventos.id=15197.
-- NO LIVE SUPABASE APPLY / NO MERGE / NO PRODUCTION ACTIVATION.
-- G10 decides retry eligibility from canonical policy snapshot.
-- G05 remains lease/fence owner. G07 remains sole next-task/attempt materialization owner.

alter table public.lf_operation_advance_receipt
  add column if not exists materialized_lease_fence bigint;

comment on column public.lf_operation_advance_receipt.materialized_lease_fence is
  'Fence current on lf_operation_execution when G07 materialized the disposition. For retry materialization it must be strictly newer than the source result fence.';

create table if not exists public.lf_operation_retry_receipt (
  execution_id text not null references public.lf_operation_execution(execution_id)
    on update restrict on delete restrict,
  task_id text not null check (btrim(task_id)<>''),
  step_id text not null check (btrim(step_id)<>''),
  source_attempt_no integer not null check (source_attempt_no>=1),
  source_result_digest text not null check (btrim(source_result_digest)<>''),
  source_lease_owner text not null check (btrim(source_lease_owner)<>''),
  source_lease_fence bigint not null check (source_lease_fence>=0),
  source_outcome text not null check (source_outcome='RETRYABLE_FAILURE'),
  next_attempt_no integer not null check (next_attempt_no>=2),
  backoff_seconds integer not null check (backoff_seconds>=0 and backoff_seconds<=86400),
  retry_not_before timestamptz not null,
  policy_code text not null check (btrim(policy_code)<>''),
  policy_version text not null check (btrim(policy_version)<>''),
  policy_sha text not null check (policy_sha ~ '^[0-9a-f]{64}$'),
  authorized_by_execution_id text not null check (btrim(authorized_by_execution_id)<>''),
  authorized_at timestamptz not null default now(),
  primary key (execution_id,task_id,step_id,source_attempt_no),
  constraint lf_operation_retry_receipt_attempt_step_ck
    check (next_attempt_no=source_attempt_no+1)
);

create or replace function public.lf_operation_retry_receipt_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog,public
as $function$
begin
  raise exception 'OPERATION_RETRY_RECEIPT_IMMUTABLE';
end;
$function$;

drop trigger if exists trg_lf_operation_retry_receipt_immutable_v1
  on public.lf_operation_retry_receipt;
create trigger trg_lf_operation_retry_receipt_immutable_v1
before update or delete on public.lf_operation_retry_receipt
for each row execute function public.lf_operation_retry_receipt_immutable_v1();

alter table public.lf_operation_retry_receipt enable row level security;
revoke all on public.lf_operation_retry_receipt from public,anon,authenticated,service_role;
grant select on public.lf_operation_retry_receipt to service_role;

create or replace function public.fn_lf_operation_authorize_retry_v1(
  p_execution_id text,
  p_task_id text,
  p_step_id text,
  p_source_attempt_no integer,
  p_lease_owner text,
  p_lease_fence bigint,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_now timestamptz:=clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_result public.lf_operation_task_result%rowtype;
  v_existing public.lf_operation_retry_receipt%rowtype;
  v_policy record;
  v_policy_count integer;
  v_max_attempts integer;
  v_backoff jsonb;
  v_backoff_seconds integer;
  v_next_attempt integer;
  v_receipt public.lf_operation_retry_receipt%rowtype;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_task_id,''))='' then raise exception 'INVALID_TASK_ID'; end if;
  if btrim(coalesce(p_step_id,''))='' then raise exception 'INVALID_STEP_ID'; end if;
  if p_source_attempt_no is null or p_source_attempt_no<1 then raise exception 'INVALID_SOURCE_ATTEMPT_NO'; end if;
  if btrim(coalesce(p_lease_owner,''))='' then raise exception 'INVALID_LEASE_OWNER'; end if;
  if p_lease_fence is null or p_lease_fence<0 then raise exception 'INVALID_LEASE_FENCE'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.status is distinct from 'IN_PROGRESS' then raise exception 'EXECUTION_NOT_RETRYABLE'; end if;
  if row(v_exec.current_task_id,v_exec.current_step_id,v_exec.current_attempt_no)
     is distinct from row(p_task_id,p_step_id,p_source_attempt_no) then
    raise exception 'RETRY_SOURCE_IS_NOT_CURRENT_TASK';
  end if;
  if v_exec.lease_owner is distinct from p_lease_owner
     or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null
     or v_exec.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  select * into v_result
  from public.lf_operation_task_result
  where execution_id=p_execution_id
    and task_id=p_task_id
    and step_id=p_step_id
    and attempt_no=p_source_attempt_no;
  if v_result.execution_id is null then raise exception 'ACCEPTED_RESULT_NOT_FOUND'; end if;
  if v_result.lease_owner is distinct from p_lease_owner
     or v_result.lease_fence is distinct from p_lease_fence then
    raise exception 'RETRY_RESULT_FENCE_MISMATCH';
  end if;
  if v_result.outcome is distinct from 'RETRYABLE_FAILURE' then
    raise exception 'RESULT_OUTCOME_NOT_RETRYABLE';
  end if;

  select * into v_existing
  from public.lf_operation_retry_receipt
  where execution_id=p_execution_id
    and task_id=p_task_id
    and step_id=p_step_id
    and source_attempt_no=p_source_attempt_no;
  if v_existing.execution_id is not null then
    if v_existing.source_result_digest is distinct from v_result.result_digest
       or v_existing.source_lease_fence is distinct from v_result.lease_fence then
      raise exception 'RETRY_RECEIPT_SOURCE_IDENTITY_MISMATCH';
    end if;
    return to_jsonb(v_existing)||jsonb_build_object('result','REPLAY_ACCEPTED_RETRY_AUTHORIZATION');
  end if;

  select count(*) into v_policy_count
  from public.v_lf_operation_policy_snapshot
  where operation_code=v_exec.operation_code
    and policy_role='RETRY_POLICY'
    and required is true;
  if v_policy_count<>1 then
    raise exception 'RETRY_POLICY_RESOLUTION_NOT_EXACT:%',v_policy_count;
  end if;

  select policy_code,policy_version,policy_sha,policy_payload
  into v_policy
  from public.v_lf_operation_policy_snapshot
  where operation_code=v_exec.operation_code
    and policy_role='RETRY_POLICY'
    and required is true;

  if coalesce(v_policy.policy_code,'')=''
     or coalesce(v_policy.policy_version,'')=''
     or coalesce(v_policy.policy_sha,'') !~ '^[0-9a-f]{64}$'
     or v_policy.policy_payload is null then
    raise exception 'RETRY_POLICY_IDENTITY_INVALID';
  end if;
  if v_policy.policy_payload->>'schema' is distinct from 'LF_UNIFIED_EXECUTION_RETRY_POLICY_V1' then
    raise exception 'RETRY_POLICY_SCHEMA_INVALID';
  end if;
  if jsonb_typeof(v_policy.policy_payload->'retryable_outcomes')<>'array'
     or not (v_policy.policy_payload->'retryable_outcomes' ? v_result.outcome) then
    raise exception 'RETRY_POLICY_OUTCOME_NOT_ALLOWED';
  end if;
  if coalesce((v_policy.policy_payload->>'new_attempt_identity_required')::boolean,false) is distinct from true
     or coalesce((v_policy.policy_payload->>'new_fence_required')::boolean,false) is distinct from true then
    raise exception 'RETRY_POLICY_IDENTITY_GUARDS_REQUIRED';
  end if;
  if coalesce(v_policy.policy_payload->>'max_attempts','') !~ '^[0-9]+$' then
    raise exception 'RETRY_POLICY_MAX_ATTEMPTS_INVALID';
  end if;
  v_max_attempts:=(v_policy.policy_payload->>'max_attempts')::integer;
  if v_max_attempts<1 or v_max_attempts>20 then raise exception 'RETRY_POLICY_MAX_ATTEMPTS_INVALID'; end if;
  if p_source_attempt_no>=v_max_attempts then raise exception 'RETRY_ATTEMPTS_EXHAUSTED'; end if;

  v_backoff:=v_policy.policy_payload->'backoff_seconds_by_retry';
  if jsonb_typeof(v_backoff)<>'array'
     or jsonb_array_length(v_backoff)<v_max_attempts-1 then
    raise exception 'RETRY_POLICY_BACKOFF_INVALID';
  end if;
  if coalesce(v_backoff->>(p_source_attempt_no-1),'') !~ '^[0-9]+$' then
    raise exception 'RETRY_POLICY_BACKOFF_INVALID';
  end if;
  v_backoff_seconds:=(v_backoff->>(p_source_attempt_no-1))::integer;
  if v_backoff_seconds<0 or v_backoff_seconds>86400 then
    raise exception 'RETRY_POLICY_BACKOFF_INVALID';
  end if;

  v_next_attempt:=p_source_attempt_no+1;
  insert into public.lf_operation_retry_receipt(
    execution_id,task_id,step_id,source_attempt_no,
    source_result_digest,source_lease_owner,source_lease_fence,source_outcome,
    next_attempt_no,backoff_seconds,retry_not_before,
    policy_code,policy_version,policy_sha,
    authorized_by_execution_id,authorized_at
  ) values (
    p_execution_id,p_task_id,p_step_id,p_source_attempt_no,
    v_result.result_digest,v_result.lease_owner,v_result.lease_fence,v_result.outcome,
    v_next_attempt,v_backoff_seconds,v_now+make_interval(secs=>v_backoff_seconds),
    v_policy.policy_code,v_policy.policy_version,v_policy.policy_sha,
    p_actor_execution_id,v_now
  ) returning * into v_receipt;

  return to_jsonb(v_receipt)||jsonb_build_object(
    'result','RETRY_AUTHORIZED',
    'lease_rotation_required',true,
    'next_task_materialization_owner','fn_lf_operation_advance_execution_v1'
  );
end;
$function$;

revoke all on function public.fn_lf_operation_authorize_retry_v1(
  text,text,text,integer,text,bigint,text
) from public,anon,authenticated;
grant execute on function public.fn_lf_operation_authorize_retry_v1(
  text,text,text,integer,text,bigint,text
) to service_role;

create or replace function public.fn_lf_operation_advance_execution_v1(
  p_execution_id text,
  p_actor_execution_id text,
  p_source_task_id text default null,
  p_source_step_id text default null,
  p_source_attempt_no integer default null
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
  v_result record;
  v_existing public.lf_operation_advance_receipt%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_retry public.lf_operation_retry_receipt%rowtype;
  v_next_ref text;
  v_next_exists boolean;
  v_kind text;
  v_disposition text;
  v_next_task_id text;
  v_next_step_id text;
  v_next_attempt_no integer;
  v_external_handoff_ref text;
  v_next_seq bigint;
  v_receipt public.lf_operation_advance_receipt%rowtype;
  v_source_count integer;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;

  v_source_count :=
    (case when p_source_task_id is null then 0 else 1 end)
    + (case when p_source_step_id is null then 0 else 1 end)
    + (case when p_source_attempt_no is null then 0 else 1 end);
  if v_source_count not in (0,3) then raise exception 'ADVANCE_SOURCE_IDENTITY_MUST_BE_ALL_OR_NONE'; end if;
  if p_source_attempt_no is not null and p_source_attempt_no<1 then raise exception 'INVALID_SOURCE_ATTEMPT_NO'; end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.status is distinct from 'IN_PROGRESS' then raise exception 'EXECUTION_NOT_ADVANCEABLE'; end if;

  v_exec_json:=to_jsonb(v_exec);
  v_frozen_spec_digest:=v_exec_json->>'operation_spec_digest';
  if coalesce(v_frozen_spec_digest,'') !~ '^[0-9a-f]{64}$' then raise exception 'EXECUTION_OPERATION_SPEC_IDENTITY_MISSING'; end if;
  v_current_spec_digest:=public.fn_lf_operation_spec_digest_v1(v_exec.operation_code);
  if v_current_spec_digest is distinct from v_frozen_spec_digest then raise exception 'FROZEN_OPERATION_SPEC_DIGEST_MISMATCH'; end if;

  if v_source_count=0 then
    select * into v_existing from public.lf_operation_advance_receipt
    where execution_id=p_execution_id and transition_kind='INITIALIZE';
    if v_existing.execution_id is not null then
      return to_jsonb(v_existing)||jsonb_build_object('result','REPLAY_ACCEPTED_ADVANCE');
    end if;
    if v_exec.advance_seq<>0 or v_exec.current_task_id is not null
       or v_exec.current_step_id is not null or v_exec.current_attempt_no is not null then
      raise exception 'EXECUTION_ALREADY_INITIALIZED';
    end if;
    select s.step_id into v_next_step_id
    from public.lf_operation_steps s
    join public.lf_operation_step_contracts c
      on c.operation_code=s.operation_code and c.step_id=s.step_id
    where s.operation_code=v_exec.operation_code and s.active is true
    order by coalesce(s.execution_order,s.step_order),s.step_order,s.step_id
    limit 1;
    if v_next_step_id is null then raise exception 'INITIAL_EXECUTABLE_TASK_NOT_FOUND'; end if;
    v_kind:='INITIALIZE';
    v_disposition:='NEXT_TASK';
    v_next_task_id:=v_next_step_id;
    v_next_attempt_no:=1;
  else
    select * into v_existing from public.lf_operation_advance_receipt
    where execution_id=p_execution_id and transition_kind='RESULT'
      and source_task_id=p_source_task_id and source_step_id=p_source_step_id
      and source_attempt_no=p_source_attempt_no;
    if v_existing.execution_id is not null then
      return to_jsonb(v_existing)||jsonb_build_object('result','REPLAY_ACCEPTED_ADVANCE');
    end if;
    if row(v_exec.current_task_id,v_exec.current_step_id,v_exec.current_attempt_no)
       is distinct from row(p_source_task_id,p_source_step_id,p_source_attempt_no) then
      raise exception 'ADVANCE_SOURCE_IS_NOT_CURRENT_TASK';
    end if;

    select r.* into v_result
    from public.lf_operation_task_result r
    where r.execution_id=p_execution_id and r.task_id=p_source_task_id
      and r.step_id=p_source_step_id and r.attempt_no=p_source_attempt_no;
    if not found then raise exception 'ACCEPTED_RESULT_NOT_FOUND'; end if;

    select * into v_contract
    from public.lf_operation_step_contracts
    where operation_code=v_exec.operation_code and step_id=p_source_step_id;
    if v_contract.operation_code is null then raise exception 'CURRENT_STEP_CONTRACT_NOT_FOUND'; end if;

    v_kind:='RESULT';
    if v_result.outcome='RETRYABLE_FAILURE' then
      select * into v_retry
      from public.lf_operation_retry_receipt
      where execution_id=p_execution_id and task_id=p_source_task_id
        and step_id=p_source_step_id and source_attempt_no=p_source_attempt_no;
      if v_retry.execution_id is null then raise exception 'RETRY_POLICY_RECEIPT_REQUIRED'; end if;
      if v_retry.source_result_digest is distinct from v_result.result_digest
         or v_retry.source_lease_fence is distinct from v_result.lease_fence
         or v_retry.next_attempt_no is distinct from p_source_attempt_no+1 then
        raise exception 'RETRY_POLICY_RECEIPT_IDENTITY_MISMATCH';
      end if;
      if v_exec.lease_owner is null or v_exec.lease_expires_at is null or v_exec.lease_expires_at<=v_now
         or v_exec.lease_fence<=v_result.lease_fence then
        raise exception 'RETRY_REQUIRES_NEW_CURRENT_LEASE_FENCE';
      end if;
      if v_now<v_retry.retry_not_before then raise exception 'RETRY_BACKOFF_NOT_ELAPSED'; end if;
      v_disposition:='NEXT_TASK';
      v_next_task_id:=p_source_task_id;
      v_next_step_id:=p_source_step_id;
      v_next_attempt_no:=v_retry.next_attempt_no;
    else
      if v_exec.lease_owner is distinct from v_result.lease_owner
         or v_exec.lease_fence is distinct from v_result.lease_fence
         or v_exec.lease_expires_at is null or v_exec.lease_expires_at<=v_now then
        raise exception 'STALE_OR_MISSING_LEASE_FENCE';
      end if;
      if v_result.outcome='SUCCEEDED' then
        v_next_ref:=v_contract.next_if_pass;
      elsif v_result.outcome='BLOCKED' then
        v_next_ref:=v_contract.next_if_blocked;
      elsif v_result.outcome='FAILED' then
        raise exception 'ADVANCE_OUTCOME_NON_RETRYABLE_FAILURE';
      else
        raise exception 'ADVANCE_OUTCOME_REQUIRES_RETRY_POLICY';
      end if;

      if v_next_ref is null then
        v_disposition:='NO_NEXT_TASK';
      else
        select exists(
          select 1 from public.lf_operation_steps s
          join public.lf_operation_step_contracts c
            on c.operation_code=s.operation_code and c.step_id=s.step_id
          where s.operation_code=v_exec.operation_code and s.step_id=v_next_ref and s.active is true
        ) into v_next_exists;
        if v_next_exists then
          v_disposition:='NEXT_TASK';
          v_next_task_id:=v_next_ref;
          v_next_step_id:=v_next_ref;
          v_next_attempt_no:=1;
        else
          v_disposition:='EXTERNAL_HANDOFF';
          v_external_handoff_ref:=v_next_ref;
        end if;
      end if;
    end if;
  end if;

  v_next_seq:=v_exec.advance_seq+1;
  if v_disposition='NEXT_TASK' then
    insert into public.lf_operation_execution_task(
      execution_id,task_id,step_id,attempt_no,created_by_execution_id
    ) values (
      p_execution_id,v_next_task_id,v_next_step_id,v_next_attempt_no,p_actor_execution_id
    ) on conflict (execution_id,task_id,step_id,attempt_no) do nothing;
    if not exists (
      select 1 from public.lf_operation_execution_task
      where execution_id=p_execution_id and task_id=v_next_task_id
        and step_id=v_next_step_id and attempt_no=v_next_attempt_no
    ) then raise exception 'NEXT_TASK_IDENTITY_PERSISTENCE_FAILED'; end if;
  end if;

  insert into public.lf_operation_advance_receipt(
    execution_id,advance_seq,transition_kind,
    source_task_id,source_step_id,source_attempt_no,
    source_result_digest,source_outcome,source_lease_owner,source_lease_fence,
    operation_spec_digest,disposition,
    next_task_id,next_step_id,next_attempt_no,external_handoff_ref,
    advanced_by_execution_id,materialized_lease_fence
  ) values (
    p_execution_id,v_next_seq,v_kind,
    p_source_task_id,p_source_step_id,p_source_attempt_no,
    case when v_kind='RESULT' then v_result.result_digest else null end,
    case when v_kind='RESULT' then v_result.outcome else null end,
    case when v_kind='RESULT' then v_result.lease_owner else null end,
    case when v_kind='RESULT' then v_result.lease_fence else null end,
    v_current_spec_digest,v_disposition,
    v_next_task_id,v_next_step_id,v_next_attempt_no,v_external_handoff_ref,
    p_actor_execution_id,v_exec.lease_fence
  ) returning * into v_receipt;

  update public.lf_operation_execution
  set current_task_id=case when v_disposition='NEXT_TASK' then v_next_task_id else null end,
      current_step_id=case when v_disposition='NEXT_TASK' then v_next_step_id else null end,
      current_attempt_no=case when v_disposition='NEXT_TASK' then v_next_attempt_no else null end,
      advance_seq=v_next_seq,
      updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id;

  return to_jsonb(v_receipt)||jsonb_build_object(
    'result','ADVANCE_ACCEPTED',
    'execution_status_advanced_to_terminal',false
  );
end;
$function$;

revoke all on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) from public,anon,authenticated;
grant execute on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) to service_role;

comment on function public.fn_lf_operation_authorize_retry_v1(
  text,text,text,integer,text,bigint,text
) is 'G10 policy-only retry authorization. It requires one canonical RETRY_POLICY snapshot, an exact current RETRYABLE_FAILURE result and current source fence. It persists an immutable authorization but never changes current task, attempt, fence or runtime state.';

comment on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) is 'G07 remains sole next-task owner. G10 extends it only to consume an immutable retry authorization after G05 has rotated to a strictly newer current fence and the policy backoff elapsed; the materialized retry is the same task/step with attempt_no+1.';
