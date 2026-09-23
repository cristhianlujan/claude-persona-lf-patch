-- CANDIDATE ONLY. PILOT-SRCR-UNIFIED-EXECUTION-V1 / G02 EXECUTION_IDENTITY.
-- No live Supabase apply is authorized by this file.
-- Extends the existing public.lf_operation_execution authority; no parallel execution engine.

alter table public.lf_operation_execution
  add column if not exists operation_spec_id text,
  add column if not exists operation_spec_digest text,
  add column if not exists profile_code text,
  add column if not exists profile_source_sha text,
  add column if not exists executor_binding_id text,
  add column if not exists executor_binding_digest text;

do $identity_constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='lf_operation_execution_unified_identity_ck'
      and conrelid='public.lf_operation_execution'::regclass
  ) then
    alter table public.lf_operation_execution
      add constraint lf_operation_execution_unified_identity_ck check (
        (
          operation_spec_id is null
          and operation_spec_digest is null
          and profile_code is null
          and profile_source_sha is null
          and executor_binding_id is null
          and executor_binding_digest is null
        )
        or
        (
          btrim(coalesce(operation_spec_id,'')) <> ''
          and length(operation_spec_id) <= 200
          and operation_spec_digest ~ '^[0-9a-f]{64}$'
          and btrim(coalesce(profile_code,'')) <> ''
          and length(profile_code) <= 200
          and profile_source_sha ~ '^[0-9a-f]{40}$'
          and btrim(coalesce(executor_binding_id,'')) <> ''
          and length(executor_binding_id) <= 200
          and executor_binding_digest ~ '^[0-9a-f]{64}$'
        )
      );
  end if;
end
$identity_constraints$;

create or replace function public.lf_operation_execution_identity_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if row(
       new.operation_spec_id,
       new.operation_spec_digest,
       new.profile_code,
       new.profile_source_sha,
       new.executor_binding_id,
       new.executor_binding_digest
     ) is distinct from row(
       old.operation_spec_id,
       old.operation_spec_digest,
       old.profile_code,
       old.profile_source_sha,
       old.executor_binding_id,
       old.executor_binding_digest
     ) then
    raise exception 'EXECUTION_IDENTITY_IMMUTABLE';
  end if;
  return new;
end;
$function$;

revoke all on function public.lf_operation_execution_identity_immutable_v1() from public, anon, authenticated;
grant execute on function public.lf_operation_execution_identity_immutable_v1() to service_role;

drop trigger if exists trg_lf_operation_execution_identity_immutable_v1 on public.lf_operation_execution;
create trigger trg_lf_operation_execution_identity_immutable_v1
before update of operation_spec_id, operation_spec_digest, profile_code, profile_source_sha,
  executor_binding_id, executor_binding_digest
on public.lf_operation_execution
for each row
execute function public.lf_operation_execution_identity_immutable_v1();

create or replace function public.fn_lf_operation_reserve_execution_v2(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_operation_spec_id text,
  p_operation_spec_digest text,
  p_profile_code text,
  p_profile_source_sha text,
  p_executor_binding_id text,
  p_executor_binding_digest text,
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

  if btrim(coalesce(p_operation_spec_id,''))='' or length(p_operation_spec_id)>200 then
    raise exception 'INVALID_OPERATION_SPEC_ID';
  end if;
  if coalesce(p_operation_spec_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_OPERATION_SPEC_DIGEST';
  end if;
  if btrim(coalesce(p_profile_code,''))='' or length(p_profile_code)>200 then
    raise exception 'INVALID_PROFILE_CODE';
  end if;
  if coalesce(p_profile_source_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'INVALID_PROFILE_SOURCE_SHA';
  end if;
  if btrim(coalesce(p_executor_binding_id,''))='' or length(p_executor_binding_id)>200 then
    raise exception 'INVALID_EXECUTOR_BINDING_ID';
  end if;
  if coalesce(p_executor_binding_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_EXECUTOR_BINDING_DIGEST';
  end if;

  insert into public.lf_operation_execution(
    execution_id, operation_code, target_type, target_code, target_repo, target_path,
    idempotency_key, request_sha256, manifest, created_by_execution_id,
    operation_spec_id, operation_spec_digest, profile_code, profile_source_sha,
    executor_binding_id, executor_binding_digest
  ) values (
    p_execution_id, p_operation_code, p_target_type, p_target_code, p_target_repo, p_target_path,
    p_idempotency_key, p_request_sha256, p_manifest, p_actor_execution_id,
    p_operation_spec_id, p_operation_spec_digest, p_profile_code, p_profile_source_sha,
    p_executor_binding_id, p_executor_binding_digest
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
  if row(
       v_row.operation_spec_id,
       v_row.operation_spec_digest,
       v_row.profile_code,
       v_row.profile_source_sha,
       v_row.executor_binding_id,
       v_row.executor_binding_digest
     ) is distinct from row(
       p_operation_spec_id,
       p_operation_spec_digest,
       p_profile_code,
       p_profile_source_sha,
       p_executor_binding_id,
       p_executor_binding_digest
     ) then
    raise exception 'EXECUTION_IDENTITY_REPLAY_MISMATCH';
  end if;

  return jsonb_build_object(
    'result',case when v_inserted then 'RESERVED_NEW_EXECUTION' else 'REPLAY_EXISTING_EXECUTION' end,
    'execution_id',v_row.execution_id,
    'operation_code',v_row.operation_code,
    'operation_spec_id',v_row.operation_spec_id,
    'operation_spec_digest',v_row.operation_spec_digest,
    'profile_code',v_row.profile_code,
    'profile_source_sha',v_row.profile_source_sha,
    'executor_binding_id',v_row.executor_binding_id,
    'executor_binding_digest',v_row.executor_binding_digest,
    'idempotency_key',v_row.idempotency_key,
    'request_sha256',v_row.request_sha256,
    'status',v_row.status,
    'dispatch_permitted',v_inserted
  );
end;
$function$;

revoke all on function public.fn_lf_operation_reserve_execution_v2(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.fn_lf_operation_reserve_execution_v2(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb
) to service_role;

comment on function public.fn_lf_operation_reserve_execution_v2(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb
) is 'G02 candidate: reserves one durable execution identity. Operation spec, profile source and executor binding identities are supplied at creation, replay-checked and immutable after insert.';
