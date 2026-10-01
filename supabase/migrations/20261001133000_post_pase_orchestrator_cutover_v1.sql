-- SADM-PP-L5-022 isolated cutover 14: POST_PASE_ORCHESTRATOR.
-- Materializes and promotes the already-verified sequential immutable-plan dispatcher.
-- Non-production only. No applicability rediscovery, parallel dispatch, runtime/deploy or production.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-POST-PASE-ORCHESTRATOR-CUTOVER-V1-20261001';
  v_source_sha constant text := '214694d69e28606f096b3dba94f8b6ad10237586';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_CUTOVER_LF_GOVERNANCE_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='POST_PASE_ROUTER' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_CUTOVER_ROUTER_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='OWNER_RUNNER_CARRIER_AUTHORITY' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_CUTOVER_OWNER_RUNNER_CARRIER_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_CUTOVER_EXECUTION_CONTRACT_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and version='1.1.0') then raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_CUTOVER_LEDGER_MISSING'; end if;

  insert into public.lf_activos(codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id)
  values('POST_PASE_ORCHESTRATOR','POST_PASE_ORCHESTRATOR_V1','ORCHESTRATOR','POST_PASE_SEQUENTIAL_DISPATCHER','GITHUB_CONTRACT','CANDIDATE_READ_ONLY','VIGENTE','ACTIVO','BLOQUEADO','1.0.0','sandbox/lf_contract_gate_test/post_pase_orchestrator/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','POST_PASE_ORCHESTRATOR_20261001',1,
    jsonb_build_object('solution_code','POST_PASE_ORCHESTRATOR_V1','work_code','SADM-PP-L4-020','mode','SEQUENTIAL_IMMUTABLE_PLAN_DISPATCH','applicability_rediscovery',false,'control_logic',false,'owner_recalculation',false,'parallel_dispatch',false,'new_receipt_store',false,'cutover_executed',true,'runtime_authorized',false,'production_authorized',false),
    jsonb_build_object('schema_version','POST_PASE_ORCHESTRATOR_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','plan_schema','LF_POST_PASE_PLAN_V1','execution_contract','CAPABILITY_EXECUTION_CONTRACT_V1','binding_authority','OWNER_RUNNER_CARRIER_AUTHORITY_V1','artifact_transport_policy','PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1','registry_cutover_state','ENFORCED'),
    '8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id)
  on conflict(codigo_activo) do update set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',raw_payload=excluded.raw_payload,metadata=excluded.metadata,updated_at=now(),updated_by_execution_id=v_execution_id;

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
   ('POST_PASE_ORCHESTRATOR','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','POST_PASE_ROUTER','DEPENDE_DE','consumes immutable plan only','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','OWNER_RUNNER_CARRIER_AUTHORITY','DEPENDE_DE','binding resolution remains canonical authority responsibility','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','CAPABILITY_EXECUTION_CONTRACT','DEPENDE_DE','shared request receipt envelope','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','EVIDENCE_LEDGER','DEPENDE_DE','receipt persistence remains canonical ledger responsibility','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,v_execution_id,v_execution_id)
  on conflict do nothing;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','POST_PASE_ORCHESTRATOR','version','1.0.0',
    'contract',jsonb_build_object('input','LF_POST_PASE_PLAN_V1 + ORCHESTRATOR_EXECUTION_ID + BINDING_PROVIDER + CAPABILITY_EXECUTOR','output','LF_POST_PASE_ORCHESTRATION_RECEIPT_V1','authority','SEQUENTIAL_FAIL_CLOSED_IMMUTABLE_PLAN_DISPATCH'),
    'delivery',jsonb_build_object('mode','VERSIONED_REPOSITORY_CONSUMER','core','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_v1.py'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('POST_PASE_ROUTER','EVIDENCE_LEDGER'),'governance',jsonb_build_array('LF_GOVERNANCE','OWNER_RUNNER_CARRIER_AUTHORITY','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','applicability_rediscovery',false,'parallel_dispatch',false,'embedded_control_logic',false,'owner_runner_carrier_recalculation',false,'new_receipt_store',false,'functional_core_unchanged',true),
    'migration',jsonb_build_object('mode','ASSET_MATERIALIZATION_AND_REGISTRY_CURRENT_POINTER_CUTOVER','functional_core_change',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/post_pase_orchestrator/POST_PASE_ORCHESTRATOR_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_VERSION_AND_RELATIONS'),
    'usage',jsonb_build_object('core','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_v1.py','contract','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','validator','sandbox/lf_contract_gate_test/post_pase_orchestrator/test_post_pase_orchestrator_v1.py','entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha,'source_revision_immutable',true,'core_blob_sha1','5dca9b717803f78c5e2ef79747219919a74f12b3','test_blob_sha1','bc831e852540f8c26f71beb83e38a56ce7030657','terminal_source_event_id',19662,'prior_deterministic_check_count',33,'direct_github_identity_only',true)
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('POST_PASE_ORCHESTRATOR','POST-PASE Orchestrator','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Sequential fail-closed dispatcher of an immutable POST-PASE plan using canonical bindings and shared execution contracts.',v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_execution_id;
  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='POST_PASE_ORCHESTRATOR' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then raise exception 'POST_PASE_ORCHESTRATOR_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('POST_PASE_ORCHESTRATOR','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_v1.py','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_orchestrator/README.md','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_orchestrator/test_post_pase_orchestrator_v1.py',v_execution_id) on conflict(capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('POST_PASE_ORCHESTRATOR','1.0.0',null,v_execution_id,'L5 isolated POST_PASE_ORCHESTRATOR cutover; sequential immutable-plan dispatcher.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'POST_PASE_ORCHESTRATOR_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
end $$;
