alter table public.lf_operation_execution
  add column if not exists idempotency_key text,
  add column if not exists request_sha256 text,
  add column if not exists lease_owner text,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists lease_fence bigint not null default 0,
  add column if not exists checkpoint_seq bigint not null default 0,
  add column if not exists checkpoint_payload jsonb not null default '{}'::jsonb;

do $ddl$
begin
  if not exists (
    select 1 from pg_constraint where conname='lf_operation_execution_idempotency_pair_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_idempotency_pair_ck check (
        (idempotency_key is null and request_sha256 is null)
        or
        (idempotency_key is not null
          and btrim(idempotency_key) <> ''
          and length(idempotency_key) <= 200
          and request_sha256 ~ '^[0-9a-f]{64}$')
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname='lf_operation_execution_lease_pair_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_lease_pair_ck check (
        (lease_owner is null and lease_expires_at is null)
        or
        (lease_owner is not null and btrim(lease_owner) <> '' and lease_expires_at is not null)
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname='lf_operation_execution_nonnegative_control_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_nonnegative_control_ck check (
        lease_fence >= 0 and checkpoint_seq >= 0
      );
  end if;
end
$ddl$;

create unique index if not exists lf_operation_execution_idempotency_uq
  on public.lf_operation_execution(operation_code,idempotency_key)
  where idempotency_key is not null;

create table if not exists public.lf_operation_effect_guard (
  execution_id text not null references public.lf_operation_execution(execution_id) on update restrict on delete restrict,
  effect_scope text not null check (btrim(effect_scope) <> '' and length(effect_scope) <= 200),
  effect_request_sha256 text not null check (effect_request_sha256 ~ '^[0-9a-f]{64}$'),
  dispatch_key text not null check (btrim(dispatch_key) <> '' and length(dispatch_key) <= 200),
  state text not null default 'RESERVED' check (state in ('RESERVED','SUCCEEDED')),
  receipt jsonb,
  reserved_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_by_execution_id text not null,
  updated_by_execution_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (execution_id,effect_scope),
  unique (dispatch_key),
  check ((state='RESERVED' and resolved_at is null) or (state='SUCCEEDED' and resolved_at is not null and receipt is not null))
);

alter table public.lf_operation_effect_guard enable row level security;
revoke all on public.lf_operation_effect_guard from public, anon, authenticated;
grant select, insert, update on public.lf_operation_effect_guard to service_role;

create or replace function public.fn_lf_operation_reserve_execution_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_target_repo text default null,
  p_target_path text default null,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_row public.lf_operation_execution%rowtype;
  v_inserted boolean := false;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_operation_code,''))='' then raise exception 'INVALID_OPERATION_CODE'; end if;
  if btrim(coalesce(p_target_type,''))='' or btrim(coalesce(p_target_code,''))='' then raise exception 'INVALID_TARGET'; end if;
  if btrim(coalesce(p_idempotency_key,''))='' or length(p_idempotency_key)>200 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  if coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_REQUEST_SHA256'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;
  if p_manifest is null or jsonb_typeof(p_manifest)<>'object' then raise exception 'INVALID_MANIFEST'; end if;

  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,target_repo,target_path,
    idempotency_key,request_sha256,manifest,created_by_execution_id
  ) values (
    p_execution_id,p_operation_code,p_target_type,p_target_code,p_target_repo,p_target_path,
    p_idempotency_key,p_request_sha256,p_manifest,p_actor_execution_id
  )
  on conflict (operation_code,idempotency_key) where idempotency_key is not null do nothing
  returning * into v_row;

  if v_row.execution_id is not null then
    v_inserted := true;
  else
    select * into v_row
    from public.lf_operation_execution
    where operation_code=p_operation_code and idempotency_key=p_idempotency_key;
  end if;

  if v_row.execution_id is null then raise exception 'IDEMPOTENCY_RESERVATION_UNAVAILABLE'; end if;
  if v_row.request_sha256 is distinct from p_request_sha256 then
    raise exception 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST';
  end if;
  if v_row.target_type is distinct from p_target_type
     or v_row.target_code is distinct from p_target_code
     or v_row.target_repo is distinct from p_target_repo
     or v_row.target_path is distinct from p_target_path then
    raise exception 'IDEMPOTENCY_REPLAY_TARGET_MISMATCH';
  end if;

  return jsonb_build_object(
    'result',case when v_inserted then 'RESERVED_NEW_EXECUTION' else 'REPLAY_EXISTING_EXECUTION' end,
    'execution_id',v_row.execution_id,
    'operation_code',v_row.operation_code,
    'idempotency_key',v_row.idempotency_key,
    'request_sha256',v_row.request_sha256,
    'status',v_row.status,
    'dispatch_permitted',v_inserted
  );
