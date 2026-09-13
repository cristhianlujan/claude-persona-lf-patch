-- LF Capability Registry + Destination Resolution LF v2
-- Candidate source for governed activation. Tested with BEGIN/ROLLBACK before activation.
-- No runtime, production, scheduler, Golden or main-branch authorization is implied.

create table public.lf_capability_registry (
  capability_code text primary key,
  capability_name text not null,
  capability_kind text not null default 'TRANSVERSAL',
  owner_scope text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','DEPRECATED','RETIRED')),
  description text not null,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  updated_at timestamptz not null default now(),
  updated_by_execution_id text
);

create table public.lf_capability_version_registry (
  capability_code text not null references public.lf_capability_registry(capability_code) on delete restrict,
  version text not null,
  version_major integer not null check (version_major >= 0),
  version_minor integer not null check (version_minor >= 0),
  version_patch integer not null check (version_patch >= 0),
  release_state text not null check (release_state in ('LEGACY_IMPORTED','RELEASED','RETIRED')),
  supersedes_version text,
  manifest jsonb not null,
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  source_ref text not null,
  docs_ref text not null,
  validator_ref text not null,
  created_at timestamptz not null default now(),
  created_by_execution_id text not null,
  primary key (capability_code, version),
  unique (capability_code, manifest_sha256),
  check (version = version_major::text || '.' || version_minor::text || '.' || version_patch::text),
  check (jsonb_typeof(manifest) = 'object'),
  check (manifest ?& array['schema_version','capability_code','version','contract','delivery','installation','dependencies','compatibility','migration','rollback','usage','currentness'])
);

alter table public.lf_capability_version_registry
  add constraint lf_capability_version_supersedes_fk
  foreign key (capability_code, supersedes_version)
  references public.lf_capability_version_registry(capability_code, version)
  on delete restrict;

create table public.lf_capability_current (
  capability_code text primary key references public.lf_capability_registry(capability_code) on delete restrict,
  version text not null,
  manifest_sha256 text not null,
  previous_version text,
  promoted_at timestamptz not null default now(),
  promoted_by_execution_id text not null,
  promotion_reason text not null,
  foreign key (capability_code, version) references public.lf_capability_version_registry(capability_code, version) on delete restrict,
  foreign key (capability_code, previous_version) references public.lf_capability_version_registry(capability_code, version) on delete restrict
);

create table public.lf_capability_binding (
  execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  capability_code text not null references public.lf_capability_registry(capability_code) on delete restrict,
  bound_version text not null,
  bound_manifest_sha256 text not null,
  binding_mode text not null check (binding_mode in ('INITIAL','REBIND_SAFE','PINNED')),
  binding_state text not null default 'BOUND' check (binding_state in ('BOUND','STALE','PINNED')),
  step_count_at_bind integer not null default 0 check (step_count_at_bind >= 0),
  rebind_count integer not null default 0 check (rebind_count >= 0),
  bound_at timestamptz not null default now(),
  last_checked_at timestamptz not null default now(),
  bound_by_execution_id text not null,
  last_checked_by_execution_id text not null,
  primary key (execution_id, capability_code),
  foreign key (capability_code, bound_version) references public.lf_capability_version_registry(capability_code, version) on delete restrict
);

create or replace function public.fn_lf_capability_version_prepare_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.manifest->>'capability_code' <> new.capability_code or new.manifest->>'version' <> new.version then
    raise exception 'CAPABILITY_MANIFEST_IDENTITY_MISMATCH';
  end if;
  new.manifest_sha256 := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(new.manifest::text,'UTF8'),'sha256'),'hex');
  return new;
end;
$$;

create trigger trg_lf_capability_version_prepare_v1
before insert on public.lf_capability_version_registry
for each row execute function public.fn_lf_capability_version_prepare_v1();

create or replace function public.fn_lf_capability_version_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'CAPABILITY_VERSION_IMMUTABLE: %.%', old.capability_code, old.version;
end;
$$;

create trigger trg_lf_capability_version_immutable_v1
before update or delete on public.lf_capability_version_registry
for each row execute function public.fn_lf_capability_version_immutable_v1();

