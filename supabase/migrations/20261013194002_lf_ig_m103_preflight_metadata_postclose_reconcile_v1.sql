-- M10.3 post-close readback of universal-preflight metadata vs actual ledger.
-- Fix stale indicators left by the initial contract repair:
-- NOT_VERIFIED, NOT_YET_AUTHORED, NOT_YET_VERIFIED, provider-readback pending.
-- It does NOT retroactively claim APTO_PARA_EJECUTAR before CP1.
-- Only M10.3 metadata and one EKB entry; checkpoint statuses unchanged.
DO $m103_reconcile$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 u constant text := 'M10.3';
 v_md jsonb; w bigint; v_assert text; v_run uuid; v_case bigint;
 v_cur_version text; v_cur_sha text;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT w,v_md
 FROM programacion.engineering_plan_units WHERE plan_code=p AND unit_code=u
 FOR UPDATE;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'DONE'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=w AND status='DONE')<>5
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=w)<>5
 THEN RAISE EXCEPTION 'M103_METADATA_RECONCILE_NOT_CLOSED'; END IF;
 IF v_md#>>'{m103_contract_governance_v1,phase}'<>'CONSTRUCTION_SANDBOX'
 OR v_md#>>'{m103_contract_governance_v1,operational_cutover_executed}'<>'false'
 OR v_md#>>'{m103_contract_governance_v1,preflight_status}'<>'NOT_VERIFIED'
 THEN RAISE EXCEPTION 'M103_METADATA_RECONCILE_UNEXPECTED_PRESTATE'; END IF;

 SELECT assertion_receipt_sha256 INTO v_assert
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=w AND checkpoint_code='ROLLBACK_DRILL'
  AND status='DONE' AND assertion_receipt->>'passed'='true';
 IF v_assert IS NULL THEN RAISE EXCEPTION 'M103_METADATA_CP3_ASSERTION_MISSING'; END IF;
 SELECT s.suite_run_id INTO v_run
 FROM public.lf_test_suite_runs s
 WHERE s.suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND s.metadata->>'unit_code'=u
  AND s.metadata->>'checkpoint_code'='ROLLBACK_SUITE'
  AND s.status='PASSED' AND s.tests_total=1 AND s.tests_passed=1
  AND s.tests_failed=0
  AND s.metadata->>'full_catalog_evaluated'='false'
  AND s.metadata->>'source_assertion_sha256'=v_assert
 ORDER BY s.created_at DESC LIMIT 1;
 IF v_run IS NULL THEN RAISE EXCEPTION 'M103_METADATA_CP4_SUITE_NOT_VERIFIED'; END IF;
 SELECT count(*) INTO v_case FROM public.lf_test_runs
 WHERE suite_run_id=v_run AND test_code='ENG_M10_3_ROLLBACK_DRILL' AND status='PASS';
 IF v_case<>1 THEN RAISE EXCEPTION 'M103_METADATA_CP4_CASE_NOT_BOUND'; END IF;

 SELECT c.version,c.manifest_sha256 INTO STRICT v_cur_version,v_cur_sha
 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r USING(capability_code,version)
 WHERE c.capability_code='INPUT_GOVERNANCE' AND c.version='1.0.0'
 AND c.previous_version IS NULL AND c.manifest_sha256=r.manifest_sha256
 AND r.release_state='RELEASED';
 IF (SELECT count(*) FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE')<>1
 THEN RAISE EXCEPTION 'M103_METADATA_SOURCE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M103-OPERATIONAL-CUTOVER-SANDBOX-CONFLATION-001'
  AND root_cause_family='R4_NO_CUESTIONA')
 THEN RAISE EXCEPTION 'M103_METADATA_ORIGINAL_EKB_MISSING'; END IF;

 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,preflight_status}',
   '"AUDIT_APPLIED_AND_RECONCILED_POST_EXECUTION"'::jsonb,true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,cp1_edge_validation}',
   '"PROVIDER_LIST_READBACK_VERIFIED_SNAPSHOT"'::jsonb,true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,cp1_edge_snapshot}',
   jsonb_build_object('observation_source','Supabase list_edge_functions, 2026-10-13',
     'deployed_not_equal_active_traffic',true,
     'curator',jsonb_build_object('slug','input-governance-curator-v1',
       'version',14,'status','ACTIVE','sha256','31fff4bc573c6832f7c3ce53c783c31b735ead263e3262af5d43b3a7b64b3d5c'),
     'validator',jsonb_build_object('slug','input-governance-validator-v1',
       'version',18,'status','ACTIVE','sha256','57bfa7fcf19002378a5f1ffcdd3f3777223a4c8ca3417df8220b55c996e59a77'),
     'agent',jsonb_build_object('slug','input-governance-agent-v1',
       'version',17,'status','ACTIVE','sha256','95977bfd7be64aef68a4c18c2e7fe15914aa510bcc1c1ee668863068cc5e656c')),true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,cp3_test_artifact}',
   '"github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_3/rollback_drill.py"'::jsonb,true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,cp4_suite_run}',
   to_jsonb('supabase://public.lf_test_suite_runs/'||v_run::text),true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,cp4_suite_scope}',
   jsonb_build_object('status','PASSED','cases_passed',1,'cases_total',1,
     'full_catalog_evaluated',false,'source_assertion_sha256',v_assert,
     'result_origin','REUSED_VERIFIED_REAL_EXECUTION'),true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,preflight_controls_reconciled}',
   jsonb_build_object('EKB','PASS','NATURE','PASS','CONTRACT','PASS',
     'CHECKPOINTS','PASS','DOCUMENTATION','N/A',
     'GOVERNANCE','PASS','RULES_VALIDATORS','PASS',
     'DEPENDENCIES_EVIDENCE','PASS','TECHNICAL_EXECUTION','PASS',
     'applicable',8,'verified',8,
     'verification_timing','POST_EXECUTION_RECONCILIATION',
     'not_retroactive_pre_execution_admission',true),true);
 v_md:=jsonb_set(v_md,
   '{m103_contract_governance_v1,final_reconciliation}',
   jsonb_build_object('checkpoint_count',5,'done',5,'work_status','DONE',
     'current_version',v_cur_version,'current_manifest_sha256',v_cur_sha,
     'operational_cutover_executed',false,'retirement_executed',false,
     'post_operational_zero_traffic_proven',false),true);

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_md
 WHERE plan_code=p AND unit_code=u;
 IF NOT FOUND THEN RAISE EXCEPTION 'M103_METADATA_UPDATE_NOT_APPLIED'; END IF;

 INSERT INTO transversal.error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
  estado,evidencia,created_at,updated_at,root_cause_family,source_ref)
 SELECT gen_random_uuid(),'IG-M103-STALE-PREFLIGHT-METADATA-001',
  'ENGINEERING_GOVERNANCE','Marcadores auxiliares M10.3 obsoletos al llegar a 100%',
  'Tras cerrarse CP1..CP5 quedaron preflight_status NOT_VERIFIED, artefacto NOT_YET_AUTHORED, suite NOT_YET_VERIFIED y Edge pending, aunque el ledger y pruebas canónicas estaban cerrados.',
  'El flujo de cierre actualizó checkpoints pero no reconciliaba los indicadores auxiliares del contrato; peligro de diagnósticos contradictorios en sesiones futuras.',
  'POST_CLOSE_DERIVED_METADATA_NOT_RECONCILED',
  'Incluir readback de todos los marcadores auxiliares contra evidencia canónica al cerrar cualquier unidad; registrar observaciones temporales por su fuente y no inventar aprobación pre-ejecución.',
  'Comparar metadata de M10.3 contra cp1 source, cp3 assertion SHA, cp4 scoped suite run y cinco DONE; no alterar permisos ni estado de checkpoints.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.3','ACTIVO',
  'M10.3 5/5 DONE; cp3 real assertion; cp4 suite 1/1 scoped; three provider Edge versions observed.',
  clock_timestamp(),clock_timestamp(),
  'R5_EROSION_PROCESO',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.3'
 WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M103-STALE-PREFLIGHT-METADATA-001');

 IF (SELECT unit_metadata#>>'{m103_contract_governance_v1,preflight_status}'
 FROM programacion.engineering_plan_units WHERE plan_code=p AND unit_code=u)
 <>'AUDIT_APPLIED_AND_RECONCILED_POST_EXECUTION'
 OR NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M103-STALE-PREFLIGHT-METADATA-001')
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'DONE'
 THEN RAISE EXCEPTION 'M103_METADATA_RECONCILE_READBACK_FAILED'; END IF;
END $m103_reconcile$;