end;
$function$;

create or replace function public.fn_lf_operation_acquire_lease_v1(
  p_execution_id text,
  p_lease_owner text,
  p_ttl_seconds integer,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_row public.lf_operation_execution%rowtype;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_lease_owner,''))='' or length(p_lease_owner)>200 then raise exception 'INVALID_LEASE_OWNER'; end if;
  if p_ttl_seconds is null or p_ttl_seconds < 5 or p_ttl_seconds > 3600 then raise exception 'INVALID_LEASE_TTL'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;

  update public.lf_operation_execution
  set lease_fence = case
        when lease_owner=p_lease_owner and lease_expires_at>v_now then lease_fence
        else lease_fence+1
      end,
      lease_owner=p_lease_owner,
      lease_expires_at=v_now+make_interval(secs=>p_ttl_seconds),
      updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id
    and (lease_owner is null or lease_expires_at is null or lease_expires_at<=v_now or lease_owner=p_lease_owner)
  returning * into v_row;

  if v_row.execution_id is not null then
    return jsonb_build_object('result','LEASE_ACQUIRED','execution_id',v_row.execution_id,
      'lease_owner',v_row.lease_owner,'lease_fence',v_row.lease_fence,'lease_expires_at',v_row.lease_expires_at);
  end if;

  select * into v_row from public.lf_operation_execution where execution_id=p_execution_id;
  if v_row.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  return jsonb_build_object('result','BLOCKED','code','LEASE_HELD','execution_id',v_row.execution_id,
    'lease_owner',v_row.lease_owner,'lease_fence',v_row.lease_fence,'lease_expires_at',v_row.lease_expires_at);
end;
$function$;

create or replace function public.fn_lf_operation_checkpoint_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_checkpoint_seq bigint,
  p_checkpoint_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_row public.lf_operation_execution%rowtype;
begin
  if p_checkpoint_seq is null or p_checkpoint_seq < 1 then raise exception 'INVALID_CHECKPOINT_SEQ'; end if;
  if p_checkpoint_payload is null or jsonb_typeof(p_checkpoint_payload)<>'object' then raise exception 'INVALID_CHECKPOINT_PAYLOAD'; end if;
  select * into v_row from public.lf_operation_execution where execution_id=p_execution_id for update;
  if v_row.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_row.lease_owner is distinct from p_lease_owner or v_row.lease_fence is distinct from p_lease_fence
     or v_row.lease_expires_at is null or v_row.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;
  if p_checkpoint_seq < v_row.checkpoint_seq then raise exception 'CHECKPOINT_NON_MONOTONIC'; end if;
  if p_checkpoint_seq = v_row.checkpoint_seq then
    if p_checkpoint_payload is distinct from v_row.checkpoint_payload then raise exception 'CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD'; end if;
    return jsonb_build_object('result','REPLAY_CHECKPOINT','execution_id',v_row.execution_id,'checkpoint_seq',v_row.checkpoint_seq);
  end if;
  update public.lf_operation_execution
  set checkpoint_seq=p_checkpoint_seq,checkpoint_payload=p_checkpoint_payload,updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id;
  return jsonb_build_object('result','CHECKPOINT_PERSISTED','execution_id',p_execution_id,'checkpoint_seq',p_checkpoint_seq);
end;
$function$;

create or replace function public.fn_lf_operation_reserve_effect_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_effect_scope text,
  p_effect_request_sha256 text,
  p_dispatch_key text,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_inserted boolean := false;
