do $$
declare v_manifest jsonb; v_sha text; v_promote jsonb;
begin
  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','EVIDENCE_RESOLVER_REGISTRY','version','1.0.0',
    'contract',jsonb_build_object('input','EVIDENCE_RESOLVER_LOOKUP_V1','output','TRUSTED_PROVIDER_BOUND_RESOLVER_V1','authority','TRUSTED_RESOLVER_IDENTITY_REGISTRY_ONLY'),
    'delivery',jsonb_build_object('mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY','source_ref','supabase://private/lf_evidence_resolver_registry_v1'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE'),
    'dependencies',jsonb_build_object('capabilities','[]'::jsonb,'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','duplicate_engine_forbidden',true),
    'migration',jsonb_build_object('mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY','functional_core_change',false,'current_pointer_creation',true),
    'rollback',jsonb_build_object('supported',true,'rule','REGISTRY_POINTER_AND_OWNER_METADATA_REVERSAL_ONLY'),
    'usage',jsonb_build_object('entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','implementation','private.lf_evidence_resolver_registry_v1'),
    'currentness',jsonb_build_object('authority_ref','supabase://private/lf_evidence_resolver_registry_v1','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','current_pointer_expected',true)
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
  values('EVIDENCE_RESOLVER_REGISTRY','Evidence Resolver Registry','TRANSVERSAL','SUPER_ADMIN','ACTIVE','Trusted provider-bound evidence resolver registry.','EXEC-SADM-EVIDENCE-RESOLVER-CUTOVER-20260930','EXEC-SADM-EVIDENCE-RESOLVER-CUTOVER-20260930',true,'ORCHESTRATOR_EXECUTION_GUARD_V1')
  on conflict(capability_code) do update set owner_scope='SUPER_ADMIN',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=excluded.updated_by_execution_id;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('EVIDENCE_RESOLVER_REGISTRY','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_sha,'supabase://private/lf_evidence_resolver_registry_v1','github://cristhianlujan/claude-persona-lf-patch@4b7e3bf69f472bed27dd971e4724c81af0966b8b/sandbox/lf_contract_gate_test/transversal_assets/evidence_resolver_registry/README.md','supabase://private/fn_lf_evidence_resolver_registry_immutable_v1','EXEC-SADM-EVIDENCE-RESOLVER-CUTOVER-20260930')
  on conflict(capability_code,version) do nothing;
  v_promote:=public.fn_lf_capability_promote_v1('EVIDENCE_RESOLVER_REGISTRY','1.0.0',null,'EXEC-SADM-EVIDENCE-RESOLVER-CUTOVER-20260930','Existing active shared enforcement moved under SUPER_ADMIN entry guard.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'EVIDENCE_RESOLVER_PROMOTION_BLOCKED:%',v_promote::text; end if;
  update public.lf_activos set owner_name='SUPER_ADMIN',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('legacy_owner_name',coalesce(metadata->>'legacy_owner_name',owner_name),'registry_capability_code','EVIDENCE_RESOLVER_REGISTRY','registry_version','1.0.0','registry_manifest_sha256',v_sha,'registry_cutover_state','ENFORCED','entry_contract',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED','owner','SUPER_ADMIN')),
  updated_at=now(),updated_by_execution_id='EXEC-SADM-EVIDENCE-RESOLVER-CUTOVER-20260930' where codigo_activo='EVIDENCE_RESOLVER_REGISTRY';
end $$;
