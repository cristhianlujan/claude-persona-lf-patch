-- Evidence plane registry/entry-guard cutover.
-- Active authorities remain current: EVIDENCE_RESOLVER_REGISTRY, TYPED_EVIDENCE_REGISTRY.
-- EVIDENCE_LEDGER and EVIDENCE_ANTIREPLAY are registered/guarded but intentionally NOT CURRENT
-- while active EKB gaps on source-head reanchoring, receipt cross-binding and resolver identity remain open.
-- No evidence rows are written and no runtime/deploy/production effect is activated by this projection.

do $$
declare
  v_code text;
  v_version text;
  v_major int;
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_promote jsonb;
  v_is_current boolean;
  v_rows jsonb := jsonb_build_array(
    jsonb_build_object(
      'code','EVIDENCE_RESOLVER_REGISTRY','name','Evidence Resolver Registry','version','1.0.0','major',1,
      'legacy_version','v1','active_current',true,'legacy_owner','S30',
      'kind','TRANSVERSAL','source_ref','supabase://private/lf_evidence_resolver_registry_v1',
      'docs_ref','github://cristhianlujan/claude-persona-lf-patch@4b7e3bf69f472bed27dd971e4724c81af0966b8b/sandbox/lf_contract_gate_test/transversal_assets/evidence_resolver_registry/README.md',
      'validator_ref','supabase://private/fn_lf_evidence_resolver_registry_immutable_v1',
      'contract_input','EVIDENCE_RESOLVER_LOOKUP_V1','contract_output','TRUSTED_PROVIDER_BOUND_RESOLVER_V1',
      'authority','TRUSTED_RESOLVER_IDENTITY_REGISTRY_ONLY'
    ),
    jsonb_build_object(
      'code','TYPED_EVIDENCE_REGISTRY','name','Typed Evidence Registry','version','3.0.0','major',3,
      'legacy_version','v3','active_current',true,'legacy_owner','S30',
      'kind','TRANSVERSAL','source_ref','supabase://private/lf_typed_evidence_schema_registry_v3',
      'docs_ref','github://cristhianlujan/claude-persona-lf-patch@4b7e3bf69f472bed27dd971e4724c81af0966b8b/sandbox/lf_contract_gate_test/transversal_assets/typed_evidence_registry/README.md',
      'validator_ref','supabase://private/fn_lf_typed_evidence_payload_valid_v3',
      'contract_input','TYPED_EVIDENCE_PAYLOAD_V3','contract_output','TYPED_EVIDENCE_VALIDATION_V3',
      'authority','EVIDENCE_SCHEMA_REGISTRATION_AND_VALIDATION_ONLY'
    ),
    jsonb_build_object(
      'code','EVIDENCE_LEDGER','name','Evidence Ledger','version','1.0.0','major',1,
      'legacy_version','v1','active_current',false,'legacy_owner',null,
      'kind','TRANSVERSAL','source_ref','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql',
      'docs_ref','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql',
      'validator_ref','supabase://private/fn_lf_evidence_ledger_guard_v1',
      'contract_input','LF_EVIDENCE_LEDGER_ANCHOR_REQUEST_V1','contract_output','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1',
      'authority','DURABLE_APPEND_ONLY_EVIDENCE_ANCHOR_ONLY'
    ),
    jsonb_build_object(
      'code','EVIDENCE_ANTIREPLAY','name','Evidence Anti-Replay','version','1.0.0','major',1,
      'legacy_version','v1','active_current',false,'legacy_owner',null,
      'kind','TRANSVERSAL','source_ref','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914185240_lf_evidence_ledger_subject_antireplay_v1.sql',
      'docs_ref','github://cristhianlujan/claude-persona-lf-patch@70bcce13f5b13533d23f4712678014db5a0c3d0d/supabase/migrations/20260914185240_lf_evidence_ledger_subject_antireplay_v1.sql',
      'validator_ref','supabase://private/fn_lf_evidence_ledger_guard_v1',
      'contract_input','LF_EVIDENCE_LEDGER_RECEIPT_V1','contract_output','EVIDENCE_REPLAY_ACCEPT_OR_BLOCK_V1',
      'authority','EVIDENCE_REPLAY_PREVENTION_ONLY'
    )
  );
  v_item jsonb;