begin
  if btrim(coalesce(p_effect_scope,''))='' or length(p_effect_scope)>200 then raise exception 'INVALID_EFFECT_SCOPE'; end if;
  if coalesce(p_effect_request_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_EFFECT_REQUEST_SHA256'; end if;
  if btrim(coalesce(p_dispatch_key,''))='' or length(p_dispatch_key)>200 then raise exception 'INVALID_DISPATCH_KEY'; end if;

  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.lease_owner is distinct from p_lease_owner or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null or v_exec.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;

  insert into public.lf_operation_effect_guard(
    execution_id,effect_scope,effect_request_sha256,dispatch_key,created_by_execution_id
  ) values (p_execution_id,p_effect_scope,p_effect_request_sha256,p_dispatch_key,p_actor_execution_id)
  on conflict (execution_id,effect_scope) do nothing
  returning * into v_effect;

  if v_effect.execution_id is not null then
    v_inserted := true;
  else
    select * into v_effect from public.lf_operation_effect_guard
    where execution_id=p_execution_id and effect_scope=p_effect_scope;
  end if;

  if v_effect.effect_request_sha256 is distinct from p_effect_request_sha256
     or v_effect.dispatch_key is distinct from p_dispatch_key then
    raise exception 'EFFECT_SCOPE_REUSED_WITH_DIFFERENT_REQUEST';
  end if;

  if v_inserted then
    return jsonb_build_object('result','EFFECT_RESERVED_NEW','dispatch_permitted',true,
      'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key);
  end if;
  if v_effect.state='SUCCEEDED' then
    return jsonb_build_object('result','REPLAY_SUCCEEDED_EFFECT','dispatch_permitted',false,
      'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key,'receipt',v_effect.receipt);
  end if;
  return jsonb_build_object('result','RECONCILIATION_REQUIRED','dispatch_permitted',false,
    'code','EXISTING_EFFECT_RESERVATION_OUTCOME_NOT_DURABLY_RESOLVED',
    'execution_id',p_execution_id,'effect_scope',p_effect_scope,'dispatch_key',p_dispatch_key);
end;
$function$;

create or replace function public.fn_lf_operation_mark_effect_succeeded_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_effect_scope text,
  p_receipt jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
begin
  if p_receipt is null or jsonb_typeof(p_receipt)<>'object' then raise exception 'INVALID_EFFECT_RECEIPT'; end if;
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id for update;
  if v_exec.execution_id is null then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if v_exec.lease_owner is distinct from p_lease_owner or v_exec.lease_fence is distinct from p_lease_fence
     or v_exec.lease_expires_at is null or v_exec.lease_expires_at<=v_now then
    raise exception 'STALE_OR_MISSING_LEASE_FENCE';
  end if;
  select * into v_effect from public.lf_operation_effect_guard
    where execution_id=p_execution_id and effect_scope=p_effect_scope for update;
  if v_effect.execution_id is null then raise exception 'EFFECT_RESERVATION_NOT_FOUND'; end if;
  if v_effect.state='SUCCEEDED' then
    if v_effect.receipt is distinct from p_receipt then raise exception 'EFFECT_SUCCESS_RECEIPT_MISMATCH'; end if;
    return jsonb_build_object('result','REPLAY_EFFECT_SUCCESS','execution_id',p_execution_id,'effect_scope',p_effect_scope);
  end if;
  update public.lf_operation_effect_guard
  set state='SUCCEEDED',receipt=p_receipt,resolved_at=v_now,updated_by_execution_id=p_actor_execution_id,updated_at=v_now
  where execution_id=p_execution_id and effect_scope=p_effect_scope;
  return jsonb_build_object('result','EFFECT_SUCCESS_PERSISTED','execution_id',p_execution_id,'effect_scope',p_effect_scope);
end;
$function$;

create or replace function public.fn_lf_operation_release_lease_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_row public.lf_operation_execution%rowtype;
begin
  update public.lf_operation_execution
  set lease_owner=null,lease_expires_at=null,updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id and lease_owner=p_lease_owner and lease_fence=p_lease_fence
  returning * into v_row;
  if v_row.execution_id is null then raise exception 'STALE_OR_MISSING_LEASE_FENCE'; end if;
  return jsonb_build_object('result','LEASE_RELEASED','execution_id',v_row.execution_id,'lease_fence',v_row.lease_fence);
end;
$function$;

revoke all on function public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.fn_lf_operation_acquire_lease_v1(text,text,integer,text) from public, anon, authenticated;
revoke all on function public.fn_lf_operation_checkpoint_v1(text,text,bigint,bigint,jsonb,text) from public, anon, authenticated;
revoke all on function public.fn_lf_operation_reserve_effect_v1(text,text,bigint,text,text,text,text) from public, anon, authenticated;
revoke all on function public.fn_lf_operation_mark_effect_succeeded_v1(text,text,bigint,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.fn_lf_operation_release_lease_v1(text,text,bigint,text) from public, anon, authenticated;

grant execute on function public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function public.fn_lf_operation_acquire_lease_v1(text,text,integer,text) to service_role;
grant execute on function public.fn_lf_operation_checkpoint_v1(text,text,bigint,bigint,jsonb,text) to service_role;
grant execute on function public.fn_lf_operation_reserve_effect_v1(text,text,bigint,text,text,text,text) to service_role;
grant execute on function public.fn_lf_operation_mark_effect_succeeded_v1(text,text,bigint,text,jsonb,text) to service_role;
grant execute on function public.fn_lf_operation_release_lease_v1(text,text,bigint,text) to service_role;
