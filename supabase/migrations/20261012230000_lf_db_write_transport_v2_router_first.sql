-- DB_WRITE_TRANSPORT v2.0.0: Router first, Merge Train only for agents.
-- Registers the v2 manifest (code merged in PR #2334, main cbcdd8dfd9053d0ef9035f095744b3e6e253ad87),
-- promotes it as current and replaces the v1 registry description that pointed
-- agents to direct SUPABASE_MCP writes. v1.0.0 stays immutable as history.
-- Requires the canonical execution EXEC-DB-TRANSPORT-V2-ROUTER-20261012-001
-- (operation ACTUALIZACION_DB_LF, IN_PROGRESS) to exist before apply.
begin;

do $pre$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id = 'EXEC-DB-TRANSPORT-V2-ROUTER-20261012-001'
      and operation_code = 'ACTUALIZACION_DB_LF'
      and status = 'IN_PROGRESS'
  ) then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_EXECUTION_MISSING';
  end if;
  if (select version from public.lf_capability_current where capability_code = 'DB_WRITE_TRANSPORT') <> '1.0.0' then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_UNEXPECTED_CURRENT';
  end if;
  if exists (select 1 from public.lf_capability_version_registry
             where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0') then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_ALREADY_EXISTS';
  end if;
  if not exists (select 1 from public.v_lf_operation_policy_snapshot
                 where operation_code = 'ACTUALIZACION_DB_LF' and policy_code = 'POL-LF-MIGRATION-NAMING') then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_NAMING_POLICY_MISSING';
  end if;
end $pre$;

insert into public.lf_capability_version_registry (
  capability_code, version, version_major, version_minor, version_patch,
  release_state, supersedes_version, manifest, manifest_sha256,
  source_ref, docs_ref, validator_ref, created_by_execution_id
) values (
  'DB_WRITE_TRANSPORT', '2.0.0', 2, 0, 0, 'RELEASED', '1.0.0',
  jsonb_build_object(
    'schema_version', 'LF_CAPABILITY_MANIFEST_V1',
    'capability_code', 'DB_WRITE_TRANSPORT',
    'version', '2.0.0',
    'contract', jsonb_build_object(
      'input', 'LF_DB_WRITE_TARGET_V1',
      'output', 'LF_DB_WRITE_AGENT_ROUTE_V2',
      'authority', 'SELECTOR_ONLY_NO_PERMISSION_GRANT'),
    'delivery', jsonb_build_object(
      'mode', 'VERSIONED_REPOSITORY_CAPABILITY',
      'selector', 'sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
      'consumer_operation', 'ACTUALIZACION_DB_LF'),
    'agent_route', jsonb_build_object(
      'entry', 'ROUTER_FIRST',
      'router_authority', 'ACT-0001',
      'router_operation', 'ACTUALIZACION_DB_LF',
      'without_router_execution', 'REDIRECT_TO_ROUTER',
      'with_router_execution', 'MIGRATION_VIA_MERGE_TRAIN',
      'executor', 'LF_MIGRATION_MERGE_TRAIN',
      'target_types', jsonb_build_array('MIGRATION','DB','FUNCTION','TRIGGER','CAPABILITY'),
      'steps', jsonb_build_array('ONE_MIGRATION_FILE','NAME_PER_POL_LF_MIGRATION_NAMING','OPEN_PR',
                                 'REQUIRED_CHECKS_GREEN','LABEL_READY_TO_MERGE','MERGE_TRAIN_APPLIES_AND_MERGES',
                                 'LEDGER_AND_MAIN_READBACK'),
      'policies', jsonb_build_array('POL-LF-MIGRATION-NAMING'),
      'forbidden', jsonb_build_array('SUPABASE_MCP_APPLY_MIGRATION','SUPABASE_MCP_EXECUTE_SQL_DDL_OR_MIGRATION_DML',
                                     'SUPABASE_CLI_DB_PUSH_BY_AGENT','SUPABASE_SQL_EDITOR_SCHEMA_CHANGE',
                                     'PSQL_DIRECT_SCHEMA_CHANGE','MANUAL_SCHEMA_MIGRATIONS_LEDGER_DML',
                                     'DB_WRITE_WITHOUT_ROUTER_EXECUTION','UNCLASSIFIED_MIGRATION_NAME')),
    'installation', jsonb_build_object('required', false, 'reinstall_required', false,
                                       'package_update_mode', 'REPOSITORY_BOUND'),
    'dependencies', jsonb_build_object(
      'packages', jsonb_build_array('python>=3.11'),
      'governance', jsonb_build_array('ACT-0001','MIGRATION_SOURCE_PARITY','CI-MIGRATION-SOURCE-PARITY-001',
                                      'POL-LF-MIGRATION-NAMING','LF_MIGRATION_MERGE_TRAIN'),
      'capabilities', jsonb_build_array()),
    'compatibility', jsonb_build_object(
      'agent_mode', 'ROUTER_FIRST_MERGE_TRAIN_ONLY',
      'direct_mode', 'RETIRED',
      'migration_mode', 'EXACT_VERSION_SOURCE_FIRST_TRAIN_INTERNAL',
      'unknown_target', 'FAIL_CLOSED',
      'supported_target_types', jsonb_build_array('MIGRATION','DB','FUNCTION','TRIGGER','CAPABILITY'),
      'breaking_change_from', '1.0.0'),
    'migration', jsonb_build_object(
      'train_internal_only', true,
      'train_internal_caller', 'sandbox/lf_contract_gate_test/db_write_transport/lf_migration_exact_apply.py',
      'primary_executor', 'SUPABASE_CLI_DB_PUSH_LINKED',
      'fallback_executor', 'SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML',
      'exact_filename_version_required', true,
      'post_apply_timestamp_rename_normal_flow', false,
      'forbidden_executor_when_exact_version_required', 'SUPABASE_MCP_APPLY_MIGRATION'),
    'rollback', jsonb_build_object(
      'rule', 'REPOINT_CURRENT_TO_PREVIOUS_VERSION_ONLY;DO_NOT_REPLAY_APPLIED_DDL',
      'supported', true, 'source_preserved', true, 'previous_version', '1.0.0'),
    'usage', jsonb_build_object(
      'docs', 'sandbox/lf_contract_gate_test/db_write_transport/README.md',
      'selector', 'sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
      'operation', 'ACTUALIZACION_DB_LF',
      'agent_cli', 'python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py --target-type <TYPE> [--migration-path <path>] --router-execution-id EXEC-...',
      'self_test', 'python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py --self-test'),
    'currentness', jsonb_build_object(
      'authority_ref', 'github://cristhianlujan/claude-persona-lf-patch@cbcdd8dfd9053d0ef9035f095744b3e6e253ad87',
      'source_revision_immutable', true,
      'execution_binding_required', true,
      'router_execution_required', true,
      'migration_source_parity_required', true,
      'prewrite_capability_preflight_required', true)
  ),
  repeat('0', 64),
  'github://cristhianlujan/claude-persona-lf-patch@cbcdd8dfd9053d0ef9035f095744b3e6e253ad87/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
  'github://cristhianlujan/claude-persona-lf-patch@cbcdd8dfd9053d0ef9035f095744b3e6e253ad87/sandbox/lf_contract_gate_test/db_write_transport/README.md',
  'github://cristhianlujan/claude-persona-lf-patch@cbcdd8dfd9053d0ef9035f095744b3e6e253ad87/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py#self_test',
  'EXEC-DB-TRANSPORT-V2-ROUTER-20261012-001'
);

update public.lf_capability_current
set version = '2.0.0',
    manifest_sha256 = (select manifest_sha256 from public.lf_capability_version_registry
                       where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0'),
    previous_version = '1.0.0',
    promoted_at = clock_timestamp(),
    promoted_by_execution_id = 'EXEC-DB-TRANSPORT-V2-ROUTER-20261012-001',
    promotion_reason = 'Router first, Merge Train only for agents; direct SUPABASE_MCP DB writes retired (PR #2334, owner-approved)'
where capability_code = 'DB_WRITE_TRANSPORT' and version = '1.0.0';

update public.lf_capability_registry
set description = 'Agent DB writes: Router (ACT-0001) first, then Merge Train only (PR + ready-to-merge) for MIGRATION/DB/FUNCTION/TRIGGER/CAPABILITY. Without an ACTUALIZACION_DB_LF execution the selector returns REDIRECT_TO_ROUTER. Exact-version executors are Train-internal.',
    updated_at = clock_timestamp(),
    updated_by_execution_id = 'EXEC-DB-TRANSPORT-V2-ROUTER-20261012-001'
where capability_code = 'DB_WRITE_TRANSPORT';

do $post$
declare
  v_sha text;
begin
  select manifest_sha256 into v_sha from public.lf_capability_version_registry
  where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0';
  if v_sha is null or v_sha = repeat('0', 64)
     or v_sha <> encode(extensions.digest(convert_to(
          (select manifest::text from public.lf_capability_version_registry
           where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0'), 'UTF8'), 'sha256'), 'hex') then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_SHA_INVALID';
  end if;
  if (select count(*) from public.v_lf_capability_entry_guard_v1
      where capability_code = 'DB_WRITE_TRANSPORT' and current_version = '2.0.0'
        and current_manifest_sha256 = v_sha and entry_guard_state = 'GUARDED') <> 1 then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_NOT_CURRENT';
  end if;
  if (select manifest->'compatibility'->>'direct_mode' from public.lf_capability_version_registry
      where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0') <> 'RETIRED' then
    raise exception 'LF_DB_WRITE_TRANSPORT_V2_DIRECT_MODE_NOT_RETIRED';
  end if;
  if not exists (select 1 from public.lf_capability_version_registry
                 where capability_code = 'DB_WRITE_TRANSPORT' and version = '1.0.0') then
    raise exception 'LF_DB_WRITE_TRANSPORT_V1_HISTORY_MISSING';
  end if;
end $post$;

commit;
