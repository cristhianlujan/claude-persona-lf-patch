-- LF / M10.5 / CP2 - one-screen-first validation without mandatory version change.
-- Git -> LF Migration Merge Train -> exact DB apply -> ledger/readback.
-- Does not promote INPUT_GOVERNANCE, deploy Edge, issue receipts or change any release pointer.
-- Historical checkpoint code NEW_RUNS_VNEXT remains for referential compatibility.
BEGIN;
DO $guard$
DECLARE old_view text;
BEGIN
 SELECT pg_get_viewdef('programacion.v_ig_m105_cp2_verdict_v1'::regclass,true) INTO old_view;
 IF old_view NOT LIKE '%fresh_vnext%' OR old_view NOT LIKE '%release_bound%'
    OR old_view NOT LIKE '%PASS_CP2%' THEN
  RAISE EXCEPTION 'CP2_EXPECTED_LEGACY_VERDICT_CONTRACT_NOT_FOUND';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
    AND c.checkpoint_code='NEW_RUNS_VNEXT' AND c.status='PENDING'
 ) THEN RAISE EXCEPTION 'CP2_CHECKPOINT_STATE_DRIFT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM lf_ops.pantallas WHERE id=1 AND codigo='ONB_001')
 THEN RAISE EXCEPTION 'CP2_PILOT_SCREEN_IDENTITY_DRIFT'; END IF;
END $guard$;

-- Preserve existing view columns/order for current consumers. The 13-screen
-- checkpoint still requires independent closure; each individual screen may pass first.
CREATE OR REPLACE VIEW programacion.v_ig_m105_cp2_verdict_v1
WITH (security_invoker=true) AS
WITH e AS (
 SELECT v.pantalla_id,v.run_id,v.run_status,v.created_at,v.family_count,
        v.release_version,v.previous_version,v.release_manifest_sha256,
        v.fresh_vnext,v.source_current,v.edge_identities,v.release_bound,
        v.agent_edge_receipt,v.family_rows,v.assessed_rows,v.classifiable_rows,
        v.observations,v.validator_failures,v.validator_elapsed_ms,
        p.codigo AS screen_code,
        (SELECT count(*) FROM programacion.input_family_assessments a
         WHERE a.run_id=v.run_id AND a.validator_outcome IN ('PASS','FAIL','BLOCKED')) AS final_decisions,
        (SELECT count(*) FROM programacion.input_family_assessments a
         WHERE a.run_id=v.run_id AND a.validator_outcome='FAIL') AS semantic_rejections,
        (SELECT count(*) FROM programacion.input_family_assessments a
         WHERE a.run_id=v.run_id AND (
          a.production_ready_status IN ('BLOCKED','NOT_READY','PENDING')
          OR a.validator_outcome='BLOCKED' OR a.applicability='UNRESOLVED')) AS evaluation_holds,
        (SELECT count(*) FROM programacion.input_family_assessments a
         WHERE a.run_id=v.run_id AND a.applicability='NOT_APPLICABLE') AS not_applicable_decisions,
        (SELECT count(*) FROM programacion.input_family_assessments a
         WHERE a.run_id=v.run_id AND (
          a.validator_outcome IS NULL OR a.validator_outcome='PENDING'
          OR a.validator_identity IS NULL OR a.validator_sha256 IS NULL
          OR jsonb_typeof(a.validator_findings) IS DISTINCT FROM 'array')) AS invalid_decisions
 FROM programacion.v_ig_m105_cohort_evidence_v1 v
 JOIN lf_ops.pantallas p ON p.id=v.pantalla_id
),t AS (
 SELECT e.*,
  CASE WHEN e.run_id IS NULL THEN 'NOT_RUN'
   WHEN e.run_status IN ('CURATING','VALIDATING','BLOCKED') THEN 'IN_PROGRESS_OR_POLICY_HOLD'
   WHEN e.run_status IS DISTINCT FROM 'COMPLETED' OR e.family_count<1
    OR e.family_rows<>e.family_count OR e.assessed_rows<>e.family_count
    OR e.classifiable_rows<>e.family_count
    OR e.final_decisions<>e.family_count OR e.invalid_decisions>0
    THEN 'ERROR_TECNICO'
   ELSE 'PASS_TECNICO' END AS technical_verdict
 FROM e
)
SELECT pantalla_id,run_id,run_status,created_at,family_count,
 release_version,previous_version,release_manifest_sha256,
 fresh_vnext,source_current,edge_identities,release_bound,
 agent_edge_receipt,family_rows,assessed_rows,classifiable_rows,
 observations,validator_failures,validator_elapsed_ms,screen_code,
 final_decisions,semantic_rejections,evaluation_holds,
 not_applicable_decisions,invalid_decisions,technical_verdict,
 CASE WHEN run_id IS NULL THEN 'NO_EJECUCION_VIGENTE'
  WHEN technical_verdict='ERROR_TECNICO' THEN 'ERROR_TECNICO'
  WHEN technical_verdict<>'PASS_TECNICO' THEN 'EN_EVALUACION_NO_ERROR'
  WHEN NOT coalesce(source_current,false) THEN 'NO_EJECUCION_VIGENTE'
  ELSE 'PASS_CP2'
 END AS cp2_verdict
