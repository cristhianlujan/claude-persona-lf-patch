do $$
declare v_manifest jsonb; v_sha text;
begin
  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','EVIDENCE_LEDGER','version','1.0.0',
    'contract',jsonb_build_object('input','LF_EVIDENCE_LEDGER_ANCHOR_REQUEST_V1','output','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1','authority','DURABLE_APPEND_ONLY_EVIDENCE_ANCHOR_ONLY'),
    'delivery',jsonb_build_object('mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY','source_ref','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('EVIDENCE_RESOLVER_REGISTRY','TYPED_EVIDENCE_REGISTRY'),'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','duplicate_engine_forbidden',true),
    'migration',jsonb_build_object('mode','REGISTER_GUARDED_NOT_CURRENT','functional_core_change',false,'current_pointer_creation',false,'blocking_ekb',jsonb_build_array('CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001','S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001','S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001')),
    'rollback',jsonb_build_object('supported',true,'rule','REGISTRY_AND_OWNER_METADATA_REVERSAL_ONLY;NO_LEDGER_ROW_MUTATION'),
    'usage',jsonb_build_object('entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','implementation','public.fn_lf_evidence_ledger_anchor_v1'),
    'currentness',jsonb_build_object('authority_ref','supabase://private/lf_evidence_ledger_v1','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','current_pointer_expected',false)
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('EVIDENCE_LEDGER','Evidence Ledger','TRANSVERSAL','SUPER_ADMIN','ACTIVE','Append-only evidence ledger; registered and guarded but not current until active evidence integrity gaps are closed.','EXEC-SADM-EVIDENCE-LEDGER-CUTOVER-20260930','EXEC-SADM-EVIDENCE-LEDGER-CUTOVER-20260930',true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='SUPER_ADMIN',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=excluded.updated_by_execution_id;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('EVIDENCE_LEDGER','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_sha,'github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql','supabase://private/fn_lf_evidence_ledger_guard_v1','EXEC-SADM-EVIDENCE-LEDGER-CUTOVER-20260930')
  on conflict(capability_code,version) do nothing;
  if exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER') then raise exception 'EVIDENCE_LEDGER_UNEXPECTED_CURRENT_POINTER'; end if;
  update public.lf_activos set owner_name='SUPER_ADMIN',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('legacy_owner_name',coalesce(metadata->>'legacy_owner_name',owner_name),'registry_capability_code','EVIDENCE_LEDGER','registry_version','1.0.0','registry_manifest_sha256',v_sha,'registry_cutover_state','REGISTERED_GUARDED_NOT_CURRENT','entry_contract',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','direct_new_binding_policy','BLOCK','enforcement_state','ENTRY_ENFORCED_NOT_CURRENT','owner','SUPER_ADMIN')),
  updated_at=now(),updated_by_execution_id='EXEC-SADM-EVIDENCE-LEDGER-CUTOVER-20260930' where codigo_activo='EVIDENCE_LEDGER';
end $$;
