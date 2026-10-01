-- MIGRATION_WRITE_AHEAD_V1 registry/entry-guard cutover only.
-- Capability remains NOT CURRENT / runtime-not-activated.
-- No Git write is executed by this projection.

do $$
declare
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
begin
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','MIGRATION_WRITE_AHEAD_V1',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','LF_MIGRATION_GIT_PERSIST_REQUEST_V1',
      'output','lf-migration-git-persist/v1',
      'authority','SOURCE_PERSISTENCE_ONLY_NO_DB_APPLY_MERGE_OR_MAIN_WRITE'
    ),
    'delivery',jsonb_build_object(
      'mode','VERSIONED_REPOSITORY_CAPABILITY',
      'transport','sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py',
      'consumer_state','REGISTERED_GUARDED_NOT_CURRENT'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REPOSITORY_BOUND'
    ),
    'dependencies',jsonb_build_object(
      'packages',jsonb_build_array('python>=3.11','git'),
      'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY','DB_WRITE_TRANSPORT'),
      'governance',jsonb_build_array('ACT-0001','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'direct_main_write','FORBIDDEN',
      'merge','FORBIDDEN',
      'db_apply','FORBIDDEN',
      'sha_or_path_mismatch','FAIL_CLOSED',
      'duplicate_writer_forbidden',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY',
      'runtime_activation',false,
      'current_pointer_creation',false,
      'registry_projection','sandbox/lf_contract_gate_test/db_write_transport/MIGRATION_WRITE_AHEAD_V1_registry_projection.sql'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REMOVE_REGISTRY_PROJECTION_AND_RESTORE_OWNER_METADATA_ONLY;NO_GIT_WRITE_REPLAY'
    ),
    'usage',jsonb_build_object(
      'transport','sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py',
      'validator','sandbox/lf_contract_gate_test/db_write_transport/test_lf_migration_git_persist_contract.py',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch@2a33b0e59220491b918a483d538dae2079a45f14',
      'authority_capability','CURRENTNESS_AUTHORITY',
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'source_revision_immutable',true,
      'runtime_authorized',false,
      'production_authorized',false,
      'current_pointer_expected',false
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'MIGRATION_WRITE_AHEAD_V1','Migration Write Ahead V1','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Exact migration-source Git persistence primitive. Registry entry does not activate runtime or authorize a Git write.',
    'EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930',
    'EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930',
    true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  on conflict (capability_code) do update set
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope=excluded.owner_scope,
    status=excluded.status,
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;

  select manifest_sha256 into v_existing_sha
  from public.lf_capability_version_registry
  where capability_code='MIGRATION_WRITE_AHEAD_V1' and version='1.0.0';

  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then
    raise exception 'MIGRATION_WRITE_AHEAD_V1_VERSION_1_0_0_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'MIGRATION_WRITE_AHEAD_V1','1.0.0',1,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@2a33b0e59220491b918a483d538dae2079a45f14/sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py',
    'github://cristhianlujan/claude-persona-lf-patch@2a33b0e59220491b918a483d538dae2079a45f14/sandbox/lf_contract_gate_test/db_write_transport/MIGRATION_WRITE_AHEAD_V1.md',
    'github://cristhianlujan/claude-persona-lf-patch@2a33b0e59220491b918a483d538dae2079a45f14/sandbox/lf_contract_gate_test/db_write_transport/test_lf_migration_git_persist_contract.py',
    'EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930'
  ) on conflict (capability_code,version) do nothing;

  if exists(select 1 from public.lf_capability_current where capability_code='MIGRATION_WRITE_AHEAD_V1') then
    raise exception 'MIGRATION_WRITE_AHEAD_V1_UNEXPECTED_CURRENT_POINTER';
  end if;

  update public.lf_activos
  set owner_name='SUPER_ADMIN',
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'legacy_owner_name',coalesce(metadata->>'legacy_owner_name',owner_name),
        'registry_capability_code','MIGRATION_WRITE_AHEAD_V1',
        'registry_version','1.0.0',
        'registry_manifest_sha256',v_manifest_sha,
        'registry_cutover_state','REGISTERED_GUARDED_NOT_CURRENT',
        'entry_contract',jsonb_build_object(
          'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
          'required',true,
          'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
          'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
          'direct_new_binding_policy','BLOCK',
          'enforcement_state','ENTRY_ENFORCED_NOT_CURRENT',
          'owner','SUPER_ADMIN',
          'updated_by_execution_id','EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930'
        )
      ),
      updated_at=now(),
      updated_by_execution_id='EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930'
  where codigo_activo='MIGRATION_WRITE_AHEAD_V1';

  if not found then raise exception 'MIGRATION_WRITE_AHEAD_V1_LF_ACTIVOS_MISSING'; end if;
end;
$$;
