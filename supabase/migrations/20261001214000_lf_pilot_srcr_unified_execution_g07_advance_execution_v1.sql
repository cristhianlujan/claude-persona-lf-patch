-- CANDIDATE SOURCE. PILOT-SRCR-UNIFIED-EXECUTION-V1 / G07 ADVANCE_EXECUTION.
-- Authorized for isolated PR/local disposable CI only by lf_eventos.id=15197.
-- NO LIVE SUPABASE APPLY / NO MERGE / NO PRODUCTION ACTIVATION.
-- G07 is the sole owner of first-task selection and subsequent next-task selection.
-- It consumes G02 frozen identity and G06 accepted results/task identities.
-- It does not own checkpointing, terminal-state closure, retry policy, runtime dispatch, or queues.

alter table public.lf_operation_execution
  add column if not exists current_task_id text,
  add column if not exists current_step_id text,
  add column if not exists current_attempt_no integer,
  add column if not exists advance_seq bigint not null default 0;

do $g07_execution_state_constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='lf_operation_execution_current_task_identity_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_current_task_identity_ck check (
        (
          current_task_id is null
          and current_step_id is null
          and current_attempt_no is null
        )
        or
        (
          btrim(coalesce(current_task_id,'')) <> ''
          and length(current_task_id) <= 200
          and btrim(coalesce(current_step_id,'')) <> ''
          and length(current_step_id) <= 200
          and current_attempt_no >= 1
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='lf_operation_execution_advance_seq_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_advance_seq_ck check (advance_seq >= 0);
  end if;
end
$g07_execution_state_constraints$;

create table if not exists public.lf_operation_advance_receipt (
  execution_id text not null references public.lf_operation_execution(execution_id)
    on update restrict on delete restrict,
  advance_seq bigint not null check (advance_seq >= 1),
  transition_kind text not null check (transition_kind in ('INITIALIZE','RESULT')),
  source_task_id text,
  source_step_id text,
  source_attempt_no integer,
  source_result_digest text,
  source_outcome text,
  source_lease_owner text,
  source_lease_fence bigint,
  operation_spec_digest text not null check (operation_spec_digest ~ '^[0-9a-f]{64}$'),
  disposition text not null check (disposition in ('NEXT_TASK','NO_NEXT_TASK','EXTERNAL_HANDOFF')),
  next_task_id text,
  next_step_id text,
  next_attempt_no integer,
  external_handoff_ref text,
  advanced_by_execution_id text not null check (btrim(advanced_by_execution_id) <> ''),
  advanced_at timestamptz not null default now(),
  primary key (execution_id, advance_seq),
  constraint lf_operation_advance_receipt_shape_ck check (
    (
      transition_kind='INITIALIZE'
      and source_task_id is null
      and source_step_id is null
      and source_attempt_no is null
      and source_result_digest is null
      and source_outcome is null
      and source_lease_owner is null
      and source_lease_fence is null
    )
    or
    (
      transition_kind='RESULT'
      and btrim(coalesce(source_task_id,'')) <> ''
      and btrim(coalesce(source_step_id,'')) <> ''
      and source_attempt_no >= 1
      and btrim(coalesce(source_result_digest,'')) <> ''
      and btrim(coalesce(source_outcome,'')) <> ''
      and btrim(coalesce(source_lease_owner,'')) <> ''
      and source_lease_fence >= 0
    )
  ),
  constraint lf_operation_advance_receipt_next_shape_ck check (
    (
      disposition='NEXT_TASK'
      and btrim(coalesce(next_task_id,'')) <> ''
      and btrim(coalesce(next_step_id,'')) <> ''
      and next_attempt_no >= 1
      and external_handoff_ref is null
    )
    or
    (
      disposition='NO_NEXT_TASK'
      and next_task_id is null
      and next_step_id is null
      and next_attempt_no is null
      and external_handoff_ref is null
    )
    or
    (
      disposition='EXTERNAL_HANDOFF'
      and next_task_id is null
      and next_step_id is null
      and next_attempt_no is null
      and btrim(coalesce(external_handoff_ref,'')) <> ''
    )
  )
);

create unique index if not exists uq_lf_operation_advance_receipt_result_source_v1
  on public.lf_operation_advance_receipt(
    execution_id, source_task_id, source_step_id, source_attempt_no
  )
  where transition_kind='RESULT';

create unique index if not exists uq_lf_operation_advance_receipt_initialize_v1
  on public.lf_operation_advance_receipt(execution_id)
  where transition_kind='INITIALIZE';

create or replace function public.lf_operation_advance_receipt_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  raise exception 'OPERATION_ADVANCE_RECEIPT_IMMUTABLE';
end;
$function$;

drop trigger if exists trg_lf_operation_advance_receipt_immutable_v1
  on public.lf_operation_advance_receipt;
create trigger trg_lf_operation_advance_receipt_immutable_v1
before update or delete on public.lf_operation_advance_receipt
for each row execute function public.lf_operation_advance_receipt_immutable_v1();

alter table public.lf_operation_advance_receipt enable row level security;
revoke all on public.lf_operation_advance_receipt from public, anon, authenticated, service_role;
grant select on public.lf_operation_advance_receipt to service_role;

create or replace function public.fn_lf_operation_spec_digest_v1(p_operation_code text)
returns text
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_registry jsonb;
  v_steps jsonb;
  v_active_count integer;
  v_contract_count integer;
begin
  if btrim(coalesce(p_operation_code,''))='' then
    raise exception 'INVALID_OPERATION_CODE';
  end if;

  select jsonb_build_object(
    'operation_code',r.operation_code,
    'version',r.version,
    'status',r.status,
    'source_model',r.source_model,
    'source_repo',r.source_repo,
    'source_paths',coalesce(r.source_paths,'[]'::jsonb),
    'operation_family',r.operation_family,
    'operation_domain',r.operation_domain,
    'operation_type',r.operation_type,
    'applies_to_asset_type',r.applies_to_asset_type,
    'lifecycle_state_code',r.lifecycle_state_code
  )
  into v_registry
  from public.lf_operation_registry r
  where r.operation_code=p_operation_code;

  if v_registry is null then
    raise exception 'OPERATION_SPEC_REGISTRY_NOT_FOUND';
  end if;

  select count(*),
         count(c.step_id),
         jsonb_agg(
           jsonb_build_object(
             'step_id',s.step_id,
             'step_order',s.step_order,
             'execution_order',s.execution_order,
             'required',s.required,
             'evidence_required',s.evidence_required,
             'source_path',s.source_path,
             'source_sha',s.source_sha,
             'contract_code',c.contract_code,
             'purpose',c.purpose,
             'input_required',c.input_required,
             'resolver_ref',c.resolver_ref,
             'output_payload',c.output_payload,
             'pass_condition',c.pass_condition,
             'block_condition',c.block_condition,
             'fail_condition',c.fail_condition,
             'blocking_code',c.blocking_code,
             'mini_judge_code',c.mini_judge_code,
             'required_evidence_keys',c.required_evidence_keys,
             'next_if_pass',c.next_if_pass,
             'next_if_blocked',c.next_if_blocked,
             'contract_status',c.status
           )
           order by coalesce(s.execution_order,s.step_order),s.step_order,s.step_id
         )
  into v_active_count,v_contract_count,v_steps
  from public.lf_operation_steps s
  left join public.lf_operation_step_contracts c
    on c.operation_code=s.operation_code
   and c.step_id=s.step_id
  where s.operation_code=p_operation_code
    and s.active is true;

  if v_active_count=0 then
    raise exception 'OPERATION_SPEC_HAS_NO_ACTIVE_STEPS';
  end if;
  if v_contract_count<>v_active_count then
    raise exception 'OPERATION_SPEC_STEP_CONTRACT_MISSING';
  end if;

  return encode(
    extensions.digest(
      jsonb_build_object('registry',v_registry,'steps',v_steps)::text,
      'sha256'
    ),
    'hex'
  );
end;
$function$;

revoke all on function public.fn_lf_operation_spec_digest_v1(text)
  from public, anon, authenticated;
grant execute on function public.fn_lf_operation_spec_digest_v1(text)
  to service_role;

create or replace function public.lf_operation_execution_advance_state_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_receipt public.lf_operation_advance_receipt%rowtype;
begin
  if row(new.current_task_id,new.current_step_id,new.current_attempt_no,new.advance_seq)
     is not distinct from
     row(old.current_task_id,old.current_step_id,old.current_attempt_no,old.advance_seq) then
    return new;
  end if;

  if new.advance_seq <> old.advance_seq + 1 then
    raise exception 'ADVANCE_SEQUENCE_MUST_INCREMENT_BY_ONE';
  end if;

  select * into v_receipt
  from public.lf_operation_advance_receipt
  where execution_id=new.execution_id
    and advance_seq=new.advance_seq;

  if v_receipt.execution_id is null then
    raise exception 'ADVANCE_STATE_RECEIPT_REQUIRED';
  end if;

  if v_receipt.disposition='NEXT_TASK' then
    if row(new.current_task_id,new.current_step_id,new.current_attempt_no)
       is distinct from
       row(v_receipt.next_task_id,v_receipt.next_step_id,v_receipt.next_attempt_no) then
      raise exception 'ADVANCE_STATE_RECEIPT_MISMATCH';
    end if;
  else
    if new.current_task_id is not null
       or new.current_step_id is not null
       or new.current_attempt_no is not null then
      raise exception 'ADVANCE_NON_TASK_DISPOSITION_MUST_CLEAR_CURRENT_TASK';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_lf_operation_execution_advance_state_guard_v1
  on public.lf_operation_execution;
create trigger trg_lf_operation_execution_advance_state_guard_v1
before update of current_task_id,current_step_id,current_attempt_no,advance_seq
on public.lf_operation_execution
for each row execute function public.lf_operation_execution_advance_state_guard_v1();

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
  if v_source_count not in (0,3) then
    raise exception 'ADVANCE_SOURCE_IDENTITY_MUST_BE_ALL_OR_NONE';
  end if;
  if p_source_attempt_no is not null and p_source_attempt_no < 1 then
    raise exception 'INVALID_SOURCE_ATTEMPT_NO';
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.status is distinct from 'IN_PROGRESS' then raise exception 'EXECUTION_NOT_ADVANCEABLE'; end if;

  v_exec_json := to_jsonb(v_exec);
  v_frozen_spec_digest := v_exec_json->>'operation_spec_digest';
  if coalesce(v_frozen_spec_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'EXECUTION_OPERATION_SPEC_IDENTITY_MISSING';
  end if;

  v_current_spec_digest := public.fn_lf_operation_spec_digest_v1(v_exec.operation_code);
  if v_current_spec_digest is distinct from v_frozen_spec_digest then
    raise exception 'FROZEN_OPERATION_SPEC_DIGEST_MISMATCH';
  end if;

  if v_source_count=0 then
    select * into v_existing
    from public.lf_operation_advance_receipt
    where execution_id=p_execution_id and transition_kind='INITIALIZE';
    if v_existing.execution_id is not null then
      return to_jsonb(v_existing) || jsonb_build_object('result','REPLAY_ACCEPTED_ADVANCE');
    end if;

    if v_exec.advance_seq<>0
       or v_exec.current_task_id is not null
       or v_exec.current_step_id is not null
       or v_exec.current_attempt_no is not null then
      raise exception 'EXECUTION_ALREADY_INITIALIZED';
    end if;

    select s.step_id into v_next_step_id
    from public.lf_operation_steps s
    join public.lf_operation_step_contracts c
      on c.operation_code=s.operation_code and c.step_id=s.step_id
    where s.operation_code=v_exec.operation_code
      and s.active is true
    order by coalesce(s.execution_order,s.step_order),s.step_order,s.step_id
    limit 1;

    if v_next_step_id is null then raise exception 'INITIAL_EXECUTABLE_TASK_NOT_FOUND'; end if;
    v_kind := 'INITIALIZE';
    v_disposition := 'NEXT_TASK';
    v_next_task_id := v_next_step_id;
    v_next_attempt_no := 1;
  else
    select * into v_existing
    from public.lf_operation_advance_receipt
    where execution_id=p_execution_id
      and transition_kind='RESULT'
      and source_task_id=p_source_task_id
      and source_step_id=p_source_step_id
      and source_attempt_no=p_source_attempt_no;
    if v_existing.execution_id is not null then
      return to_jsonb(v_existing) || jsonb_build_object('result','REPLAY_ACCEPTED_ADVANCE');
    end if;

    if row(v_exec.current_task_id,v_exec.current_step_id,v_exec.current_attempt_no)
       is distinct from
       row(p_source_task_id,p_source_step_id,p_source_attempt_no) then
      raise exception 'ADVANCE_SOURCE_IS_NOT_CURRENT_TASK';
    end if;

    select r.* into v_result
    from public.lf_operation_task_result r
    where r.execution_id=p_execution_id
      and r.task_id=p_source_task_id
      and r.step_id=p_source_step_id
      and r.attempt_no=p_source_attempt_no;
    if not found then raise exception 'ACCEPTED_RESULT_NOT_FOUND'; end if;

    if v_exec.lease_owner is distinct from v_result.lease_owner
       or v_exec.lease_fence is distinct from v_result.lease_fence
       or v_exec.lease_expires_at is null
       or v_exec.lease_expires_at<=v_now then
      raise exception 'STALE_OR_MISSING_LEASE_FENCE';
    end if;

    select * into v_contract
    from public.lf_operation_step_contracts
    where operation_code=v_exec.operation_code
      and step_id=p_source_step_id;
    if v_contract.operation_code is null then raise exception 'CURRENT_STEP_CONTRACT_NOT_FOUND'; end if;

    if v_result.outcome='SUCCEEDED' then
      v_next_ref := v_contract.next_if_pass;
    elsif v_result.outcome='BLOCKED' then
      v_next_ref := v_contract.next_if_blocked;
    else
      raise exception 'ADVANCE_OUTCOME_REQUIRES_RETRY_POLICY';
    end if;

    v_kind := 'RESULT';
    if v_next_ref is null then
      v_disposition := 'NO_NEXT_TASK';
    else
      select exists(
        select 1
        from public.lf_operation_steps s
        join public.lf_operation_step_contracts c
          on c.operation_code=s.operation_code and c.step_id=s.step_id
        where s.operation_code=v_exec.operation_code
          and s.step_id=v_next_ref
          and s.active is true
      ) into v_next_exists;

      if v_next_exists then
        v_disposition := 'NEXT_TASK';
        v_next_task_id := v_next_ref;
        v_next_step_id := v_next_ref;
        v_next_attempt_no := 1;
      else
        v_disposition := 'EXTERNAL_HANDOFF';
        v_external_handoff_ref := v_next_ref;
      end if;
    end if;
  end if;

  v_next_seq := v_exec.advance_seq + 1;

  if v_disposition='NEXT_TASK' then
    insert into public.lf_operation_execution_task(
      execution_id,task_id,step_id,attempt_no,created_by_execution_id
    ) values (
      p_execution_id,v_next_task_id,v_next_step_id,v_next_attempt_no,p_actor_execution_id
    )
    on conflict (execution_id,task_id,step_id,attempt_no) do nothing;

    if not exists (
      select 1 from public.lf_operation_execution_task
      where execution_id=p_execution_id
        and task_id=v_next_task_id
        and step_id=v_next_step_id
        and attempt_no=v_next_attempt_no
    ) then
      raise exception 'NEXT_TASK_IDENTITY_PERSISTENCE_FAILED';
    end if;
  end if;

  insert into public.lf_operation_advance_receipt(
    execution_id,advance_seq,transition_kind,
    source_task_id,source_step_id,source_attempt_no,
    source_result_digest,source_outcome,source_lease_owner,source_lease_fence,
    operation_spec_digest,disposition,
    next_task_id,next_step_id,next_attempt_no,external_handoff_ref,
    advanced_by_execution_id
  ) values (
    p_execution_id,v_next_seq,v_kind,
    p_source_task_id,p_source_step_id,p_source_attempt_no,
    case when v_kind='RESULT' then v_result.result_digest else null end,
    case when v_kind='RESULT' then v_result.outcome else null end,
    case when v_kind='RESULT' then v_result.lease_owner else null end,
    case when v_kind='RESULT' then v_result.lease_fence else null end,
    v_current_spec_digest,v_disposition,
    v_next_task_id,v_next_step_id,v_next_attempt_no,v_external_handoff_ref,
    p_actor_execution_id
  )
  returning * into v_receipt;

  update public.lf_operation_execution
  set current_task_id=case when v_disposition='NEXT_TASK' then v_next_task_id else null end,
      current_step_id=case when v_disposition='NEXT_TASK' then v_next_step_id else null end,
      current_attempt_no=case when v_disposition='NEXT_TASK' then v_next_attempt_no else null end,
      advance_seq=v_next_seq,
      updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id;

  return to_jsonb(v_receipt) || jsonb_build_object(
    'result','ADVANCE_ACCEPTED',
    'execution_status_advanced_to_terminal',false
  );
end;
$function$;

revoke all on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) from public, anon, authenticated;
grant execute on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) to service_role;

comment on function public.fn_lf_operation_advance_execution_v1(
  text,text,text,text,integer
) is
  'G07 candidate and sole next-task owner. Initializes the first task or advances from one accepted fenced result. Persists current task state in lf_operation_execution, immutable transition receipt and next task identity. It never checkpoints, retries, marks terminal, dispatches runtime work or delegates routing to a queue/profile.';
