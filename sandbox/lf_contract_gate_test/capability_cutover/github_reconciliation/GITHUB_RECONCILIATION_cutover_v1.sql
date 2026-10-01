-- SADM-PP-L5-022 isolated cutover 02: GITHUB_RECONCILIATION.
-- Registry/current-pointer cutover only. Functional core remains byte-identical.
-- No runtime/deploy/production and no legacy retirement.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-GITHUB-RECONCILIATION-CUTOVER-V1-20261001';
  v_source_sha constant text := '78d0b7c6b742826451c8cf9180d85e46877f9d20';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_CUTOVER_LF_GOVERNANCE_MISSING';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='OWNER_RUNNER_CARRIER_AUTHORITY' and archived_at is null) then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_CUTOVER_OWNER_RUNNER_CARRIER_MISSING';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_CUTOVER_EXECUTION_CONTRACT_MISSING';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='GITHUB_RECONCILIATION' and archived_at is null) then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_CUTOVER_ASSET_MISSING';
  end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_CUTOVER_CURRENTNESS_MISSING';
  end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','GITHUB_RECONCILIATION',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','LF_CAPABILITY_EXECUTION_REQUEST_V1 + LF_GITHUB_RECONCILIATION_SCOPE_V1 + OBSERVATION',
      'output','LF_GITHUB_RECONCILIATION_RECEIPT_V1',
      'authority','BOUNDED_POST_MERGE_DECLARED_SCOPE_READBACK_ONLY'
    ),
    'delivery',jsonb_build_object(
      'mode','VERSIONED_REPOSITORY_CAPABILITY',
      'core','sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_v1.py',
      'consumer','POST_PASE_ORCHESTRATOR_V1',
      'external_fact_resolution','CARRIER_OBSERVATION_ONLY'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','REPOSITORY_BOUND'
    ),
    'dependencies',jsonb_build_object(
      'packages',jsonb_build_array('python>=3.11'),
      'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY'),
      'governance',jsonb_build_array('LF_GOVERNANCE','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED',
      'legacy_workflow_preserved',true,
      'legacy_edge_function_preserved',true,
      'duplicate_engine_forbidden',true,
      'functional_core_unchanged',true
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
      'script','sandbox/lf_contract_gate_test/capability_cutover/github_reconciliation/GITHUB_RECONCILIATION_cutover_rollback_v1.sql',
      'rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_VERSION_AND_LEGACY_PATHS'
    ),
    'usage',jsonb_build_object(
      'core','sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_v1.py',
      'contract','sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_v1.json',
      'validator','sandbox/lf_contract_gate_test/github_reconciliation/test_github_reconciliation_v1.py',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha,
      'authority_capability','CURRENTNESS_AUTHORITY',
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'source_revision_immutable',true,
      'core_blob_sha1','2043574b30820aea3a1bde969366b196d23eb8f5',
      'test_blob_sha1','b659d04e0485211a16b46a3788c5f04bb616ea59'
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'GITHUB_RECONCILIATION','GitHub Reconciliation','TRANSVERSAL','LF_GOVERNANCE','ACTIVE',
    'Bounded deterministic post-merge readback over the exact declared GitHub scope; applicability and lifecycle remain outside this capability.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) on conflict(capability_code) do update set
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope=excluded.owner_scope,
    status='ACTIVE',
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=now(),
    updated_by_execution_id=v_execution_id;

  select manifest_sha256 into v_existing_sha
  from public.lf_capability_version_registry
  where capability_code='GITHUB_RECONCILIATION' and version='1.0.0';

  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then
    raise exception 'GITHUB_RECONCILIATION_VERSION_1_0_0_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'GITHUB_RECONCILIATION','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/github_reconciliation/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/github_reconciliation/test_github_reconciliation_v1.py',
    v_execution_id
  ) on conflict(capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1(
    'GITHUB_RECONCILIATION','1.0.0',null,v_execution_id,
    'L5 isolated registry and entry-guard cutover; functional core and legacy rollback paths preserved.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'GITHUB_RECONCILIATION_CURRENT_POINTER_BLOCKED:%',v_promote::text;
  end if;

  update public.lf_activos
  set estado_documental='VIGENTE',
      estado_operativo='ACTIVO',
      version='1.0.0',
      owner_name='LF_GOVERNANCE',
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'administrative_owner','LF_GOVERNANCE',
        'registry_capability_code','GITHUB_RECONCILIATION',
        'registry_version','1.0.0',
        'registry_manifest_sha256',v_manifest_sha,
        'registry_cutover_state','ENFORCED',
        'functional_core_unchanged',true,
        'legacy_workflow_preserved',true,
        'legacy_edge_function_preserved',true,
        'entry_contract',jsonb_build_object(
          'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
          'required',true,
          'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
          'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
          'direct_new_binding_policy','BLOCK',
          'enforcement_state','ENFORCED',
          'owner','LF_GOVERNANCE'
        )
      ),
      updated_at=now(),
      updated_by_execution_id=v_execution_id
  where codigo_activo='GITHUB_RECONCILIATION' and archived_at is null;
  if not found then raise exception 'GITHUB_RECONCILIATION_ASSET_UPDATE_MISSING'; end if;

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    'GITHUB_RECONCILIATION','CURRENTNESS_AUTHORITY','DEPENDE_DE','current source/manifest authority before binding',
    'sandbox/lf_contract_gate_test/capability_cutover/github_reconciliation/github_reconciliation_cutover_inventory_v1.json',
    '8c1d2f6c-4a1c-4f80-9d5d-022000000002'::uuid,v_execution_id,v_execution_id
  ) on conflict do nothing;
end $$;
