-- DB_WRITE_TRANSPORT 2.2.0 registry promotion.
-- Source code and docs are the exact code-PR head; the Merge Train owns execution
-- reservation, recording, application, ledger readback, and closure.
begin;

do $pre$
declare
  v_execution_id text;
begin
  if (select version from public.lf_capability_current
      where capability_code = 'DB_WRITE_TRANSPORT') <> '2.1.0' then
    raise exception 'DB_WRITE_TRANSPORT_V22_UNEXPECTED_CURRENT';
  end if;
  if exists (select 1 from public.lf_capability_version_registry
             where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.2.0') then
    raise exception 'DB_WRITE_TRANSPORT_V22_ALREADY_REGISTERED';
  end if;

  select execution_id into v_execution_id
  from public.lf_operation_execution
  where operation_code = 'ACTUALIZACION_DB_LF'
    and target_type = 'MIGRATION'
    and target_repo = 'cristhianlujan/claude-persona-lf-patch'
    and target_code like '%_lf_db_write_transport_v2_2_0'
    and status = 'IN_PROGRESS'
  order by started_at desc
  limit 1;

  if v_execution_id is null then
    raise exception 'DB_WRITE_TRANSPORT_V22_TRAIN_EXECUTION_MISSING';
  end if;
end $pre$;

with base as (
  select manifest
  from public.lf_capability_version_registry
  where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0'
), v1 as (
  select jsonb_set(manifest, '{version}', to_jsonb('2.2.0'::text), true) as manifest from base
), v2 as (
  select jsonb_set(manifest, '{migration,fallback_executor}', 'null'::jsonb, true) as manifest from v1
), v3 as (
  select jsonb_set(manifest, '{migration,train_internal_only}', 'true'::jsonb, true) as manifest from v2
), v4 as (
  select jsonb_set(manifest, '{agent_route,execution_request}',
    to_jsonb('NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION'::text), true) as manifest from v3
), v5 as (
  select jsonb_set(manifest, '{agent_route,router_passage}',
    '["ROUTER_OPERATION_FROM_LF_ROUTER_RESOLVE_V1","TRAIN_RESERVED_ACTUALIZACION_DB_LF_EXECUTION"]'::jsonb,
    true) as manifest from v4
), v6 as (
  select jsonb_set(manifest, '{agent_route,steps}',
    '["ONE_MIGRATION_FILE","ONE_MIGRATION_PER_PR","NAME_PER_POL_LF_MIGRATION_NAMING","VERSION_IS_ASSIGNED_OR_REASSIGNED_BY_TRAIN","TRAIN_RESERVES_REGISTERS_CLOSES_ACTUALIZACION_DB_LF","APPLIED_MIGRATION_IMMUTABILITY_CHECK","OPEN_PR_NOT_DRAFT","REQUIRED_CHECKS_GREEN_ON_EXACT_HEAD","ONE_TRAIN_AT_A_TIME","LABEL_READY_TO_MERGE","MERGE_TRAIN_APPLIES_AND_MERGES","LEDGER_AND_MAIN_READBACK"]'::jsonb,
    true) as manifest from v5
), v7 as (
  select jsonb_set(manifest, '{rollback,previous_version}', to_jsonb('2.1.0'::text), true) as manifest from v6
), v8 as (
  select jsonb_set(manifest, '{agent_route,applied_migration_rule}',
    to_jsonb('IMMUTABLE_IF_PRESENT_IN_MAIN_OR_LEDGER;NEW_FAIL_FORWARD_MIGRATION_VIA_MERGE_TRAIN'::text),
    true) as manifest from v7
), m as (
  select jsonb_set(manifest, '{currentness,authority_ref}',
    to_jsonb('github://cristhianlujan/claude-persona-lf-patch@7d35e3e314fa4de36cd814ac2d3e0dccddebbba3'::text),
    true) as manifest from v8
)
insert into public.lf_capability_version_registry (
  capability_code, version, version_major, version_minor, version_patch,
  release_state, supersedes_version, manifest, manifest_sha256,
  source_ref, docs_ref, validator_ref, created_by_execution_id
)
select
  'DB_WRITE_TRANSPORT', '2.2.0', 2, 2, 0, 'RELEASED', '2.1.0', manifest, repeat('0', 64),
  'github://cristhianlujan/claude-persona-lf-patch@7d35e3e314fa4de36cd814ac2d3e0dccddebbba3/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
  'github://cristhianlujan/claude-persona-lf-patch@7d35e3e314fa4de36cd814ac2d3e0dccddebbba3/sandbox/lf_contract_gate_test/db_write_transport/README.md',
  'github://cristhianlujan/claude-persona-lf-patch@7d35e3e314fa4de36cd814ac2d3e0dccddebbba3/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py#self_test',
  (select execution_id from public.lf_operation_execution
   where operation_code = 'ACTUALIZACION_DB_LF'
     and target_type = 'MIGRATION'
     and target_repo = 'cristhianlujan/claude-persona-lf-patch'
     and target_code like '%_lf_db_write_transport_v2_2_0'
     and status = 'IN_PROGRESS'
   order by started_at desc limit 1)
from m;

update public.lf_capability_current
set version = '2.2.0',
    manifest_sha256 = (select manifest_sha256 from public.lf_capability_version_registry
                       where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.2.0'),
    previous_version = '2.1.0',
    promoted_at = clock_timestamp(),
    promoted_by_execution_id = (select execution_id from public.lf_operation_execution
      where operation_code = 'ACTUALIZACION_DB_LF'
        and target_type = 'MIGRATION'
        and target_repo = 'cristhianlujan/claude-persona-lf-patch'
        and target_code like '%_lf_db_write_transport_v2_2_0'
        and status = 'IN_PROGRESS'
      order by started_at desc limit 1),
    promotion_reason = 'Train promotion of DB_WRITE_TRANSPORT 2.2.0: Train-managed execution, no manual fallback, applied migrations immutable'
where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0';

do $post$
begin
  if (select count(*) from public.v_lf_capability_entry_guard_v1
      where capability_code = 'DB_WRITE_TRANSPORT'
        and current_version = '2.2.0' and entry_guard_state = 'GUARDED') <> 1 then
    raise exception 'DB_WRITE_TRANSPORT_V22_NOT_CURRENT';
  end if;
  if (select manifest->'agent_route'->>'execution_request'
      from public.lf_capability_version_registry
      where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.2.0')
       <> 'NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION' then
    raise exception 'DB_WRITE_TRANSPORT_V22_EXECUTION_CONTRACT_INVALID';
  end if;
  if (select manifest->'migration'->'fallback_executor'
      from public.lf_capability_version_registry
      where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.2.0')
       <> 'null'::jsonb then
    raise exception 'DB_WRITE_TRANSPORT_V22_MANUAL_FALLBACK_PRESENT';
  end if;
end $post$;

commit;
