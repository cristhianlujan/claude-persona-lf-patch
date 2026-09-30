-- MIGRATION_SOURCE_PARITY registry cutover only.
-- No functional-core change, no runtime/deploy activation, no migration apply/repair.
-- Canonical entrypoint for new bindings: public.fn_lf_capability_bind_from_orchestrator_v1.

do $$
declare
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','MIGRATION_SOURCE_PARITY',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','LF_MIGRATION_SOURCE_PARITY_SNAPSHOTS_V1',
      'output','lf-migration-source-parity-result/v1',
      'authority','GIT_LEDGER_PARITY_ONLY_NO_SCOPE_ROUTING_OR_REPAIR'
    ),
    'delivery',jsonb_build_object(
      'mode','VERSIONED_REPOSITORY_CAPABILITY',
      'core','sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py',
      'adapter','sandbox/lf_contract_gate_test/lf_migration_source_parity.py',
      'consumer_state','ENTRY_GUARD_CUTOVER'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REPOSITORY_BOUND'
    ),
    'dependencies',jsonb_build_object(
      'packages',jsonb_build_array('python>=3.11'),
      'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY'),
      'governance',jsonb_build_array('ACT-0001','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED',
      'legacy_carriers_preserved',true,
      'duplicate_engine_forbidden',true,
      'functional_core_unchanged',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY',
      'runtime_or_carrier_change',false,
      'functional_core_change',false,
      'registry_projection','sandbox/lf_contract_gate_test/transversal_assets/migration_source_parity/MIGRATION_SOURCE_PARITY_registry_projection_v1.sql'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','REGISTRY_POINTER_AND_OWNER_METADATA_REVERSAL_ONLY;NO_FUNCTIONAL_CORE_ROLLBACK_REQUIRED'
    ),
    'usage',jsonb_build_object(
      'core','sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py',
      'adapter','sandbox/lf_contract_gate_test/lf_migration_source_parity.py',
      'validator','sandbox/lf_contract_gate_test/s30_migration_source_parity/test_migration_source_parity_core.py',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch@e1c98f25a3fec60bf50c3ca73b52e44fa34afa17',
      'authority_capability','CURRENTNESS_AUTHORITY',
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'source_revision_immutable',true
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(
    capability_code, capability_name, capability_kind, owner_scope, status,
    description, created_by_execution_id, updated_by_execution_id,
    entry_guard_required, entry_guard_code
  ) values (
    'MIGRATION_SOURCE_PARITY','Migration Source Parity','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Fail-closed Git-vs-Supabase migration source parity over already-resolved snapshots. Applicability belongs to the caller/orchestrator; this capability never repairs source or owns lifecycle.',
    'EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930',
    'EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930',
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
  where capability_code='MIGRATION_SOURCE_PARITY' and version='1.0.0';

  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then
    raise exception 'MIGRATION_SOURCE_PARITY_VERSION_1_0_0_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'MIGRATION_SOURCE_PARITY','1.0.0',1,0,0,'RELEASED',null,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@e1c98f25a3fec60bf50c3ca73b52e44fa34afa17/sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py',
    'github://cristhianlujan/claude-persona-lf-patch@e1c98f25a3fec60bf50c3ca73b52e44fa34afa17/sandbox/lf_contract_gate_test/transversal_assets/migration_source_parity/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@e1c98f25a3fec60bf50c3ca73b52e44fa34afa17/sandbox/lf_contract_gate_test/s30_migration_source_parity/test_migration_source_parity_core.py',
    'EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930'
  ) on conflict (capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1(
    'MIGRATION_SOURCE_PARITY','1.0.0',null,
    'EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930',
    'Registry/entry-guard cutover only; existing functional core and carriers preserved.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'MIGRATION_SOURCE_PARITY_CURRENT_POINTER_BLOCKED: %', v_promote::text;
  end if;

  update public.lf_activos
  set owner_name='SUPER_ADMIN',
      metadata = coalesce(metadata,'{}'::jsonb)
        || jsonb_build_object(
          'legacy_owner_name',coalesce(metadata->>'legacy_owner_name',owner_name),
          'registry_capability_code','MIGRATION_SOURCE_PARITY',
          'registry_version','1.0.0',
          'registry_manifest_sha256',v_manifest_sha,
          'registry_cutover_state','ENFORCED',
          'entry_contract',jsonb_build_object(
            'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
            'required',true,
            'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
            'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
            'direct_new_binding_policy','BLOCK',
            'enforcement_state','ENFORCED',
            'owner','SUPER_ADMIN',
            'updated_by_execution_id','EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930'
          )
        ),
      updated_at=now(),
      updated_by_execution_id='EXEC-SADM-MIGRATION-SOURCE-PARITY-REGISTRY-CUTOVER-20260930'
  where codigo_activo='MIGRATION_SOURCE_PARITY';

  if not found then
    raise exception 'MIGRATION_SOURCE_PARITY_LF_ACTIVOS_MISSING';
  end if;
end;
$$;
