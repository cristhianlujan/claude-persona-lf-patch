-- CP2 ONLY. No run mutation, operational cutover or checkpoint DONE.
CREATE OR REPLACE VIEW programacion.v_ig_m105_cp2_verdict_v1 WITH (security_invoker=true) AS
WITH e AS (
 SELECT v.*,p.codigo screen_code,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=v.run_id AND a.validator_outcome IN ('PASS','FAIL','BLOCKED')) final_decisions,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=v.run_id AND a.validator_outcome='FAIL') semantic_rejections,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=v.run_id AND (a.production_ready_status IN ('BLOCKED','NOT_READY','PENDING') OR a.validator_outcome='BLOCKED' OR a.applicability='UNRESOLVED')) evaluation_holds,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=v.run_id AND a.applicability='NOT_APPLICABLE') not_applicable_decisions,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=v.run_id AND (a.validator_outcome IS NULL OR a.validator_outcome='PENDING' OR a.validator_identity IS NULL OR a.validator_sha256 IS NULL OR jsonb_typeof(a.validator_findings) IS DISTINCT FROM 'array')) invalid_decisions
 FROM programacion.v_ig_m105_cohort_evidence_v1 v
 JOIN lf_ops.pantallas p ON p.id=v.pantalla_id
), t AS (
 SELECT e.*,CASE
 WHEN run_id IS NULL THEN 'NOT_RUN'
 WHEN run_status IN ('CURATING','VALIDATING','BLOCKED') THEN 'IN_PROGRESS_OR_POLICY_HOLD'
 WHEN run_status IS DISTINCT FROM 'COMPLETED' OR family_count<1 OR family_rows<>family_count OR assessed_rows<>family_count OR final_decisions<>family_count OR invalid_decisions>0 THEN 'ERROR_TECNICO'
 ELSE 'PASS_TECNICO' END technical_verdict FROM e
)
SELECT t.*, CASE WHEN NOT coalesce(fresh_vnext,false) THEN 'NO_EJECUTADO_VNEXT'
 WHEN technical_verdict='ERROR_TECNICO' THEN 'ERROR_TECNICO'
 WHEN technical_verdict<>'PASS_TECNICO' THEN 'EN_EVALUACION_NO_ERROR'
 WHEN NOT coalesce(source_current,false) OR NOT coalesce(release_bound,false) OR NOT coalesce(edge_identities,false) OR NOT coalesce(agent_edge_receipt,false) THEN 'ERROR_PROCEDENCIA'
 ELSE 'PASS_CP2' END cp2_verdict FROM t;
