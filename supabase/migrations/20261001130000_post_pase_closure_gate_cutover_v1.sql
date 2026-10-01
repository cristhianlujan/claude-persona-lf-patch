-- SADM-PP-L5-022 isolated cutover 12: CLOSURE_GATE.
-- Materializes and promotes the already-verified deterministic POST-PASE closure gate.
-- Non-production only. No control execution, evidence collection, runtime/deploy or production.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-CLOSURE-GATE-CUTOVER-V1-20261001';
  v_source_sha constant text := '5627c5b2a0a8c219660b72a90edb10189a73c2c7';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_CUTOVER_LF_GOVERNANCE_MISSING'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_CUTOVER_EXECUTION_CONTRACT_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='PLAN_AUTHORITY_DRIFT_GUARD' and version='1.0.0') then raise exception 'BLOCK_CLOSURE_GATE_CUTOVER_PLAN_AUTHORITY_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='FINAL_EVIDENCE' and version='1.0.0') then raise exception 'BLOCK_CLOSURE_GATE_CUTOVER_FINAL_EVIDENCE_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='WAIVER_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_CLOSURE_GATE_CUTOVER_WAIVER_AUTHORITY_MISSING'; end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
    estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
    source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    'CLOSURE_GATE','TRANSVERSAL_POST_PASE_CLOSURE_GATE','CAPABILITY','TRANSVERSAL_DETERMINISTIC_CLOSURE_GATE',
    'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','VIGENTE','ACTIVO','BLOQUEADO','1.0.0',
    'sandbox/lf_contract_gate_test/closure_gate/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','CLOSURE_GATE_20261001',1,
    jsonb_build_object('solution_code','POST_PASE_CLOSURE_GATE_V1','work_code','SADM-PP-L3-017','verdict_count',4,'evidence_collection',false,'control_execution',false,'cutover_executed',true,'runtime_authorized',false,'production_authorized',false),
    jsonb_build_object('schema_version','CLOSURE_GATE_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','final_evidence','FINAL_EVIDENCE','waiver_authority','WAIVER_AUTHORITY','plan_authority','PLAN_AUTHORITY_DRIFT_GUARD','terminal_verdict_only',true,'registry_cutover_state','ENFORCED'),
    '8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,v_execution_id,v_execution_id
  ) on conflict(codigo_activo) do update set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',raw_payload=excluded.raw_payload,metadata=excluded.metadata,updated_at=now(),updated_by_execution_id=v_execution_id;

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
   ('CLOSURE_GATE','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative owner','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,v_execution_id,v_execution_id),
   ('CLOSURE_GATE','PLAN_AUTHORITY_DRIFT_GUARD','DEPENDE_DE','authorized plan identity and control set','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,v_execution_id,v_execution_id),
   ('CLOSURE_GATE','FINAL_EVIDENCE','DEPENDE_DE','bounded manifest and terminal outcomes','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,v_execution_id,v_execution_id),
   ('CLOSURE_GATE','WAIVER_AUTHORITY','DEPENDE_DE','exact one-use waiver receipt for failed controls only','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,v_execution_id,v_execution_id)
  on conflict do nothing;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','CLOSURE_GATE','version','1.0.0',
    'contract',jsonb_build_object('input','LF_POST_PASE_CLOSURE_REQUEST_V1 + AUTHORIZED_PLAN + FINAL_EVIDENCE_MANIFEST + OPTIONAL_ONE_USE_WAIVER_RECEIPTS','output','LF_POST_PASE_CLOSURE_VERDICT_V1','authority','DETERMINISTIC_TERMINAL_VERDICT_ONLY'),
    'delivery',jsonb_build_object('mode','VERSIONED_REPOSITORY_CAPABILITY','core','sandbox/lf_contract_gate_test/closure_gate/closure_gate_v1.py','consumer','POST_PASE_ORCHESTRATOR'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('PLAN_AUTHORITY_DRIFT_GUARD','FINAL_EVIDENCE','WAIVER_AUTHORITY'),'governance',jsonb_build_array('LF_GOVERNANCE','CAPABILITY_EXECUTION_CONTRACT','ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','verdicts',jsonb_build_array('PASS','FAIL','BLOCKED','WAIVED'),'evidence_collection',false,'control_execution',false,'promotion',false,'lifecycle_mutation',false,'functional_core_unchanged',true),
    'migration',jsonb_build_object('mode','ASSET_MATERIALIZATION_AND_REGISTRY_CURRENT_POINTER_CUTOVER','functional_core_change',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/closure_gate/CLOSURE_GATE_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_VERSION_AND_RELATIONS'),
    'usage',jsonb_build_object('core','sandbox/lf_contract_gate_test/closure_gate/closure_gate_v1.py','contract','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','validator','sandbox/lf_contract_gate_test/closure_gate/test_closure_gate_v1.py','entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha,'source_revision_immutable',true,'core_blob_sha1','f91433006bddcc51de53fe8ad6a2da3c7b3fa1e0','test_blob_sha1','fc401aa4deb046f071e9356561ffa74722791d15','terminal_source_event_id',19652,'prior_deterministic_check_count',26)
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('CLOSURE_GATE','Closure Gate','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Deterministic POST-PASE terminal closure verdict over authorized plan, final evidence manifest and exact one-use waiver receipts.',v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_execution_id;

  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='CLOSURE_GATE' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then raise exception 'CLOSURE_GATE_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;

  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('CLOSURE_GATE','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/closure_gate/closure_gate_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/closure_gate/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/closure_gate/test_closure_gate_v1.py',v_execution_id)
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1('CLOSURE_GATE','1.0.0',null,v_execution_id,'L5 isolated CLOSURE_GATE cutover; deterministic verdict only, no evidence collection/control execution.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'CLOSURE_GATE_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
end $$;
