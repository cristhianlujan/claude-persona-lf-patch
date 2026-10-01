-- SADM-PP-L5-022 isolated cutover 13: POST_PASE_ROUTER.
-- Materializes and promotes the already-verified applicability-only POST-PASE router.
-- Non-production only. No control execution, evidence collection, runtime/deploy or production.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-POST-PASE-ROUTER-CUTOVER-V1-20261001';
  v_source_sha constant text := '4afac31a2107c9e60b6122e5d08e6623fbfbd51e';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_LF_GOVERNANCE_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_CURRENTNESS_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='GITHUB_RECONCILIATION' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_GITHUB_RECONCILIATION_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='AUTHORITY_READBACK' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_AUTHORITY_READBACK_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='RUNTIME_DEPLOY_VERIFICATION' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_RUNTIME_VERIFY_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='FINAL_EVIDENCE' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_FINAL_EVIDENCE_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CLOSURE_GATE' and version='1.0.0') then raise exception 'BLOCK_POST_PASE_ROUTER_CUTOVER_CLOSURE_GATE_MISSING'; end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
    estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
    source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    'POST_PASE_ROUTER','POST_PASE_ROUTER_V1','ROUTER','POST_PASE_APPLICABILITY_ROUTER','GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY','VIGENTE','ACTIVO','BLOQUEADO','1.0.0',
    'sandbox/lf_contract_gate_test/post_pase_router/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','POST_PASE_ROUTER_20261001',1,
    jsonb_build_object('solution_code','POST_PASE_ROUTER_V1','work_code','SADM-PP-L4-019','target_set_event_id',19549,'mode','APPLICABILITY_ONLY_IMMUTABLE_PLAN','control_execution',false,'control_logic',false,'owner_recalculation',false,'cutover_executed',true,'runtime_authorized',false,'production_authorized',false),
    jsonb_build_object('schema_version','POST_PASE_ROUTER_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','currentness_authority','CURRENTNESS_AUTHORITY','plan_schema','LF_POST_PASE_PLAN_V1','target_capability_count',5,'registry_cutover_state','ENFORCED'),
    '8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id
  ) on conflict(codigo_activo) do update set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',raw_payload=excluded.raw_payload,metadata=excluded.metadata,updated_at=now(),updated_by_execution_id=v_execution_id;

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
   ('POST_PASE_ROUTER','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','CURRENTNESS_AUTHORITY','DEPENDE_DE','source currentness before immutable plan','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','GITHUB_RECONCILIATION','RELACIONADO_CAPACIDADES','selects bounded reconciliation scope only','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','AUTHORITY_READBACK','RELACIONADO_CAPACIDADES','selects declared authority scopes only','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','RUNTIME_DEPLOY_VERIFICATION','RELACIONADO_CAPACIDADES','selects verification only when effect scope exists','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','FINAL_EVIDENCE','RELACIONADO_CAPACIDADES','terminal evidence manifest control','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id),
   ('POST_PASE_ROUTER','CLOSURE_GATE','RELACIONADO_CAPACIDADES','terminal closure verdict control','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,v_execution_id,v_execution_id)
  on conflict do nothing;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','POST_PASE_ROUTER','version','1.0.0',
    'contract',jsonb_build_object('input','LF_POST_PASE_ROUTER_REQUEST_V1 + CURRENTNESS_RECEIPT + ORCHESTRATOR_ENTRY','output','LF_POST_PASE_PLAN_V1','authority','APPLICABILITY_ONLY_IMMUTABLE_PLAN'),
    'delivery',jsonb_build_object('mode','VERSIONED_REPOSITORY_CONSUMER','core','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_v1.py'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('CURRENTNESS_AUTHORITY','GITHUB_RECONCILIATION','AUTHORITY_READBACK','RUNTIME_DEPLOY_VERIFICATION','FINAL_EVIDENCE','CLOSURE_GATE'),'governance',jsonb_build_array('LF_GOVERNANCE','ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','control_execution',false,'control_logic',false,'owner_runner_carrier_recalculation',false,'evidence_collection',false,'plan_immutable',true,'functional_core_unchanged',true),
    'migration',jsonb_build_object('mode','ASSET_MATERIALIZATION_AND_REGISTRY_CURRENT_POINTER_CUTOVER','functional_core_change',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/post_pase_router/POST_PASE_ROUTER_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_ASSET_TO_CANDIDATE;PRESERVE_VERSION_AND_RELATIONS'),
    'usage',jsonb_build_object('core','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_v1.py','contract','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','validator','sandbox/lf_contract_gate_test/post_pase_router/test_post_pase_router_v1.py','entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha,'source_revision_immutable',true,'core_blob_sha1','8054667e225247c1b1b213d8d2ac970c33871690','test_blob_sha1','60ad1a3c3d1b58bd00d5f0689763c432a5d2483f','terminal_source_event_id',19653,'evidence_rebind_event_id',19660,'prior_deterministic_check_count',32,'target_set_event_id',19549)
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('POST_PASE_ROUTER','POST-PASE Router','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Applicability-only immutable-plan router for POST-PASE controls; never executes controls.',v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_execution_id;

  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='POST_PASE_ROUTER' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then raise exception 'POST_PASE_ROUTER_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;

  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('POST_PASE_ROUTER','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_router/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_router/test_post_pase_router_v1.py',v_execution_id)
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1('POST_PASE_ROUTER','1.0.0',null,v_execution_id,'L5 isolated POST_PASE_ROUTER cutover; applicability-only immutable plan.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'POST_PASE_ROUTER_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
end $$;
