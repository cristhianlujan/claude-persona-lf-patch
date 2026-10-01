-- SADM-PP-L5-022 isolated cutover 09: PLAN_AUTHORITY_DRIFT_GUARD.
-- Registry/current-pointer cutover only. Functional core remains byte-identical.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-PLAN-AUTHORITY-CUTOVER-V1-20261001';
  v_source_sha constant text := '4058845e74210043ef6fa9a13fc4e4885c738cad';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and archived_at is null) then raise exception 'BLOCK_PLAN_AUTHORITY_CUTOVER_ASSET_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_PLAN_AUTHORITY_CUTOVER_CURRENTNESS_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_PLAN_AUTHORITY_CUTOVER_EXECUTION_CONTRACT_MISSING'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','PLAN_AUTHORITY_DRIFT_GUARD','version','1.0.0',
    'contract',jsonb_build_object('input','LF_CAPABILITY_EXECUTION_REQUEST_V1 + PLAN_ANCHOR + LIVE_PLAN_SNAPSHOT + CURRENTNESS_RECEIPT + AUTHORIZED_DELTAS','output','LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1','authority','IMMUTABLE_PLAN_ANCHOR_PLUS_AUTHORIZED_DELTA_CHAIN_ONLY'),
    'delivery',jsonb_build_object('mode','VERSIONED_REPOSITORY_CAPABILITY','core','sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_v1.py','consumer','POST_PASE_CONTROL_PLANE'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object('packages',jsonb_build_array('python>=3.11'),'capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY'),'governance',jsonb_build_array('LF_GOVERNANCE','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','parallel_currentness_engine',false,'functional_core_unchanged',true),
    'migration',jsonb_build_object('mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY','functional_core_change',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/plan_authority/PLAN_AUTHORITY_DRIFT_GUARD_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_CANDIDATE_ASSET'),
    'usage',jsonb_build_object('core','sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_v1.py','contract','sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_v1.json','validator','sandbox/lf_contract_gate_test/plan_authority/test_plan_authority_drift_guard_v1.py','entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha,'authority_capability','CURRENTNESS_AUTHORITY','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','source_revision_immutable',true,'core_blob_sha1','ff0d702b8d7f49235320ab923dd93fd222c54de2','test_blob_sha1','501ba9088c30fc0cfe44b249d76529a84a491020','anchor_event_id',19435)
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('PLAN_AUTHORITY_DRIFT_GUARD','Plan Authority Drift Guard','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Fail-closed immutable plan anchor and authorized delta-chain guard over CURRENTNESS_AUTHORITY.',v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set capability_name=excluded.capability_name,capability_kind=excluded.capability_kind,owner_scope=excluded.owner_scope,status='ACTIVE',description=excluded.description,entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_execution_id;
  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='PLAN_AUTHORITY_DRIFT_GUARD' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then raise exception 'PLAN_AUTHORITY_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('PLAN_AUTHORITY_DRIFT_GUARD','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_v1.py','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/plan_authority/README.md','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/plan_authority/test_plan_authority_drift_guard_v1.py',v_execution_id)
  on conflict(capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('PLAN_AUTHORITY_DRIFT_GUARD','1.0.0',null,v_execution_id,'L5 isolated plan-authority registry and guard cutover; functional core unchanged.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'PLAN_AUTHORITY_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
  update public.lf_activos set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('registry_cutover_state','ENFORCED','functional_core_unchanged',true,'registry_manifest_sha256',v_manifest_sha),updated_at=now(),updated_by_execution_id=v_execution_id where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and archived_at is null;
end $$;
