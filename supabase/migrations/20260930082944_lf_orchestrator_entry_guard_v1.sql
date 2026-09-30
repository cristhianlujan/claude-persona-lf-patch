alter table public.lf_capability_registry
  add column if not exists entry_guard_required boolean not null default true,
  add column if not exists entry_guard_code text not null default 'ORCHESTRATOR_EXECUTION_GUARD_V1';

alter table public.lf_capability_registry
  drop constraint if exists lf_capability_registry_entry_guard_code_ck;
alter table public.lf_capability_registry
  add constraint lf_capability_registry_entry_guard_code_ck
  check (not entry_guard_required or length(btrim(entry_guard_code)) >= 3);

comment on column public.lf_capability_registry.entry_guard_required is
'True means a new execution-to-capability binding must carry a valid orchestrator dispatch receipt before the capability can be entered.';
comment on column public.lf_capability_registry.entry_guard_code is
'Canonical shared entry guard. Current transversal standard: ORCHESTRATOR_EXECUTION_GUARD_V1.';

create table if not exists private.lf_orchestrator_dispatch_receipts_v1 (
  receipt_id uuid primary key default gen_random_uuid(),
  orchestrator_execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  consumer_execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  capability_code text not null references public.lf_capability_registry(capability_code) on delete restrict,
  plan_digest text not null check (plan_digest ~ '^[0-9a-f]{64}$'),
  dispatch_scope jsonb not null check (jsonb_typeof(dispatch_scope)='object'),
  orchestrator_operation_code text not null,
  orchestrator_operation_version text not null,
  guard_code text not null,
  receipt_sha256 text not null unique check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  issued_by_execution_id text not null,
  issued_at timestamptz not null default now(),
  unique(orchestrator_execution_id,consumer_execution_id,capability_code,plan_digest)
);

comment on table private.lf_orchestrator_dispatch_receipts_v1 is
'Append-only dispatch authority proving that an operational ORCHESTRATION execution dispatched one exact capability for one exact consumer execution and plan digest.';

create or replace function private.fn_block_lf_orchestrator_dispatch_receipt_mutation_v1()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
begin
  raise exception using errcode='55000', message='ORCHESTRATOR_DISPATCH_RECEIPT_IMMUTABLE';
end; $$;

drop trigger if exists trg_lf_orchestrator_dispatch_receipts_immutable_v1 on private.lf_orchestrator_dispatch_receipts_v1;
create trigger trg_lf_orchestrator_dispatch_receipts_immutable_v1
before update or delete on private.lf_orchestrator_dispatch_receipts_v1
for each row execute function private.fn_block_lf_orchestrator_dispatch_receipt_mutation_v1();