DO $m$
DECLARE u jsonb; w bigint; q text;
BEGIN
SELECT work_item_id,unit_metadata INTO STRICT w,u FROM programacion.engineering_plan_units
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=w AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
OR u#>>'{m105_validation_contract_v3,schema_version}'<>'M105_COHORT_EVIDENCE_V3'
OR u#>>'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries,0}' NOT LIKE '%v_ig_m105_cohort_evidence_v1%'
THEN RAISE EXCEPTION 'CP2_PRESTATE_DRIFT'; END IF;
IF (SELECT count(*) FROM programacion.v_ig_m105_cp2_verdict_v1)
  <>jsonb_array_length(u#>'{m105_scope_v1,screen_ids}')
OR EXISTS(SELECT 1 FROM programacion.v_ig_m105_cp2_verdict_v1
          WHERE technical_verdict IS NULL OR cp2_verdict IS NULL)
THEN RAISE EXCEPTION 'CP2_PREVIEW_SHAPE_DRIFT'; END IF;
q:=$readback$SELECT jsonb_build_object(
'schema_version','IG_M105_CP2_RELEASE_READBACK_V2','scope_origin','M105_SCOPE_SNAPSHOT_V1','readback_provider','SUPABASE_CANONICAL_READONLY',
'current_release',max(release_version),'previous_release',max(previous_version),'current_manifest_sha256',max(release_manifest_sha256),
'cohort_count',count(*),'fresh_completed_count',count(*) FILTER(WHERE fresh_vnext),
'release_bound_count',count(*) FILTER(WHERE release_bound),'source_current_count',count(*) FILTER(WHERE source_current),
'validator_assessed_count',count(*) FILTER(WHERE family_count>0 AND assessed_rows=family_count),
'edge_identity_count',count(*) FILTER(WHERE edge_identities),'edge_provenance_receipt_count',count(*) FILTER(WHERE agent_edge_receipt),
'technical_pass_count',count(*) FILTER(WHERE technical_verdict='PASS_TECNICO'),
'technical_error_count',count(*) FILTER(WHERE technical_verdict='ERROR_TECNICO'),
'cp2_pass_count',count(*) FILTER(WHERE cp2_verdict='PASS_CP2'),
'cp2_provenance_error_count',count(*) FILTER(WHERE cp2_verdict='ERROR_PROCEDENCIA'),
'cp2_not_executed_count',count(*) FILTER(WHERE cp2_verdict='NO_EJECUTADO_VNEXT'),
'cp2_pending_count',count(*) FILTER(WHERE cp2_verdict='EN_EVALUACION_NO_ERROR'),
'semantic_rejections_recorded',coalesce(sum(semantic_rejections),0),
'evaluation_holds_recorded',coalesce(sum(evaluation_holds),0),
'not_applicable_recorded',coalesce(sum(not_applicable_decisions),0),
'screen_results',jsonb_agg(jsonb_build_object('screen',screen_code,'pantalla_id',pantalla_id,
'run_id',run_id,'technical',technical_verdict,'cp2',cp2_verdict,
'holds',evaluation_holds,'rejections',semantic_rejections,'not_applicable',not_applicable_decisions)
ORDER BY pantalla_id),'not_a_production_authorization',true
) AS readback FROM programacion.v_ig_m105_cp2_verdict_v1$readback$;
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries}',jsonb_build_array(q),true);
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_queries}',jsonb_build_array(q),true);
u:=jsonb_set(u,'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,queries}',jsonb_build_array(q),true);
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,expected}',to_jsonb(
'13 authentic vNext Edge executions with valid decisions. Semantic rejects, holds, manual review, N/A, missing/partial coverage are legitimate recorded outcomes, not engine errors.'::text),true);
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}',jsonb_build_object(
'test_passed',true,'test_exit_code',0,'semantic_authority_bound',true,
'cohort_count',13,'cp2_pass_count',13,'technical_error_count',0,
'cp2_provenance_error_count',0,'cp2_not_executed_count',0,
'edge_verified_count',13,'release_bound_count',13,'post_cutover_real_vnext',true),true);
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}',
u#>'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}'||jsonb_build_array('programacion.v_ig_m105_cp2_verdict_v1'),true);
u:=jsonb_set(u,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_objects}',
u#>'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_objects}'||jsonb_build_array('programacion.v_ig_m105_cp2_verdict_v1'),true);
u:=jsonb_set(u,'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}',
u#>'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}'||jsonb_build_array('programacion.v_ig_m105_cp2_verdict_v1'),true);
u:=jsonb_set(u,'{m105_cp2_governance_v1}',jsonb_build_object(
'schema_version','M105_CP2_EVALUATION_IS_NOT_ENGINE_FAILURE_V1','scope','M10.5/CP2_ONLY',
'engine_failure_only',jsonb_build_array('BAD_TERMINAL_RUN','MISSING_VALIDATOR_EVIDENCE','WRONG_EDGE_OR_RELEASE_PROVENANCE'),
'valid_evaluation_outcomes',jsonb_build_array('SEMANTIC_REJECTION','BLOCKED','NOT_READY','PARTIAL','MISSING','NOT_APPLICABLE','HUMAN_REVIEW'),
'not_executed','NO_EJECUTADO_VNEXT_NOT_A_SCREEN_ERROR',
'production_activation',false,'receipt_fabrication',false),true);
UPDATE programacion.engineering_plan_units SET unit_metadata=u WHERE work_item_id=w AND unit_code='M10.5' AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';
IF (SELECT unit_metadata#>>'{m105_cp2_governance_v1,schema_version}' FROM programacion.engineering_plan_units WHERE work_item_id=w)
IS DISTINCT FROM 'M105_CP2_EVALUATION_IS_NOT_ENGINE_FAILURE_V1' THEN RAISE EXCEPTION 'CP2_READBACK_MISMATCH'; END IF;
END $m$;
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-CP2-EVALUATION-VERSUS-ENGINE-005','INPUT_GOVERNANCE',
'M10.5 CP2: semantic reject/review is a valid evaluator outcome, not executor failure',
'CP2 needs independent runtime verdict and semantic assessment outcomes per screen.',
'Ready/Blocked/Fail/Not Applicable/Review were conflated with failure or unexecuted-vNext screen defect.',
'Separate integrity and signed Edge provenance from valid semantic outcomes; report no-vNext as not executed, never as screen error.',
'13 current latest-readback runs have structurally valid terminal evaluations; 0 genuine vNext. Do not claim CP2 PASS.',
'supabase://programacion.engineering_plan_units/M10.5/CP2',
'programacion.engineering_plan_units/M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-CP2-EVALUATION-VERSUS-ENGINE-005');
