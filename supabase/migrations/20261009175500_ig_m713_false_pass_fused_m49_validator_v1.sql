-- M7.13 checkpoint 4: repair wrong fused reference M7.7 -> canonical M4.9.
-- Fix local contract and actual validator atomically. No new gate; no release.
-- The independent M4.9 suite verifies 10 typed mutation assertions, 0 false PASS.
CREATE OR REPLACE FUNCTION programacion.fn_ig_release_criteria_controls_v1(p_family_run_id bigint, p_false_pass_suite_run_id uuid, p_divergence_suite_run_id uuid, p_bundle_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
DECLARE v_family_count integer:=0;v_assessment_count integer:=0;
DECLARE v_run record;v_coverage_ok boolean:=false;
DECLARE v_false_ok boolean:=false;v_divergence_ok boolean:=false;
DECLARE v_bundle_ok boolean:=false;
DECLARE v_false_bundle jsonb;v_div_bundle jsonb;
BEGIN
 v_bundle_ok:=coalesce(p_bundle_sha256 ~ '^[0-9a-f]{64}$',false);
 IF p_family_run_id IS NOT NULL THEN
   SELECT status,invalidated_at,family_count INTO v_run
   FROM programacion.input_readiness_runs WHERE id=p_family_run_id;
   IF FOUND THEN
     SELECT count(distinct family_code),count(*)
       INTO v_family_count,v_assessment_count
     FROM programacion.input_family_assessments WHERE run_id=p_family_run_id;
     v_coverage_ok:=v_run.status='COMPLETED' AND v_run.invalidated_at IS NULL
       AND programacion.fn_input_readiness_run_is_current(p_family_run_id) IS TRUE
       AND v_run.family_count=47 AND v_family_count=47 AND v_assessment_count=47;
   END IF;
 END IF;
 IF p_false_pass_suite_run_id IS NOT NULL THEN
   v_false_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(p_false_pass_suite_run_id);
   -- M7.7 is FUSED -> M4.9 (PAULO-063). The canonical M4.9 suite has
   -- 10 mutation cases, each storing detected + false_pass as typed booleans.
   -- A PASSED suite with even one false_pass=true is NEVER acceptable.
   SELECT (
     count(DISTINCT tr.test_code)=10
     AND count(ar.assertion_result_id)=10
     AND coalesce(bool_and(
       tr.status='PASS'
       AND ar.status='PASS'
       AND ar.actual_value->>'detected'='true'
       AND ar.actual_value->>'false_pass'='false'
     ),false)
   ) INTO v_false_ok
   FROM public.lf_test_suite_runs sr
   JOIN public.lf_test_runs tr ON tr.suite_run_id=sr.suite_run_id
   JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
   WHERE sr.suite_run_id=p_false_pass_suite_run_id
     AND sr.suite_code='INPUT_GOVERNANCE_REGRESSION'
     AND sr.status='PASSED'
     AND sr.tests_total=10 AND sr.tests_passed=10 AND sr.tests_failed=0 AND sr.tests_blocked=0
     AND sr.metadata->>'unit_code'='M4.9'
     AND sr.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
     AND tr.test_code ~ '^M4_9_T(0[1-9]|10)_'
     AND ar.assertion_code=tr.test_code||'_ASSERT'
     AND (v_false_bundle->>'status')='VERIFIED';
 END IF;
 IF p_divergence_suite_run_id IS NOT NULL THEN
   v_div_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(p_divergence_suite_run_id);
   SELECT EXISTS(
     SELECT 1 FROM public.lf_test_suite_runs sr
     JOIN public.lf_test_runs tr ON tr.suite_run_id=sr.suite_run_id
     JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
     WHERE sr.suite_run_id=p_divergence_suite_run_id
       AND sr.status='PASSED' AND sr.tests_total>0
       AND sr.tests_failed=0 AND sr.tests_blocked=0
       AND ar.assertion_code='IG_UNEXPLAINED_DIVERGENCE_ZERO'
       AND ar.status='PASS'
       AND ar.actual_value->>'unexplained_divergence_count'='0'
       AND sr.metadata->>'unit_code' IN ('M7.7','M7.13')
       AND (v_div_bundle->>'status')='VERIFIED'
   ) INTO v_divergence_ok;
 END IF;
 IF p_false_pass_suite_run_id IS NOT NULL AND p_false_pass_suite_run_id=p_divergence_suite_run_id
 THEN
   -- Two distinct obligations must be independently supported (no one-receipt shortcut).
   v_false_ok:=false;v_divergence_ok:=false;
 END IF;
 RETURN jsonb_build_object(
  'schema_version','IG_M713_QUALIFICATION_CRITERIA_V1',
  'status',CASE WHEN v_coverage_ok AND v_false_ok AND v_divergence_ok AND v_bundle_ok
          THEN 'CANDIDATE_EVIDENCED' ELSE 'BLOCKED' END,
  'qualification_framework','QUALIFICATION_FRAMEWORK',
  'closure_gate','CLOSURE_GATE',
  'consumer_unit','M9.0','release_authorized',false,
  'bundle_sha256',CASE WHEN v_bundle_ok THEN p_bundle_sha256 ELSE null END,
  'criteria',jsonb_build_object(
   'family_coverage',jsonb_build_object('state',CASE WHEN v_coverage_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'observed_families',v_family_count,'observed_assessments',v_assessment_count,'required',47,
       'run_id',p_family_run_id),
   'known_false_pass',jsonb_build_object('state',CASE WHEN v_false_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'suite_run_id',p_false_pass_suite_run_id,'required',0),
   'unexplained_divergence',jsonb_build_object('state',CASE WHEN v_divergence_ok THEN 'PASS' ELSE 'BLOCKED' END,
       'suite_run_id',p_divergence_suite_run_id,'required',0)
  ),
  'receipts',jsonb_build_object(
    'mutation',coalesce(v_false_bundle,'{}'::jsonb),
    'divergence',coalesce(v_div_bundle,'{}'::jsonb))
 );
END
$function$


UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(
 jsonb_set(
  jsonb_set(unit_metadata,
   '{action_specs_v1,CRITERIA_AS_CONTROLS,qualification_controls_contract_v1,false_pass_known,evidence}',
   to_jsonb('M4.9 PAULO-063 mutation campaign (M7.7 FUSED -> M4.9)'::text)),
  '{action_specs_v1,FALSE_PASS_BLOCKS,test_execution_contract,canonical_mutation_provider}',
  jsonb_build_object('unit','M4.9','work_code','PAULO-063',
     'source_unit','M7.7','source_disposition','FUSED',
     'suite_code','INPUT_GOVERNANCE_REGRESSION',
     'assertion_key','false_pass','negative_required',true)),
 '{source_pack_v1,checkpoint_inputs,FALSE_PASS_BLOCKS,inputs,db_objects}',
 '["public.lf_test_suite_runs","public.lf_test_runs","public.lf_test_assertion_results","programacion.engineering_plan_units","programacion.engineering_work_items"]'::jsonb)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M7.13';

UPDATE programacion.engineering_work_checkpoints
SET title='Negativo: un false PASS conocido en la campaña de mutación M4.9 (M7.7 FUSED) deja la calificación BLOCKED/FAIL',
updated_at=now(),updated_by_execution_id='IG_M713_M77_FUSED_REPAIR_20261009'
WHERE work_item_id=246 AND checkpoint_code='FALSE_PASS_BLOCKS'
AND status IN ('PENDING','IN_PROGRESS');