create or replace function public.fn_lf_orchestrator_dispatch_receipt_v1(
  p_orchestrator_execution_id text,
  p_consumer_execution_id text,
  p_capability_code text,
  p_plan_digest text,
  p_dispatch_scope jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','public','private','extensions'
as $$
declare
  v_orch public.lf_operation_execution%rowtype;
  v_cons public.lf_operation_execution%rowtype;
  v_cap public.lf_capability_registry%rowtype;
  v_op public.lf_operation_registry%rowtype;
  v_payload jsonb;
  v_sha text;
  v_existing private.lf_orchestrator_dispatch_receipts_v1%rowtype;
  v_id uuid;
begin
  if btrim(coalesce(p_orchestrator_execution_id,''))='' or btrim(coalesce(p_consumer_execution_id,''))='' or btrim(coalesce(p_capability_code,''))='' then
    return jsonb_build_object('ready',false,'decision','BLOCK_INVALID_IDENTITY');
  end if;
  if coalesce(p_plan_digest,'') !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_dispatch_scope) is distinct from 'object' then
    return jsonb_build_object('ready',false,'decision','BLOCK_INVALID_DISPATCH_CONTRACT');
  end if;
  if p_actor_execution_id is distinct from p_orchestrator_execution_id then
    return jsonb_build_object('ready',false,'decision','BLOCK_ACTOR_NOT_ORCHESTRATOR');
  end if;
  select * into v_orch from public.lf_operation_execution where execution_id=p_orchestrator_execution_id;
  if not found or v_orch.status<>'IN_PROGRESS' then
    return jsonb_build_object('ready',false,'decision','BLOCK_ORCHESTRATOR_EXECUTION_NOT_ACTIVE');
  end if;
  select * into v_op from public.lf_operation_registry where operation_code=v_orch.operation_code;
  if not found or v_op.operation_family<>'ORCHESTRATION' or v_op.lifecycle_state_code<>'OP_OPERATIONAL' then
    return jsonb_build_object('ready',false,'decision','BLOCK_NOT_OPERATIONAL_ORCHESTRATOR','operation_code',v_orch.operation_code);
  end if;
  select * into v_cons from public.lf_operation_execution where execution_id=p_consumer_execution_id;
  if not found or v_cons.status<>'IN_PROGRESS' then
    return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_EXECUTION_NOT_ACTIVE');
  end if;
  if v_cons.manifest->>'orchestrator_execution_id' is distinct from p_orchestrator_execution_id
     or v_cons.manifest->>'plan_digest' is distinct from p_plan_digest
     or v_cons.manifest->>'capability_code' is distinct from p_capability_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_CROSSBIND_MISMATCH');
  end if;
  select * into v_cap from public.lf_capability_registry where capability_code=p_capability_code and status='ACTIVE';
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_OR_INACTIVE_CAPABILITY'); end if;
  if not v_cap.entry_guard_required then return jsonb_build_object('ready',false,'decision','BLOCK_ENTRY_GUARD_POLICY_DISABLED'); end if;

  v_payload:=jsonb_build_object(
    'schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1',
    'orchestrator_execution_id',p_orchestrator_execution_id,
    'orchestrator_operation_code',v_orch.operation_code,
    'orchestrator_operation_version',v_op.version,
    'consumer_execution_id',p_consumer_execution_id,
    'capability_code',p_capability_code,
    'plan_digest',p_plan_digest,
    'dispatch_scope',p_dispatch_scope,
    'guard_code',v_cap.entry_guard_code
  );
  v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');

  select * into v_existing from private.lf_orchestrator_dispatch_receipts_v1
   where orchestrator_execution_id=p_orchestrator_execution_id and consumer_execution_id=p_consumer_execution_id and capability_code=p_capability_code and plan_digest=p_plan_digest;
  if found then
    if v_existing.receipt_sha256<>v_sha then raise exception 'ORCHESTRATOR_DISPATCH_REPLAY_CONFLICT'; end if;
    return jsonb_build_object('ready',true,'decision','DISPATCH_RECEIPT_REPLAY','receipt_id',v_existing.receipt_id,'receipt_sha256',v_existing.receipt_sha256);
  end if;

  insert into private.lf_orchestrator_dispatch_receipts_v1(
    orchestrator_execution_id,consumer_execution_id,capability_code,plan_digest,dispatch_scope,
    orchestrator_operation_code,orchestrator_operation_version,guard_code,receipt_sha256,issued_by_execution_id
  ) values (
    p_orchestrator_execution_id,p_consumer_execution_id,p_capability_code,p_plan_digest,p_dispatch_scope,
    v_orch.operation_code,v_op.version,v_cap.entry_guard_code,v_sha,p_actor_execution_id
  ) returning receipt_id into v_id;
  return jsonb_build_object('ready',true,'decision','DISPATCH_RECEIPT_ISSUED','receipt_id',v_id,'receipt_sha256',v_sha,'guard_code',v_cap.entry_guard_code);
end; $$;

