-- SADM-PP-L5-022 isolated cutover 07: EVIDENCE_LEDGER.
-- Promotes the already-applied cross-bind-hardened ledger as v1.1.0.
-- No ledger-row mutation, no runtime/deploy/production, no bulk cutover.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-EVIDENCE-LEDGER-CUTOVER-V1-20261001';
  v_source_sha constant text := 'e025d977186b4c2fa253f1458dc178cfc8eafdda';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_RESOLVER_REGISTRY' and version='1.0.0') then raise exception 'BLOCK_EVIDENCE_LEDGER_RESOLVER_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='TYPED_EVIDENCE_REGISTRY' and version='3.0.0') then raise exception 'BLOCK_EVIDENCE_LEDGER_TYPED_REGISTRY_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_EVIDENCE_LEDGER_LF_GOVERNANCE_MISSING'; end if;
  if to_regprocedure('public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)') is null then raise exception 'BLOCK_EVIDENCE_LEDGER_ANCHOR_MISSING'; end if;
  if to_regprocedure('private.fn_lf_evidence_ledger_guard_v1()') is null then raise exception 'BLOCK_EVIDENCE_LEDGER_GUARD_MISSING'; end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20260930133539' and encode(extensions.digest(convert_to(statements[1],'UTF8'),'sha256'),'hex')='7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a') then raise exception 'BLOCK_EVIDENCE_LEDGER_HARDENING_SOURCE_MISMATCH'; end if;
  if md5(pg_get_functiondef('private.fn_lf_evidence_ledger_guard_v1()'::regprocedure)) <> '2eba89c4c6c87904205564d39994f2e5' then raise exception 'BLOCK_EVIDENCE_LEDGER_GUARD_DRIFT'; end if;
  if md5(pg_get_functiondef('public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)'::regprocedure)) <> 'fde5b4db6af6b3566a93906c27e01c39' then raise exception 'BLOCK_EVIDENCE_LEDGER_ANCHOR_DRIFT'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','EVIDENCE_LEDGER','version','1.1.0',
    'contract',jsonb_build_object('input','LF_EVIDENCE_LEDGER_ANCHOR_REQUEST_V1','output','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1','authority','DURABLE_APPEND_ONLY_CROSS_BOUND_EVIDENCE_ANCHOR_ONLY'),
    'delivery',jsonb_build_object('mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY','implementation','public.fn_lf_evidence_ledger_anchor_v1','guard','private.fn_lf_evidence_ledger_guard_v1'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE_ALREADY_APPLIED'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('EVIDENCE_RESOLVER_REGISTRY','TYPED_EVIDENCE_REGISTRY'),'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1','LF_GOVERNANCE')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','append_only',true,'duplicate_engine_forbidden',true,'existing_rows_untouched',true),
    'migration',jsonb_build_object('mode','CURRENT_POINTER_CUTOVER_OVER_ALREADY_APPLIED_HARDENING','functional_core_change',false,'hardening_migration_version','20260930133539','hardening_statement_sha256','7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a','legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/evidence_ledger/EVIDENCE_LEDGER_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_OWNER_METADATA;NEVER_MUTATE_LEDGER_ROWS'),
    'usage',jsonb_build_object('entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','implementation','public.fn_lf_evidence_ledger_anchor_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','source_revision_immutable',true,'guard_md5','2eba89c4c6c87904205564d39994f2e5','anchor_md5','fde5b4db6af6b3566a93906c27e01c39')
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  update public.lf_capability_registry
  set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',description='Append-only cross-bound evidence ledger with exact orchestrator/producer/resolver/currentness binding.',updated_at=now(),updated_by_execution_id=v_execution_id
  where capability_code='EVIDENCE_LEDGER';
  if not found then raise exception 'BLOCK_EVIDENCE_LEDGER_REGISTRY_MISSING'; end if;

  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='EVIDENCE_LEDGER' and version='1.1.0';
  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then raise exception 'EVIDENCE_LEDGER_VERSION_1_1_0_MANIFEST_CONFLICT'; end if;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('EVIDENCE_LEDGER','1.1.0',1,1,0,'RELEASED','1.0.0',v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/transversal_assets/evidence_plane/EVIDENCE_LEDGER_registry_projection_v1.sql',
    'supabase://private/fn_lf_evidence_ledger_guard_v1',v_execution_id)
  on conflict(capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1('EVIDENCE_LEDGER','1.1.0',null,v_execution_id,'L5 isolated promotion after evidence cross-bind/currentness/replay/resolver blockers were closed; no ledger-row mutation.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'EVIDENCE_LEDGER_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;

  update public.lf_activos
  set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.1.0',owner_name='LF_GOVERNANCE',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('administrative_owner','LF_GOVERNANCE','registry_capability_code','EVIDENCE_LEDGER','registry_version','1.1.0','registry_manifest_sha256',v_manifest_sha,'registry_cutover_state','ENFORCED','ledger_rows_mutated',false,'hardening_migration_version','20260930133539','entry_contract',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED','owner','LF_GOVERNANCE')),updated_at=now(),updated_by_execution_id=v_execution_id
  where codigo_activo='EVIDENCE_LEDGER' and archived_at is null;
  if not found then raise exception 'EVIDENCE_LEDGER_ASSET_UPDATE_MISSING'; end if;

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
  values('EVIDENCE_LEDGER','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative ownership after hardening/current cutover','sandbox/lf_contract_gate_test/capability_cutover/evidence_ledger/evidence_ledger_cutover_inventory_v1.json','8c1d2f6c-4a1c-4f80-9d5d-022000000007'::uuid,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
