-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M9.2 / PAULO-089
-- R16 Git-first. Existing Input Governance service release handle only.
-- Does not create a local cutover engine, domain runtime assets, functions, or a second pointer.
-- Sandbox baseline registration; no deploy or production activation.
DO $m9_2$
DECLARE
 v_e text := 'EXEC-IG-M9-2-SANDBOX-BIND-V1-20261009';
 v_manifest jsonb; v_sha text; v_result jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM transversal.decision_log WHERE adr='DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001' AND estado='VIGENTE') THEN RAISE EXCEPTION 'ADR_NOT_CURRENT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_items WHERE work_code='SADM-PP-L5-022' AND status='DONE' AND target_component='CAPABILITY_CUTOVER') THEN RAISE EXCEPTION 'CUTOVER_AUTHORITY_NOT_READY'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='EJECUCION_INPUT_GOVERNANCE_LF' AND status='SANDBOX_ACTIVE') THEN RAISE EXCEPTION 'SANDBOX_OPERATION_NOT_READY'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='INPUT_GOVERNANCE') THEN RAISE EXCEPTION 'ALREADY_REGISTERED'; END IF;
 v_manifest := jsonb_build_object(
 'schema_version','LF_CAPABILITY_MANIFEST_V1','capability_code','INPUT_GOVERNANCE','version','1.0.0',
 'contract',jsonb_build_object('operation_code','EJECUCION_INPUT_GOVERNANCE_LF','readiness','programacion.contratos/INPUT_READINESS_CONTRACT','execution','programacion.contratos/INPUT_GOVERNANCE_EXECUTION_CONTRACT','release_decision','DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001'),
 'delivery',jsonb_build_object('mode','EXISTING_GOVERNED_OPERATION_POINTER_ONLY','operation_code','EJECUCION_INPUT_GOVERNANCE_LF','runtime_inventory','public.lf_activos'),
 'installation',jsonb_build_object('required',false,'runtime_activation',false,'production_activation',false),
 'dependencies',jsonb_build_object('capabilities',jsonb_build_array('CAPABILITY_CUTOVER'),'governance',jsonb_build_array('LF_GOVERNANCE','ORCHESTRATOR_EXECUTION_GUARD_V1')),
 'compatibility',jsonb_build_object('no_domain_asset_inventory_duplication',true,'no_local_current_pointer',true,'no_new_function',true,'unknown_version','FAIL_CLOSED'),
 'migration',jsonb_build_object('mode','EXISTING_SERVICE_RELEASE_REGISTRATION_ONLY','work_code','PAULO-089','runtime_mutation',false),
 'rollback',jsonb_build_object('mode','CAPABILITY_CUTOVER_RESTORE_PREVIOUS','pointer_only',true,'preserve_history',true),
 'usage',jsonb_build_object('consumer_operation','EJECUCION_INPUT_GOVERNANCE_LF','entrypoint','existing_canonical_operation','runtime_assets_authority','public.lf_activos','readiness_authority','programacion.fn_input_readiness_run_is_current*'),
 'currentness',jsonb_build_object('authority_ref','github://cristhianlujan/claude-persona-lf-patch@d68359e80867ff32033070b681a6f5368f4a6201','source_revision_immutable',true,'runtime_change',false));
 v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_capability_registry(capability_code,capability_name,capability_kind,owner_scope,status,description,created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code)
 VALUES('INPUT_GOVERNANCE','Input Governance existing service release','TRANSVERSAL','LF_GOVERNANCE','ACTIVE','Version handle for existing governed cross-consumer service, not new domain assets or runtime.',v_e,v_e,true,'ORCHESTRATOR_EXECUTION_GUARD_V1');
 INSERT INTO public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
 VALUES('INPUT_GOVERNANCE','1.0.0',1,0,0,'RELEASED',NULL,v_manifest,v_sha,
 'github://cristhianlujan/claude-persona-lf-patch@d68359e80867ff32033070b681a6f5368f4a6201/supabase/functions/input-governance-agent-v1/index.ts',
 'github://cristhianlujan/claude-persona-lf-patch@d68359e80867ff32033070b681a6f5368f4a6201/docs/input-governance/README.md',
 'supabase://programacion.fn_engineering_current_adr_assert_v1',v_e);
 v_result := public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',NULL,v_e,'M9.2 sandbox baseline pointer only; no runtime activation.');
 IF coalesce((v_result->>'ready')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PROMOTION_REJECTED:%',v_result::text; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256=v_sha) THEN RAISE EXCEPTION 'READBACK_FAILED'; END IF;
END $m9_2$;