create or replace function public.fn_lf_capability_orchestrator_entry_guard_v1(
  p_consumer_execution_id text,
  p_capability_code text,
  p_plan_digest text,
  p_dispatch_receipt_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','public','private','extensions'
as $$
declare
  v_r private.lf_orchestrator_dispatch_receipts_v1%rowtype;
  v_orch public.lf_operation_execution%rowtype;
  v_cons public.lf_operation_execution%rowtype;
  v_cap public.lf_capability_registry%rowtype;
  v_op public.lf_operation_registry%rowtype;
  v_payload jsonb;
  v_sha text;
begin
  if p_dispatch_receipt_id is null then return jsonb_build_object('ready',false,'decision','BLOCK_MISSING_ORCHESTRATOR_DISPATCH_RECEIPT'); end if;
  select * into v_r from private.lf_orchestrator_dispatch_receipts_v1 where receipt_id=p_dispatch_receipt_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_ORCHESTRATOR_DISPATCH_RECEIPT'); end if;
  if v_r.consumer_execution_id<>p_consumer_execution_id or v_r.capability_code<>p_capability_code or v_r.plan_digest<>p_plan_digest then
    return jsonb_build_object('ready',false,'decision','BLOCK_DISPATCH_RECEIPT_CROSSBIND_MISMATCH');
  end if;
  select * into v_cap from public.lf_capability_registry where capability_code=p_capability_code and status='ACTIVE';
  if not found or not v_cap.entry_guard_required or v_cap.entry_guard_code<>v_r.guard_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_ENTRY_GUARD_POLICY_MISMATCH');
  end if;
  select * into v_orch from public.lf_operation_execution where execution_id=v_r.orchestrator_execution_id;
  select * into v_cons from public.lf_operation_execution where execution_id=p_consumer_execution_id;
  if v_orch.execution_id is null or v_orch.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_ORCHESTRATOR_EXECUTION_NOT_ACTIVE'); end if;
  if v_cons.execution_id is null or v_cons.status<>'IN_PROGRESS' then return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_EXECUTION_NOT_ACTIVE'); end if;
  select * into v_op from public.lf_operation_registry where operation_code=v_orch.operation_code;
  if not found or v_op.operation_family<>'ORCHESTRATION' or v_op.lifecycle_state_code<>'OP_OPERATIONAL' then
    return jsonb_build_object('ready',false,'decision','BLOCK_NOT_OPERATIONAL_ORCHESTRATOR');
  end if;
  if v_cons.manifest->>'orchestrator_execution_id' is distinct from v_r.orchestrator_execution_id
     or v_cons.manifest->>'plan_digest' is distinct from p_plan_digest
     or v_cons.manifest->>'capability_code' is distinct from p_capability_code then
    return jsonb_build_object('ready',false,'decision','BLOCK_CONSUMER_CROSSBIND_MISMATCH');
  end if;
  v_payload:=jsonb_build_object(
    'schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1',
    'orchestrator_execution_id',v_r.orchestrator_execution_id,
    'orchestrator_operation_code',v_r.orchestrator_operation_code,
    'orchestrator_operation_version',v_r.orchestrator_operation_version,
    'consumer_execution_id',v_r.consumer_execution_id,
    'capability_code',v_r.capability_code,
    'plan_digest',v_r.plan_digest,
    'dispatch_scope',v_r.dispatch_scope,
    'guard_code',v_r.guard_code
  );
  v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  if v_sha<>v_r.receipt_sha256 then return jsonb_build_object('ready',false,'decision','BLOCK_DISPATCH_RECEIPT_DIGEST_MISMATCH'); end if;
  return jsonb_build_object('ready',true,'decision','ORCHESTRATOR_ENTRY_ACCEPTED','orchestrator_execution_id',v_r.orchestrator_execution_id,'receipt_id',v_r.receipt_id,'guard_code',v_r.guard_code);
end; $$;

create or replace function private.fn_lf_capability_bind_core_v1(p_execution_id text,p_capability_code text,p_expected_manifest_sha256 text,p_actor_execution_id text)
returns jsonb language plpgsql set search_path to '' as $$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_binding public.lf_capability_binding%rowtype;
  v_step_count integer := 0;
  v_lease_active boolean := false;
  v_current_major integer;
  v_bound_major integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_execution_id || ':' || p_capability_code,0));
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_EXECUTION'); end if;
  select count(*)::int into v_step_count from public.lf_operation_execution_steps where execution_id=p_execution_id;
  v_lease_active := v_exec.lease_owner is not null and (v_exec.lease_expires_at is null or v_exec.lease_expires_at > now());
  select * into v_current from public.lf_capability_current where capability_code=p_capability_code;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_NO_CURRENT_CAPABILITY'); end if;
  if p_expected_manifest_sha256 is null or p_expected_manifest_sha256 <> v_current.manifest_sha256 then
    return jsonb_build_object('ready',false,'decision','BLOCK_CURRENTNESS_MISMATCH','expected',p_expected_manifest_sha256,'observed',v_current.manifest_sha256);
  end if;
  select * into v_binding from public.lf_capability_binding where execution_id=p_execution_id and capability_code=p_capability_code;
  if not found then
    if v_step_count<>0 then return jsonb_build_object('ready',false,'decision','LEGACY_EXECUTION_MIGRATION_GATE','step_count',v_step_count); end if;
    if v_lease_active then return jsonb_build_object('ready',false,'decision','BLOCK_ACTIVE_LEASE_UNBOUND'); end if;
    insert into public.lf_capability_binding(execution_id,capability_code,bound_version,bound_manifest_sha256,binding_mode,binding_state,step_count_at_bind,rebind_count,bound_by_execution_id,last_checked_by_execution_id)
    values(p_execution_id,p_capability_code,v_current.version,v_current.manifest_sha256,'INITIAL','BOUND',0,0,p_actor_execution_id,p_actor_execution_id);
    return jsonb_build_object('ready',true,'decision','BOUND_CURRENT','version',v_current.version,'manifest_sha256',v_current.manifest_sha256);
  end if;
  if v_binding.bound_version=v_current.version and v_binding.bound_manifest_sha256=v_current.manifest_sha256 then
    update public.lf_capability_binding set last_checked_at=now(),last_checked_by_execution_id=p_actor_execution_id where execution_id=p_execution_id and capability_code=p_capability_code;
    return jsonb_build_object('ready',true,'decision','READY_CURRENT','version',v_current.version,'manifest_sha256',v_current.manifest_sha256);
  end if;
  if v_step_count=0 and not v_lease_active then
    update public.lf_capability_binding set bound_version=v_current.version,bound_manifest_sha256=v_current.manifest_sha256,binding_mode='REBIND_SAFE',binding_state='BOUND',step_count_at_bind=0,rebind_count=rebind_count+1,bound_at=now(),last_checked_at=now(),bound_by_execution_id=p_actor_execution_id,last_checked_by_execution_id=p_actor_execution_id where execution_id=p_execution_id and capability_code=p_capability_code;
    return jsonb_build_object('ready',true,'decision','REBOUND_CURRENT','version',v_current.version,'manifest_sha256',v_current.manifest_sha256);
  end if;
  if v_lease_active then return jsonb_build_object('ready',false,'decision','BLOCK_ACTIVE_LEASE_STALE_BINDING'); end if;
  select version_major into v_current_major from public.lf_capability_version_registry where capability_code=p_capability_code and version=v_current.version;
  select version_major into v_bound_major from public.lf_capability_version_registry where capability_code=p_capability_code and version=v_binding.bound_version;
  if v_current_major=v_bound_major then
    update public.lf_capability_binding set binding_mode='PINNED',binding_state='PINNED',last_checked_at=now(),last_checked_by_execution_id=p_actor_execution_id where execution_id=p_execution_id and capability_code=p_capability_code;
    return jsonb_build_object('ready',true,'decision','PIN_BOUND_VERSION','bound_version',v_binding.bound_version,'current_version',v_current.version);
  end if;
  return jsonb_build_object('ready',false,'decision','MIGRATION_REQUIRED','bound_version',v_binding.bound_version,'current_version',v_current.version,'step_count',v_step_count);