FROM t;

-- Align CP2 work-item, checkpoint, current-source test and governance together.
DO $contract$
DECLARE v_meta jsonb;
BEGIN
 SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 v_meta:=replace(v_meta::text,'cp2_not_executed_count','cp2_not_current_count')::jsonb;
 v_meta:=replace(v_meta::text,'NO_EJECUTADO_VNEXT','NO_EJECUCION_VIGENTE')::jsonb;
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,runner_ref}',
  to_jsonb('cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-input-governance-recurate.yml'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,runner_mode}',
  to_jsonb('CURRENT_RECURATION_CP2_MODE_FALSE_ONE_SCREEN'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_validation_contract_v3,phase}',
  to_jsonb('CURRENT_SOURCE_SCREEN_EVALUATION'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_validation_contract_v3,execution_gate}',
  to_jsonb('COMPLETE_SOURCE_CURRENT_RUN_NO_VNEXT_REQUIRED'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_governance_v1,version_change_required}','false'::jsonb,true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_governance_v1,pilot_screen_id}','1'::jsonb,true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,runtime}',
  to_jsonb('EXISTING_GOVERNED_INPUT_READINESS_RECURATION'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,executor_path}',
  to_jsonb('cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-input-governance-recurate.yml'::text),true);
 v_meta:=v_meta #- '{m105_cp2_producer_v1,release_authority}';
 v_meta:=v_meta #- '{m105_cp2_producer_v1,dispatch_context_rpc}';
 v_meta:=v_meta #- '{m105_cp2_producer_v1,receipt_issuer}';
 v_meta:=v_meta #- '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_sha256}';
 v_meta:=v_meta #- '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,attestation_rpc}';
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_path}',
  to_jsonb('cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-input-governance-recurate.yml'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_status}',
  to_jsonb('EXISTING_RECURATION_PRODUCER_READY_FOR_SINGLE_SCREEN'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,release_gate}',
  to_jsonb('CURRENT_SOURCE_RUN_NO_PROMOTION_REQUIRED'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,requires_real_promotion}','false'::jsonb,true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,execution_route}',
  to_jsonb('EXISTING_INPUT_READINESS_RECURATION_ONE_SCREEN_THEN_READBACK'::text),true);
 v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_v1,execution_status}',
  to_jsonb('PENDING_ONE_SCREEN_FRESH_EXECUTION'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_scope_contract,release}',
  to_jsonb('CURRENT_INPUT_GOVERNANCE_NO_NEW_RELEASE'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_scope_contract,proof_phase}',
  to_jsonb('CURRENT_SOURCE_SCREEN_EVALUATION'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,expected}',
  to_jsonb('First one genuine source-current ONB_001 run and its canonical CP2 readback; later the remaining cohort screens. Semantic holds/rejections are evaluator outcomes, not engine errors.'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,router_mode}',
  to_jsonb('EXISTING_GOVERNED_RECURATION_THEN_CANONICAL_READBACK'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,canonical_exit_criterion}',
  to_jsonb('13 source-current evaluated screens eventually; first verify ONB_001 PASS_CP2 without a new release or runtime deployment. Reject stale and incomplete runs.'::text),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}',
  (v_meta#>'{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}')
    - 'release_bound_count' - 'edge_provenance_receipt_count' - 'cp2_not_executed_count'
      || jsonb_build_object('source_current_count',13,'cp2_not_current_count',0),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta,
  title='M10.5 — Evaluacion vigente de pantallas: piloto ONB_001 primero',
  exit_criterion='ONB_001 fresh source-current execution with 100% families classified and PASS_CP2 first, then 13/13 current cohort runs, semantic regression, performance, stale negative and terminal readback; no INPUT_GOVERNANCE version promotion needed'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5';
 UPDATE programacion.engineering_work_checkpoints SET
  title='Ejecutar primero CP2 de ONB_001 con fuentes vigentes; luego las otras 12 pantallas'
 WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5')
  AND checkpoint_code='NEW_RUNS_VNEXT' AND status='PENDING';
 UPDATE programacion.engineering_work_items SET
  title='M10.5 — Validacion E2E con fuentes vigentes (sin nuevo release)',
  objective='Evaluar ONB_001 y luego el resto de la cohorte actual, sin crear ni promover un nuevo release',
  expected_result='One genuine source-current ONB_001 PASS_CP2 first; then 13/13 authenticated current-source runs with semantic regression, timings and stale negative readback',
  acceptance_criteria=jsonb_build_array(
   'ONB_001 first: fresh current-source run; all family decisions complete, valid and classifiable; canonical PASS_CP2',
   'Then 13/13 source-current evaluated runs, no Input Governance version migration',
   'Semantic rejects, holds, review and N/A classified without technical execution error',
   'M7 semantic suite and M8 performance bound to actual run IDs',
   'Negative stale/incomplete runs rejected, exact final readback')
 WHERE id=(SELECT work_item_id FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5')
 AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'CP2_WORK_ITEM_NOT_IN_PROGRESS'; END IF;
END $contract$;

-- Operational EKB. Not an optional local note.
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,severidad,
 estado,lote_origen,source_context,source_ref)
SELECT
 'IG-M105-CP2-UNNECESSARY-RELEASE-GATE-017','GOVERNANCE',
 'CP2 de pantalla dependia innecesariamente de publicar otra version de Input Governance',
 'Separa PASS individual por fuente vigente de proceso de cutover. Conserva semantica y ejecucion real.',
 'Veredicto CP2 confundia evaluacion funcional de pantalla con prueba operacional de despliegue vNext.',
 'Nunca requerir un release ni HUMAN_AUTHORITY_V1 para evaluar una pantalla con el ejecutor existente. Rechazar run viejo e incompleto. Solo PASS desde readback real.',
 'Validar positivo y negativos sobre vista y ejecutar ONB_001 por ruta existente; nunca aceptar run 825 desactualizado.',
 'ALTA','ACTIVO','M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'supabase://programacion.v_ig_m105_cp2_verdict_v1'
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M105-CP2-UNNECESSARY-RELEASE-GATE-017');

-- Negative assertion, not synthetic PASS.
DO $post$
BEGIN
 IF EXISTS (SELECT 1 FROM programacion.v_ig_m105_cp2_verdict_v1
   WHERE pantalla_id=1 AND NOT source_current AND cp2_verdict='PASS_CP2')
 THEN RAISE EXCEPTION 'CP2_STALE_RUN_WRONGLY_PASSED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.v_ig_m105_cp2_verdict_v1
   WHERE pantalla_id=1 AND run_id=825 AND cp2_verdict='NO_EJECUCION_VIGENTE')
 THEN RAISE EXCEPTION 'CP2_STALE_ONB001_NEGATIVE_PROOF_MISSING'; END IF;
END $post$;
COMMIT;
