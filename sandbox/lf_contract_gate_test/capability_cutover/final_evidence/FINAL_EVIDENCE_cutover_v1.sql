-- SADM-PP-L5-022 isolated cutover 10: FINAL_EVIDENCE.
-- Registry/current-pointer cutover only. No evidence collection, ledger rehydration or control reexecution.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-FINAL-EVIDENCE-CUTOVER-V1-20261001';
  v_source_sha constant text := 'f5d321cd97da254adab6f8f7d3284bd55a7d91b5';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='FINAL_EVIDENCE' and archived_at is null) then raise exception 'BLOCK_FINAL_EVIDENCE_CUTOVER_ASSET_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='PLAN_AUTHORITY_DRIFT_GUARD' and version='1.0.0') then raise exception 'BLOCK_FINAL_EVIDENCE_CUTOVER_PLAN_AUTHORITY_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and version='1.1.0') then raise exception 'BLOCK_FINAL_EVIDENCE_CUTOVER_LEDGER_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_RESOLVER_REGISTRY' and version='1.0.0') then raise exception 'BLOCK_FINAL_EVIDENCE_CUTOVER_RESOLVER_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='TYPED_EVIDENCE_REGISTRY' and version='3.0.0') then raise exception 'BLOCK_FINAL_EVIDENCE_CUTOVER_TYPED_REGISTRY_MISSING'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','FINAL_EVIDENCE','version','1.0.0',
    'contract',jsonb_build_object('input','LF_CAPABILITY_EXECUTION_REQUEST_V1 + AUTHORIZED_PLAN + VERIFIED_TYPED_RECEIPT_REFS','output','LF_POST_PASE_FINAL_EVIDENCE_MANIFEST_V1','authority','BOUNDED_DETERMINISTIC_RECEIPT_REFS_AND_TERMINAL_OUTCOME_ONLY'),
    'delivery',jsonb_build_object('mode','VERSIONED_REPOSITORY_CAPABILITY','core','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_v1.py','consumer','CLOSURE_GATE'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','REPOSITORY_BOUND'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('PLAN_AUTHORITY_DRIFT_GUARD','EVIDENCE_LEDGER','EVIDENCE_RESOLVER_REGISTRY','TYPED_EVIDENCE_REGISTRY'),'governance',jsonb_build_array('LF_GOVERNANCE','ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','raw_evidence_embedded',false,'ledger_rehydration',false,'control_reexecution',false,'waived_outcome_allowed',false,'functional_core_unchanged',true),
    'migration',jsonb_build_object('mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY','functional_core_change',false,'legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/final_evidence/FINAL_EVIDENCE_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_CANDIDATE_ASSET'),
    'usage',jsonb_build_object('core','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_v1.py','contract','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','validator','sandbox/lf_contract_gate_test/post_pase_final_evidence/test_final_evidence_v1.py','entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha,'entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','source_revision_immutable',true,'core_blob_sha1','a5873b919e5668977cbae7d20ffb1ca156f7d0ad','test_blob_sha1','b811e450dbd0d7e2a9931b83cc8052ebf5a79ccf','terminal_source_event_id',19643)
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('FINAL_EVIDENCE','Final Evidence','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Bounded deterministic manifest over already-verified typed receipt references and trusted terminal outcomes.',v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_execution_id;
  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='FINAL_EVIDENCE' and version='1.0.0';
  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then raise exception 'FINAL_EVIDENCE_VERSION_1_0_0_MANIFEST_CONFLICT'; end if;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('FINAL_EVIDENCE','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,'github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_v1.py','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_final_evidence/README.md','github://cristhianlujan/claude-persona-lf-patch@'||v_source_sha||'/sandbox/lf_contract_gate_test/post_pase_final_evidence/test_final_evidence_v1.py',v_execution_id) on conflict(capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('FINAL_EVIDENCE','1.0.0',null,v_execution_id,'L5 isolated FINAL_EVIDENCE cutover; no evidence collection or control reexecution.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'FINAL_EVIDENCE_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
  update public.lf_activos set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('registry_cutover_state','ENFORCED','functional_core_unchanged',true,'raw_evidence_embedded',false,'ledger_rehydration',false,'control_reexecution',false,'registry_manifest_sha256',v_manifest_sha),updated_at=now(),updated_by_execution_id=v_execution_id where codigo_activo='FINAL_EVIDENCE' and archived_at is null;
end $$;