end; $$;

create or replace function public.fn_lf_capability_bind_current_v1(p_execution_id text,p_capability_code text,p_expected_manifest_sha256 text,p_actor_execution_id text)
returns jsonb language plpgsql set search_path to '' as $$
declare v_required boolean; v_existing boolean;
begin
  select entry_guard_required into v_required from public.lf_capability_registry where capability_code=p_capability_code;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_CAPABILITY'); end if;
  select exists(select 1 from public.lf_capability_binding where execution_id=p_execution_id and capability_code=p_capability_code) into v_existing;
  if coalesce(v_required,false) and not v_existing then
    return jsonb_build_object('ready',false,'decision','BLOCK_ORCHESTRATOR_ENTRY_GUARD_REQUIRED','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1');
  end if;
  return private.fn_lf_capability_bind_core_v1(p_execution_id,p_capability_code,p_expected_manifest_sha256,p_actor_execution_id);
end; $$;

create or replace function public.fn_lf_capability_bind_from_orchestrator_v1(
  p_execution_id text,
  p_capability_code text,
  p_expected_manifest_sha256 text,
  p_plan_digest text,
  p_dispatch_receipt_id uuid,
  p_actor_execution_id text
) returns jsonb language plpgsql set search_path to '' as $$
declare v_guard jsonb; v_bind jsonb;
begin
  v_guard:=public.fn_lf_capability_orchestrator_entry_guard_v1(p_execution_id,p_capability_code,p_plan_digest,p_dispatch_receipt_id);
  if coalesce((v_guard->>'ready')::boolean,false) is not true then return v_guard; end if;
  v_bind:=private.fn_lf_capability_bind_core_v1(p_execution_id,p_capability_code,p_expected_manifest_sha256,p_actor_execution_id);
  return jsonb_build_object('ready',coalesce((v_bind->>'ready')::boolean,false),'entry_guard',v_guard,'binding',v_bind);
end; $$;

create or replace view public.v_lf_capability_entry_guard_v1 as
select r.capability_code,r.capability_name,r.capability_kind,r.owner_scope,r.status,
       r.entry_guard_required,r.entry_guard_code,
       c.version as current_version,c.manifest_sha256 as current_manifest_sha256,
       case when r.status='ACTIVE' and r.entry_guard_required and btrim(r.entry_guard_code)<>'' then 'GUARDED' else 'NOT_GUARDED' end as entry_guard_state
from public.lf_capability_registry r
left join public.lf_capability_current c on c.capability_code=r.capability_code;

revoke all on table private.lf_orchestrator_dispatch_receipts_v1 from public,anon,authenticated;
revoke all on function public.fn_lf_orchestrator_dispatch_receipt_v1(text,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.fn_lf_capability_orchestrator_entry_guard_v1(text,text,text,uuid) from public,anon,authenticated;
revoke all on function public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.fn_lf_orchestrator_dispatch_receipt_v1(text,text,text,text,jsonb,text) to service_role;
grant execute on function public.fn_lf_capability_orchestrator_entry_guard_v1(text,text,text,uuid) to service_role;
grant execute on function public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text) to service_role;