create or replace function public.fn_lf_capability_promote_v1(
  p_capability_code text,
  p_version text,
  p_expected_current_manifest_sha256 text,
  p_actor_execution_id text,
  p_reason text
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_version public.lf_capability_version_registry%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_had_current boolean := false;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_capability_code, 0));
  select * into v_version from public.lf_capability_version_registry where capability_code=p_capability_code and version=p_version;
  if not found then
    return jsonb_build_object('ready',false,'decision','BLOCK_VERSION_NOT_FOUND','capability_code',p_capability_code,'version',p_version);
  end if;
  select * into v_current from public.lf_capability_current where capability_code=p_capability_code;
  v_had_current := found;
  if v_had_current and p_expected_current_manifest_sha256 is not null and v_current.manifest_sha256 <> p_expected_current_manifest_sha256 then
    return jsonb_build_object('ready',false,'decision','BLOCK_CURRENTNESS_MISMATCH','expected',p_expected_current_manifest_sha256,'observed',v_current.manifest_sha256);
  end if;
  insert into public.lf_capability_current as c(capability_code,version,manifest_sha256,previous_version,promoted_at,promoted_by_execution_id,promotion_reason)
  values (p_capability_code,p_version,v_version.manifest_sha256,case when v_had_current then v_current.version else null end,now(),p_actor_execution_id,p_reason)
  on conflict (capability_code) do update set
    previous_version = case when c.version = excluded.version then c.previous_version else c.version end,
    version = excluded.version,
    manifest_sha256 = excluded.manifest_sha256,
    promoted_at = excluded.promoted_at,
    promoted_by_execution_id = excluded.promoted_by_execution_id,
    promotion_reason = excluded.promotion_reason;
  return jsonb_build_object('ready',true,'decision',case when v_had_current and v_current.version=p_version then 'CURRENT_UNCHANGED' else 'PROMOTED_CURRENT' end,'capability_code',p_capability_code,'version',p_version,'manifest_sha256',v_version.manifest_sha256,'previous_version',case when v_had_current then v_current.version else null end);
end;
$$;

