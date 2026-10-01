-- SADM-PP-L5-022 isolated cutover 04: RUNTIME_DEPLOY_VERIFICATION.
-- Registers only the read-only verifier. It does not deploy, restart, switch symlinks or touch production.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-RUNTIME-DEPLOY-VERIFICATION-CUTOVER-V1-20261001';
  v_source_sha constant text := '19dac34c45b41f0416e254e1ae2dc45a33d84444';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_CUTOVER_LF_GOVERNANCE_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_CUTOVER_EXECUTION_CONTRACT_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='RUNTIME_DEPLOY_VERIFICATION' and archived_at is null) then raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_CUTOVER_ASSET_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_CUTOVER_CURRENTNESS_MISSING'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','RUNTIME_DEPLOY_VERIFICATION',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','LF_CAPABILITY_EXECUTION_REQUEST_V1 + LF_RUNTIME_DEPLOY_VERIFICATION_SCOPE_V1 + DEPLOYMENT_RECEIPT + READ_ONLY_OBSERVATIONS',
      'output','LF_RUNTIME_DEPLOY_VERIFICATION_RECEIPT_V1',
      'authority','EXACT_DEPLOYMENT_RECEIPT_AND_READ_ONLY_RUNTIME_READBACK_ONLY'
    ),
    'delivery',jsonb_build_object(
      'mode','VERSIONED_REPOSITORY_CAPABILITY',
      'core','sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_v1.py',
      'consumer','POST_PASE_ORCHESTRATOR_V1',
      'effect_owner','EXPLICIT_GOVERNED_DEPLOY_OPERATION'
    ),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object(
      'packages',jsonb_build_array('python>=3.11'),
      'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY'),
      'governance',jsonb_build_array('LF_GOVERNANCE','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')
    ),
    'compatibility',jsonb_build_object(
      'unknown_state','FAIL_CLOSED','legacy_installer_preserved',true,'deploy_effect_path_preserved',true,
      'duplicate_engine_forbidden',true,'functional_core_unchanged',true
    ),
    'migration',jsonb_build_object(
      'mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY','runtime_or_carrier_change',false,'functional_core_change',false,
      'deploy_executed',false,'restart_executed',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'script','sandbox/lf_contract_gate_test/capability_cutover/runtime_deploy_verification/RUNTIME_DEPLOY_VERIFICATION_cutover_rollback_v1.sql',
      'rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_DEPLOY_EFFECT_PATH'
    ),
    'usage',jsonb_build_object(
      'core','sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_v1.py',
      'contract','sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_v1.json',
      'validator','sandbox/lf_contract_gate_test/runtime_deploy_verification/test_runtime_deploy_verification_v1.py',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha,
      'authority_capability','CURRENTNESS_AUTHORITY','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'source_revision_immutable',true,'core_blob_sha1','af53b9221d15d27a8ff016e3ec1ada804594867a',
      'test_blob_sha1','6d9ff2a581840eee8844836d4099cd70b513fe3b'
    )
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'RUNTIME_DEPLOY_VERIFICATION','Runtime Deploy Verification','TRANSVERSAL','LF_GOVERNANCE','ACTIVE',
    'Read-only verification of an exact deployment receipt and declared runtime readbacks; deployment and restart effects remain outside this capability.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) on conflict(capability_code) do update set
    capability_name=excluded.capability_name,capability_kind=excluded.capability_kind,owner_scope=excluded.owner_scope,
    status='ACTIVE',description=excluded.description,entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=now(),updated_by_execution_id=v_execution_id;

  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry
  where capability_code='RUNTIME_DEPLOY_VERIFICATION' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then raise exception 'RUNTIME_DEPLOY_VERIFICATION_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'RUNTIME_DEPLOY_VERIFICATION','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/runtime_deploy_verification/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/runtime_deploy_verification/test_runtime_deploy_verification_v1.py',
    v_execution_id
  ) on conflict(capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1(
    'RUNTIME_DEPLOY_VERIFICATION','1.0.0',null,v_execution_id,
    'L5 isolated verifier registry cutover only; no deploy/restart/runtime effect executed.'
  );
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'RUNTIME_DEPLOY_VERIFICATION_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;

  update public.lf_activos
  set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'administrative_owner','LF_GOVERNANCE','registry_capability_code','RUNTIME_DEPLOY_VERIFICATION','registry_version','1.0.0',
        'registry_manifest_sha256',v_manifest_sha,'registry_cutover_state','ENFORCED','functional_core_unchanged',true,
        'legacy_installer_preserved',true,'deploy_effect_path_preserved',true,'deploy_executed',false,'restart_executed',false,
        'entry_contract',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,
          'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
          'direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED','owner','LF_GOVERNANCE')
      ),updated_at=now(),updated_by_execution_id=v_execution_id
  where codigo_activo='RUNTIME_DEPLOY_VERIFICATION' and archived_at is null;
  if not found then raise exception 'RUNTIME_DEPLOY_VERIFICATION_ASSET_UPDATE_MISSING'; end if;
end $$;
