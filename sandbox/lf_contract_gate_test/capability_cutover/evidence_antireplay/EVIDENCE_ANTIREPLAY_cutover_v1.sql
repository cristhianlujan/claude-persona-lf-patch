-- SADM-PP-L5-022 isolated cutover 08: EVIDENCE_ANTIREPLAY.
-- Promotes the already-applied anti-replay/cross-bind guard as v1.1.0.
-- No ledger-row mutation, runtime/deploy/production, or bulk cutover.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-EVIDENCE-ANTIREPLAY-CUTOVER-V1-20261001';
  v_source_sha constant text := '407600b295781fcf065e89d4da0d447a957c58f0';
  v_manifest jsonb; v_manifest_sha text; v_existing_sha text; v_promote jsonb;
begin
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and version='1.1.0') then raise exception 'BLOCK_EVIDENCE_ANTIREPLAY_LEDGER_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_RESOLVER_REGISTRY' and version='1.0.0') then raise exception 'BLOCK_EVIDENCE_ANTIREPLAY_RESOLVER_NOT_CURRENT'; end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20260930133539' and encode(extensions.digest(convert_to(statements[1],'UTF8'),'sha256'),'hex')='7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a') then raise exception 'BLOCK_EVIDENCE_ANTIREPLAY_HARDENING_SOURCE_MISMATCH'; end if;
  if md5(pg_get_functiondef('private.fn_lf_evidence_ledger_guard_v1()'::regprocedure)) <> '2eba89c4c6c87904205564d39994f2e5' then raise exception 'BLOCK_EVIDENCE_ANTIREPLAY_GUARD_DRIFT'; end if;

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','EVIDENCE_ANTIREPLAY','version','1.1.0',
    'contract',jsonb_build_object('input','LF_EVIDENCE_LEDGER_APPEND_ATTEMPT_V1','output','ANTI_REPLAY_DECISION_V1','authority','EVIDENCE_LEDGER_COMPOSITION_CROSSBIND_AND_UNIQUE_DIGEST_ONLY'),
    'delivery',jsonb_build_object('mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY','source_ref','supabase://private/fn_lf_evidence_ledger_guard_v1'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE_ALREADY_APPLIED'),
    'dependencies',jsonb_build_object('capabilities',jsonb_build_array('EVIDENCE_LEDGER','EVIDENCE_RESOLVER_REGISTRY'),'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1','LF_GOVERNANCE')),
    'compatibility',jsonb_build_object('unknown_state','FAIL_CLOSED','duplicate_engine_forbidden',true,'ledger_rows_untouched',true),
    'migration',jsonb_build_object('mode','CURRENT_POINTER_CUTOVER_OVER_ALREADY_APPLIED_HARDENING','functional_core_change',false,'hardening_migration_version','20260930133539','hardening_statement_sha256','7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a','legacy_retirement',false,'work_code','SADM-PP-L5-022'),
    'rollback',jsonb_build_object('supported',true,'script','sandbox/lf_contract_gate_test/capability_cutover/evidence_antireplay/EVIDENCE_ANTIREPLAY_cutover_rollback_v1.sql','rule','REMOVE_EXACT_CURRENT_POINTER_AND_RESTORE_OWNER_METADATA;NEVER_MUTATE_LEDGER_ROWS'),
    'usage',jsonb_build_object('entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','implementation','private.fn_lf_evidence_ledger_guard_v1'),
    'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql','entry_guard_required',true,'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','source_revision_immutable',true,'guard_md5','2eba89c4c6c87904205564d39994f2e5'));
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  update public.lf_capability_registry set owner_scope='LF_GOVERNANCE',status='ACTIVE',entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',description='Anti-replay and exact composition cross-binding enforcement for Evidence Ledger writes.',updated_at=now(),updated_by_execution_id=v_execution_id where capability_code='EVIDENCE_ANTIREPLAY';
  if not found then raise exception 'BLOCK_EVIDENCE_ANTIREPLAY_REGISTRY_MISSING'; end if;
  select manifest_sha256 into v_existing_sha from public.lf_capability_version_registry where capability_code='EVIDENCE_ANTIREPLAY' and version='1.1.0';
  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then raise exception 'EVIDENCE_ANTIREPLAY_VERSION_1_1_0_MANIFEST_CONFLICT'; end if;
  insert into public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  values('EVIDENCE_ANTIREPLAY','1.1.0',1,1,0,'RELEASED','1.0.0',v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch@' || v_source_sha || '/sandbox/lf_contract_gate_test/transversal_assets/evidence_plane/EVIDENCE_ANTIREPLAY_registry_projection_v1.sql',
    'supabase://private/fn_lf_evidence_ledger_guard_v1',v_execution_id)
  on conflict(capability_code,version) do nothing;
  v_promote := public.fn_lf_capability_promote_v1('EVIDENCE_ANTIREPLAY','1.1.0',null,v_execution_id,'L5 isolated anti-replay current-pointer cutover over already-applied hardening.');
  if coalesce((v_promote->>'ready')::boolean,false) is not true then raise exception 'EVIDENCE_ANTIREPLAY_CURRENT_POINTER_BLOCKED:%',v_promote::text; end if;
  update public.lf_activos set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.1.0',owner_name='LF_GOVERNANCE',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('administrative_owner','LF_GOVERNANCE','registry_capability_code','EVIDENCE_ANTIREPLAY','registry_version','1.1.0','registry_manifest_sha256',v_manifest_sha,'registry_cutover_state','ENFORCED','ledger_rows_mutated',false,'hardening_migration_version','20260930133539'),updated_at=now(),updated_by_execution_id=v_execution_id where codigo_activo='EVIDENCE_ANTIREPLAY' and archived_at is null;
  if not found then raise exception 'EVIDENCE_ANTIREPLAY_ASSET_UPDATE_MISSING'; end if;
  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
  values('EVIDENCE_ANTIREPLAY','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative ownership after hardening/current cutover','sandbox/lf_contract_gate_test/capability_cutover/evidence_antireplay/evidence_antireplay_cutover_inventory_v1.json','8c1d2f6c-4a1c-4f80-9d5d-022000000008'::uuid,v_execution_id,v_execution_id) on conflict do nothing;
end $$;
