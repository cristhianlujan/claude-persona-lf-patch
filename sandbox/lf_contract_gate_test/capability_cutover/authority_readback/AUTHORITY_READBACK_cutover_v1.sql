-- SADM-PP-L5-022 isolated cutover 03: AUTHORITY_READBACK.
-- Registry/current-pointer cutover only. Core/adapters remain byte-identical.
-- No runtime/deploy/production and no legacy retirement.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-AUTHORITY-READBACK-CUTOVER-V1-20261001';
  v_source_sha constant text := 'c2f0d008d8588d2c439ea14b6143a522f38370e5';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_AUTHORITY_READBACK_CUTOVER_LF_GOVERNANCE_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='OWNER_RUNNER_CARRIER_AUTHORITY' and archived_at is null) then raise exception 'BLOCK_AUTHORITY_READBACK_CUTOVER_OWNER_RUNNER_CARRIER_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_AUTHORITY_READBACK_CUTOVER_EXECUTION_CONTRACT_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='AUTHORITY_READBACK' and archived_at is null) then raise exception 'BLOCK_AUTHORITY_READBACK_CUTOVER_ASSET_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_AUTHORITY_READBACK_CUTOVER_CURRENTNESS_MISSING'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','AUTHORITY_READBACK',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','LF_CAPABILITY_EXECUTION_REQUEST_V1 + LF_AUTHORITY_READBACK_SCOPE_V1 + NORMALIZED_READ_ONLY_OBSERVATIONS',
      'output','LF_AUTHORITY_READBACK_RECEIPT_V1',
      'authority','DECLARED_READ_ONLY_AUTHORITY_CHECKS_ONLY'
    ),
    'delivery',jsonb_build_object(
      'mode','VERSIONED_REPOSITORY_CAPABILITY',
      'core','sandbox/lf_contract_gate_test/authority_readback/authority_readback_v1.py',
      'adapters','sandbox/lf_contract_gate_test/authority_readback/authority_readback_adapters_v1.py',
      'consumer','POST_PASE_ORCHESTRATOR_V1'
    ),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object(
      'packages',jsonb_build_array('python>=3.11'),
      'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY'),
      'governance',jsonb_build_array('LF_GOVERNANCE','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED',
      'legacy_mutation_functions_preserved',true,
      'duplicate_engine_forbidden',true,
      'functional_core_unchanged',true,
      'read_only_adapters_unchanged',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY',
      'runtime_or_carrier_change',false,
      'functional_core_change',false,
      'legacy_retirement',false,
      'work_code','SADM-PP-L5-022'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'script','sandbox/lf_contract_gate_test/capability_cutover/authority_readback/AUTHORITY_READBACK_cutover_rollback_v1.sql',
      'rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_VERSION_AND_LEGACY_MUTATION_PATHS'
    ),
    'usage',jsonb_build_object(
      'core','sandbox/lf_contract_gate_test/authority_readback/authority_readback_v1.py',
      'adapters','sandbox/lf_contract_gate_test/authority_readback/authority_readback_adapters_v1.py',
      'contract','sandbox/lf_contract_gate_test/authority_readback/authority_readback_v1.json',
      'validator','sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_v1.py',
      'adapter_validator','sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_adapters_v1.py',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha,
      'authority_capability','CURRENTNESS_AUTHORITY',
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'source_revision_immutable',true,
      'core_blob_sha1','686c21c49efa21f6ea83ae20d91dec046722c92c',
      'adapters_blob_sha1','6ffc635c25b70472e28229f4d5da290555a77728',
      'core_test_blob_sha1','f941564eb3e8d05056eb6b23fcb1576335412403',
      'adapter_test_blob_sha1','4634ab5ab99528e47ab95acc33cf9dd59b893d57'
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'AUTHORITY_READBACK','Authority Readback','TRANSVERSAL','LF_GOVERNANCE','ACTIVE',
    'Read-only deterministic validation of exact declared authority checks through normalized adapters; mutation and next-gate selection remain outside the capability.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) on conflict(capability_code) do update set
    capability_name=excluded.capability_name,capability_kind=excluded.capability_kind,owner_scope=excluded.owner_scope,
    status='ACTIVE',description=excluded.description,entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=now(),updated_by_execution_id=v_execution_id;

  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry
  where capability_code='AUTHORITY_READBACK' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then raise exception 'AUTHORITY_READBACK_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'AUTHORITY_READBACK','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/authority_readback/authority_readback_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/authority_readback/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_v1.py',
    v_execution_id
  ) on conflict(capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1(
    'AUTHORITY_READBACK','1.0.0',null,v_execution_id,
    'L5 isolated registry and entry-guard cutover; read-only core/adapters and legacy mutation paths preserved.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'AUTHORITY_READBACK_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;

  update public.lf_activos
  set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'administrative_owner','LF_GOVERNANCE','registry_capability_code','AUTHORITY_READBACK','registry_version','1.0.0',
        'registry_manifest_sha256',v_manifest_sha,'registry_cutover_state','ENFORCED','functional_core_unchanged',true,
        'read_only_adapters_unchanged',true,'legacy_mutation_functions_preserved',true,
        'entry_contract',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,
          'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
          'direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED','owner','LF_GOVERNANCE')
      ),updated_at=now(),updated_by_execution_id=v_execution_id
  where codigo_activo='AUTHORITY_READBACK' and archived_at is null;
  if not found then raise exception 'AUTHORITY_READBACK_ASSET_UPDATE_MISSING'; end if;
end $$;