create or replace function public.fn_lf_capability_preflight_v1(
  p_execution_id text,
  p_capability_code text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_version public.lf_capability_version_registry%rowtype;
  v_binding public.lf_capability_binding%rowtype;
  v_step_count integer := 0;
  v_lease_active boolean := false;
  v_bound_major integer;
  v_decision text;
  v_ready boolean := false;
  v_package_action text;
begin
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_EXECUTION','execution_id',p_execution_id); end if;
  select count(*)::int into v_step_count from public.lf_operation_execution_steps where execution_id=p_execution_id;
  v_lease_active := v_exec.lease_owner is not null and (v_exec.lease_expires_at is null or v_exec.lease_expires_at > now());
  select * into v_current from public.lf_capability_current where capability_code=p_capability_code;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_NO_CURRENT_CAPABILITY','capability_code',p_capability_code); end if;
  select * into v_version from public.lf_capability_version_registry where capability_code=p_capability_code and version=v_current.version;
  if not found or v_version.manifest_sha256 <> v_current.manifest_sha256 then return jsonb_build_object('ready',false,'decision','BLOCK_CURRENT_POINTER_INVALID','capability_code',p_capability_code); end if;
  select * into v_binding from public.lf_capability_binding where execution_id=p_execution_id and capability_code=p_capability_code;
  if not found then
    if v_step_count=0 and not v_lease_active then v_decision:='BIND_CURRENT_SAFE'; v_ready:=true;
    elsif v_step_count=0 and v_lease_active then v_decision:='BLOCK_ACTIVE_LEASE_UNBOUND';
    else v_decision:='LEGACY_EXECUTION_MIGRATION_GATE'; end if;
  elsif v_binding.bound_manifest_sha256=v_current.manifest_sha256 and v_binding.bound_version=v_current.version then
    v_decision:='READY_CURRENT'; v_ready:=true;
  else
    select version_major into v_bound_major from public.lf_capability_version_registry where capability_code=p_capability_code and version=v_binding.bound_version;
    if v_step_count=0 and not v_lease_active then v_decision:='REBIND_CURRENT_SAFE'; v_ready:=true;
    elsif v_step_count=0 and v_lease_active then v_decision:='BLOCK_ACTIVE_LEASE_STALE_BINDING';
    elsif v_bound_major = v_version.version_major then v_decision:='PIN_BOUND_VERSION'; v_ready:=true;
    else v_decision:='MIGRATION_REQUIRED'; end if;
  end if;
  v_package_action := case when coalesce(jsonb_array_length(v_version.manifest #> '{dependencies,packages}'),0)=0 then 'NONE' else 'VERIFY_DECLARED_PACKAGES' end;
  return jsonb_build_object(
    'ready',v_ready,'decision',v_decision,'execution_id',p_execution_id,'capability_code',p_capability_code,
    'current_version',v_current.version,'current_manifest_sha256',v_current.manifest_sha256,
    'bound_version',v_binding.bound_version,'bound_manifest_sha256',v_binding.bound_manifest_sha256,
    'step_count',v_step_count,'lease_active',v_lease_active,'package_action',v_package_action,
    'installation',v_version.manifest->'installation','dependencies',v_version.manifest->'dependencies',
    'migration',v_version.manifest->'migration','usage',v_version.manifest->'usage','currentness',v_version.manifest->'currentness',
    'docs_ref',v_version.docs_ref,'validator_ref',v_version.validator_ref
  );
end;
$$;

create or replace function public.fn_lf_capability_bind_current_v1(
  p_execution_id text,
  p_capability_code text,
  p_expected_manifest_sha256 text,
  p_actor_execution_id text
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
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
end;
$$;

create or replace function public.fn_lf_resolve_artifact_destination_v2(
  p_execution_id text,
  p_requested_destination_code text default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_version public.lf_capability_version_registry%rowtype;
  v_dest public.lf_artifact_destination_registry%rowtype;
  v_count integer := 0;
  v_mode text;
begin
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_EXECUTION'); end if;
  select * into v_current from public.lf_capability_current where capability_code='DESTINATION_RESOLUTION_LF';
  if not found then return jsonb_build_object('ready',false,'decision','BLOCK_DESTINATION_CAPABILITY_NOT_CURRENT'); end if;
  select * into v_version from public.lf_capability_version_registry where capability_code='DESTINATION_RESOLUTION_LF' and version=v_current.version;
  if not found or v_version.manifest_sha256<>v_current.manifest_sha256 then return jsonb_build_object('ready',false,'decision','BLOCK_DESTINATION_CAPABILITY_POINTER_INVALID'); end if;
  if p_requested_destination_code is not null then
    select * into v_dest from public.lf_artifact_destination_registry
    where destination_code=p_requested_destination_code and status in ('ACTIVE','BINDING_ONLY')
      and operation_code=v_exec.operation_code and artifact_type=v_exec.target_type;
    if not found then return jsonb_build_object('ready',false,'decision','BLOCK_EXPLICIT_DESTINATION_INVALID','requested_destination_code',p_requested_destination_code); end if;
    v_mode:='EXPLICIT_BOUND_CODE';
  else
    select count(*)::int into v_count from public.lf_artifact_destination_registry
    where status='ACTIVE' and operation_code=v_exec.operation_code and artifact_type=v_exec.target_type;
    if v_count=0 then return jsonb_build_object('ready',false,'decision','BLOCK_NO_DEFAULT_DESTINATION'); end if;
    if v_count>1 then return jsonb_build_object('ready',false,'decision','BLOCK_AMBIGUOUS_DEFAULT_DESTINATION','active_count',v_count); end if;
    select * into v_dest from public.lf_artifact_destination_registry
    where status='ACTIVE' and operation_code=v_exec.operation_code and artifact_type=v_exec.target_type;
    v_mode:='UNIQUE_ACTIVE_DEFAULT';
  end if;
  if v_exec.target_repo is not null and v_exec.target_repo<>v_dest.repo then
    return jsonb_build_object('ready',false,'decision','BLOCK_TARGET_REPO_MISMATCH','execution_repo',v_exec.target_repo,'destination_repo',v_dest.repo);
  end if;
  if v_exec.target_path is not null and v_exec.target_path not like v_dest.base_folder || '/%' then
    return jsonb_build_object('ready',false,'decision','BLOCK_TARGET_PATH_OUTSIDE_DESTINATION','target_path',v_exec.target_path,'base_folder',v_dest.base_folder);
  end if;
  return jsonb_build_object(
    'ready',true,'decision','READY_TO_RESOLVE','selection_mode',v_mode,
    'capability_code','DESTINATION_RESOLUTION_LF','capability_version',v_current.version,'capability_manifest_sha256',v_current.manifest_sha256,
    'binding_required_before_material_write',true,
    'destination',jsonb_build_object('destination_code',v_dest.destination_code,'repo',v_dest.repo,'branch',v_dest.branch,'base_folder',v_dest.base_folder,'status',v_dest.status,'package_mode',v_dest.package_mode,'naming_rule',v_dest.naming_rule,'filename_suffix',v_dest.filename_suffix)
  );
end;
$$;

create view public.v_lf_capability_versions with (security_invoker=true) as
select v.capability_code,v.version,v.version_major,v.version_minor,v.version_patch,v.release_state,v.supersedes_version,v.manifest_sha256,
       case when c.version=v.version and c.manifest_sha256=v.manifest_sha256 then 'CURRENT'
            when v.release_state='RETIRED' then 'RETIRED'
            else 'SUPERSEDED' end as effective_status,
       v.source_ref,v.docs_ref,v.validator_ref,v.created_at,v.created_by_execution_id
from public.lf_capability_version_registry v
left join public.lf_capability_current c on c.capability_code=v.capability_code;

alter table public.lf_capability_registry enable row level security;
alter table public.lf_capability_version_registry enable row level security;
alter table public.lf_capability_current enable row level security;
alter table public.lf_capability_binding enable row level security;

create policy lf_capability_registry_authenticated_read_v1 on public.lf_capability_registry for select to authenticated using (true);
create policy lf_capability_version_authenticated_read_v1 on public.lf_capability_version_registry for select to authenticated using (true);
create policy lf_capability_current_authenticated_read_v1 on public.lf_capability_current for select to authenticated using (true);
create policy lf_capability_binding_authenticated_read_v1 on public.lf_capability_binding for select to authenticated using (true);

revoke all on public.lf_capability_registry,public.lf_capability_version_registry,public.lf_capability_current,public.lf_capability_binding from anon,authenticated;
grant select on public.lf_capability_registry,public.lf_capability_version_registry,public.lf_capability_current,public.lf_capability_binding to authenticated;
grant all on public.lf_capability_registry,public.lf_capability_version_registry,public.lf_capability_current,public.lf_capability_binding to service_role;
grant select on public.v_lf_capability_versions to authenticated,service_role;
revoke all on function public.fn_lf_capability_version_prepare_v1() from public,anon,authenticated;
revoke all on function public.fn_lf_capability_version_immutable_v1() from public,anon,authenticated;
revoke all on function public.fn_lf_capability_promote_v1(text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.fn_lf_capability_bind_current_v1(text,text,text,text) from public,anon,authenticated;
grant execute on function public.fn_lf_capability_promote_v1(text,text,text,text,text) to service_role;
grant execute on function public.fn_lf_capability_bind_current_v1(text,text,text,text) to service_role;
grant execute on function public.fn_lf_capability_preflight_v1(text,text) to authenticated,service_role;
grant execute on function public.fn_lf_resolve_artifact_destination_v2(text,text) to authenticated,service_role;

insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id)
values('DESTINATION_RESOLUTION_LF','LF Destination Resolution','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Single versioned transversal capability for deterministic artifact destination resolution.','EXEC-CAPABILITY-REGISTRY-V1-20260913-001');

insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
values
('DESTINATION_RESOLUTION_LF','1.0.0',1,0,0,'LEGACY_IMPORTED',null,$${"schema_version":"LF_CAPABILITY_MANIFEST_V1","capability_code":"DESTINATION_RESOLUTION_LF","version":"1.0.0","contract":{"input":"OPERATION_EXECUTION_V1","output":"ARTIFACT_DESTINATION_V1"},"delivery":{"mode":"CENTRAL_DATABASE_LEGACY"},"installation":{"required":false,"reinstall_required":false},"dependencies":{"capabilities":[],"packages":[]},"compatibility":{"to":["2.0.0"],"auto_rebind_when_zero_steps":true,"mid_execution_rebind":false},"migration":{"id":"DESTINATION_RESOLUTION_V1_TO_V2","zero_step":"SAFE_REBIND","material_started":"PIN_OR_RESTART"},"rollback":{"supported":true,"target":null},"usage":{"invoke":"LEGACY_DIRECT_DESTINATION_REGISTRY","manual":"historical"},"currentness":{"required_before_material_write":false}}$$::jsonb,repeat('0',64),'supabase://public/lf_artifact_destination_registry/DEST_CREACION_ESTRATEGIA_LF_CANARY@2026-09-07T04:05:04.685436+00:00','github://cristhianlujan/claude-persona-lf-patch@80d1cab80eab67921237acbf61529c480c530e91/sandbox/lf_contract_gate_test/strategy_update_exclusive_lane_20260913/CAPABILITY_STANDARD_V1.md','supabase://legacy/direct-destination-registry','EXEC-CAPABILITY-REGISTRY-V1-20260913-001'),
('DESTINATION_RESOLUTION_LF','2.0.0',2,0,0,'RELEASED','1.0.0',$${"schema_version":"LF_CAPABILITY_MANIFEST_V1","capability_code":"DESTINATION_RESOLUTION_LF","version":"2.0.0","contract":{"input":"OPERATION_EXECUTION_V1_PLUS_OPTIONAL_DESTINATION_CODE","output":"ARTIFACT_DESTINATION_V2"},"delivery":{"mode":"CENTRAL_DATABASE_CAPABILITY"},"installation":{"required":false,"reinstall_required":false,"package_update_mode":"MANIFEST_DECLARED"},"dependencies":{"capabilities":[],"packages":[]},"compatibility":{"from":["1.x"],"auto_rebind_when_zero_steps":true,"mid_execution_rebind":false,"major_change_requires_migration":true},"migration":{"id":"DESTINATION_RESOLUTION_V1_TO_V2","zero_step":"SAFE_REBIND","material_started":"PIN_OR_RESTART","execution_row_mutation":false},"rollback":{"supported":true,"target":"1.0.0","pointer_only":true},"usage":{"preflight":"public.fn_lf_capability_preflight_v1","bind":"public.fn_lf_capability_bind_current_v1","invoke":"public.fn_lf_resolve_artifact_destination_v2"},"currentness":{"required_before_material_write":true,"compare":"manifest_sha256","stale_action":"BLOCK_OR_REBIND_PREWRITE"},"selection":{"explicit_destination_statuses":["ACTIVE","BINDING_ONLY"],"default_destination_statuses":["ACTIVE"],"multiple_default":"BLOCK"}}$$::jsonb,repeat('0',64),'github://cristhianlujan/claude-persona-lf-patch@80d1cab80eab67921237acbf61529c480c530e91/sandbox/lf_contract_gate_test/strategy_update_exclusive_lane_20260913/DESTINATION_RESOLUTION_LF_v2.manifest.yaml','github://cristhianlujan/claude-persona-lf-patch@80d1cab80eab67921237acbf61529c480c530e91/sandbox/lf_contract_gate_test/strategy_update_exclusive_lane_20260913/CAPABILITY_STANDARD_V1.md','supabase://public/fn_lf_resolve_artifact_destination_v2','EXEC-CAPABILITY-REGISTRY-V1-20260913-001');

select public.fn_lf_capability_promote_v1('DESTINATION_RESOLUTION_LF','2.0.0',null,'EXEC-CAPABILITY-REGISTRY-V1-20260913-001','Bootstrap current v2 after legacy import');

insert into public.lf_artifact_destination_registry(destination_code,operation_code,artifact_type,domain_key,repo,branch,base_folder,filename_suffix,naming_rule,status,priority,notes,package_mode,package_files,required_files,optional_files,pack_selection_policy,created_by_execution_id,updated_by_execution_id)
values('DEST_STRATEGY_UPDATE_E2E_EXCLUSIVE_20260913','CREACION_ESTRATEGIA_LF','STRATEGY','CANARY','cristhianlujan/claude-persona-lf-patch','lf/strategy-update-gpt-exclusive-20260913','strategies','.yaml','SLUG_UPPER_UNDERSCORE','BINDING_ONLY',5,'Explicit-only destination for Strategy Update E2E canary; never selected by legacy/default lookup. Legacy view filters ACTIVE only.','SINGLE_FILE','[]'::jsonb,'[]'::jsonb,'[]'::jsonb,'STATIC_SINGLE_FILE','EXEC-CAPABILITY-REGISTRY-V1-20260913-001','EXEC-CAPABILITY-REGISTRY-V1-20260913-001');