begin
  for v_item in select value from jsonb_array_elements(v_rows) loop
    v_code := v_item->>'code';
    v_version := v_item->>'version';
    v_major := (v_item->>'major')::int;
    v_is_current := (v_item->>'active_current')::boolean;

    v_manifest := jsonb_build_object(
      'schema_version','LF_CAPABILITY_MANIFEST_V1',
      'capability_code',v_code,
      'version',v_version,
      'contract',jsonb_build_object(
        'input',v_item->>'contract_input',
        'output',v_item->>'contract_output',
        'authority',v_item->>'authority'
      ),
      'delivery',jsonb_build_object(
        'mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY',
        'source_ref',v_item->>'source_ref',
        'consumer_state',case when v_is_current then 'ENTRY_GUARD_CUTOVER_CURRENT' else 'REGISTERED_GUARDED_NOT_CURRENT' end
      ),
      'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE'),
      'dependencies',jsonb_build_object(
        'capabilities',case when v_code='EVIDENCE_LEDGER' then jsonb_build_array('EVIDENCE_RESOLVER_REGISTRY','TYPED_EVIDENCE_REGISTRY') else '[]'::jsonb end,
        'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1')
      ),
      'compatibility',jsonb_build_object(
        'unknown_state','FAIL_CLOSED',
        'duplicate_engine_forbidden',true,
        'legacy_surface_preserved',true
      ),
      'migration',jsonb_build_object(
        'mode','REGISTRY_ENTRY_GUARD_CUTOVER_ONLY',
        'functional_core_change',false,
        'current_pointer_creation',v_is_current,
        'blocking_ekb',case when v_code in ('EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY') then jsonb_build_array('CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001','S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001','S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001') else '[]'::jsonb end
      ),
      'rollback',jsonb_build_object('supported',true,'rule','REGISTRY_POINTER_AND_OWNER_METADATA_REVERSAL_ONLY;NO_EVIDENCE_DATA_MUTATION'),
      'usage',jsonb_build_object(
        'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'source_ref',v_item->>'source_ref',
        'validator_ref',v_item->>'validator_ref'
      ),
      'currentness',jsonb_build_object(
        'authority_ref',v_item->>'source_ref',
        'entry_guard_required',true,
        'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'current_pointer_expected',v_is_current,
        'production_authorized',false
      )
    );
    v_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

    insert into public.lf_capability_registry(
      capability_code,capability_name,capability_kind,owner_scope,status,description,
      created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
    ) values (
      v_code,v_item->>'name',v_item->>'kind','SUPER_ADMIN','ACTIVE',
      format('%s governed by SUPER_ADMIN; entry requires ORCHESTRATOR_EXECUTION_GUARD_V1.',v_item->>'name'),
      'EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930','EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930',true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
    ) on conflict (capability_code) do update set
      capability_name=excluded.capability_name,capability_kind=excluded.capability_kind,
      owner_scope='SUPER_ADMIN',status='ACTIVE',description=excluded.description,
      entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
      updated_at=now(),updated_by_execution_id=excluded.updated_by_execution_id;

    select manifest_sha256 into v_existing
    from public.lf_capability_version_registry
    where capability_code=v_code and version=v_version;
    if v_existing is not null and v_existing <> v_sha then
      raise exception 'EVIDENCE_PLANE_MANIFEST_CONFLICT:%:%',v_code,v_version;
    end if;

    insert into public.lf_capability_version_registry(
      capability_code,version,version_major,version_minor,version_patch,release_state,
      supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
    ) values (
      v_code,v_version,v_major,0,0,'RELEASED',null,v_manifest,v_sha,
      v_item->>'source_ref',v_item->>'docs_ref',v_item->>'validator_ref',
      'EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930'
    ) on conflict (capability_code,version) do nothing;

    if v_is_current then
      v_promote := public.fn_lf_capability_promote_v1(
        v_code,v_version,null,'EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930',
        'Existing active shared enforcement projected under SUPER_ADMIN + shared orchestrator entry guard.'
      );
      if coalesce((v_promote->>'ready')::boolean,false) is not true then
        raise exception 'EVIDENCE_PLANE_CURRENT_POINTER_BLOCKED:%:%',v_code,v_promote::text;
      end if;
    else
      if exists(select 1 from public.lf_capability_current where capability_code=v_code) then
        raise exception 'EVIDENCE_PLANE_UNEXPECTED_CURRENT_POINTER:%',v_code;
      end if;
    end if;

    update public.lf_activos
    set owner_name='SUPER_ADMIN',
        metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
          'legacy_owner_name',coalesce(metadata->>'legacy_owner_name',owner_name),
          'registry_capability_code',v_code,
          'registry_version',v_version,
          'registry_manifest_sha256',v_sha,
          'registry_cutover_state',case when v_is_current then 'ENFORCED' else 'REGISTERED_GUARDED_NOT_CURRENT' end,
          'entry_contract',jsonb_build_object(
            'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,
            'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
            'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
            'direct_new_binding_policy','BLOCK',
            'enforcement_state',case when v_is_current then 'ENFORCED' else 'ENTRY_ENFORCED_NOT_CURRENT' end,
            'owner','SUPER_ADMIN',
            'updated_by_execution_id','EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930'
          )
        ),
        updated_at=now(),updated_by_execution_id='EXEC-SADM-EVIDENCE-PLANE-REGISTRY-CUTOVER-20260930'
    where codigo_activo=v_code;
    if not found then raise exception 'EVIDENCE_PLANE_LF_ACTIVOS_MISSING:%',v_code; end if;
  end loop;
end;
$$;
