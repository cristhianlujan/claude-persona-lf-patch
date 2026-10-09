-- M7.13 checkpoint 2: unit contract + typed quality controls in the same governed micro-lot.
-- Builder responsibility is NOT M9.0 release publication; candidate evidence must never imply release.
-- No new gate/registry/engine; uses existing lf_test_requirement_bindings and the common QA suite.
DO $pre$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_test_suites WHERE suite_code='INPUT_GOVERNANCE_REGRESSION')
 THEN RAISE EXCEPTION 'M713_CANONICAL_SUITE_NOT_FOUND'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M7.13')
 THEN RAISE EXCEPTION 'M713_UNIT_NOT_FOUND'; END IF;
END $pre$;

INSERT INTO public.lf_test_requirement_bindings(
 binding_code,subject_type,subject_code,characteristic_code,suite_code,required,
 min_pass_rate,false_pass_tolerance,independent_review_required,rollback_required,
 currentness_mode,activation_condition,status,created_by_execution_id
)
SELECT v.binding_code,'OPERATION','IG_CURATOR_VALIDATOR_REFACTOR_V2',NULL,
  'INPUT_GOVERNANCE_REGRESSION',true,1,0,true,true,'EXACT_REVISION',
  jsonb_build_object('type','QUALIFICATION_FRAMEWORK','phase','CANDIDATE_ONLY',
    'criterion',v.criterion,'expected',v.expected,
    'consumed_by','M9.0','requires_typed_receipt',true,'release_authorized',false),
  'CANDIDATO','IG_M713_CONTRACT_CRITERIA_20261009'
FROM (VALUES
 ('BIND-IG-M713-FALSE-PASS-V1','KNOWN_FALSE_PASS',0),
 ('BIND-IG-M713-DIVERGENCE-V1','UNEXPLAINED_DIVERGENCE',0),
 ('BIND-IG-M713-FAMILY-COVERAGE-V1','FAMILY_COVERAGE',47)
) AS v(binding_code,criterion,expected)
WHERE NOT EXISTS(SELECT 1 FROM public.lf_test_requirement_bindings b WHERE b.binding_code=v.binding_code);

-- Deterministic evidence resolver, NOT a release gate and NOT a receipt publisher.
-- Proof cannot be replaced by a caller-supplied PASS/count; it comes from DB rows and
-- existing canonical test graph. Missing/stale/ambiguous evidence fails closed.
CREATE OR REPLACE FUNCTION programacion.fn_ig_release_criteria_controls_v1(
 p_family_run_id bigint,
 p_false_pass_suite_run_id uuid,
 p_divergence_suite_run_id uuid,
 p_bundle_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog','programacion','public'
AS $fn$
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
       AND v_run.family_count=47 AND v_family_count=47 AND v_assessment_count=47;
   END IF;
 END IF;
 IF p_false_pass_suite_run_id IS NOT NULL THEN
   v_false_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(p_false_pass_suite_run_id);
   SELECT EXISTS(
     SELECT 1 FROM public.lf_test_suite_runs sr
     JOIN public.lf_test_runs tr ON tr.suite_run_id=sr.suite_run_id
     JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
     WHERE sr.suite_run_id=p_false_pass_suite_run_id
       AND sr.status='PASSED' AND sr.tests_total>0
       AND sr.tests_failed=0 AND sr.tests_blocked=0
       AND ar.assertion_code='IG_KNOWN_FALSE_PASS_REJECTED'
       AND ar.status='PASS'
       AND ar.actual_value->>'known_false_pass_count'='0'
       AND sr.metadata->>'unit_code' IN ('M7.7','M7.13')
       AND (v_false_bundle->>'status')='VERIFIED'
   ) INTO v_false_ok;
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
$fn$;

COMMENT ON FUNCTION programacion.fn_ig_release_criteria_controls_v1(bigint,uuid,uuid,text)
IS 'M7.13 candidate-only typed criteria readback. Release authority remains solely with existing QUALIFICATION_FRAMEWORK/CLOSURE_GATE consumers; never passes without independently verified real receipts.';

-- Explicitly separate the unit's build/demonstrate closure from M9.0's later publication.
-- Preserve original 3 predicates and no-own-gate requirement; do NOT auto-mark the unit DONE.
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(
  jsonb_set(unit_metadata,
   '{action_specs_v1,CRITERIA_AS_CONTROLS,qualification_controls_contract_v1}',
   coalesce(unit_metadata#>'{action_specs_v1,CRITERIA_AS_CONTROLS,qualification_controls_contract_v1}','{}'::jsonb)
   || jsonb_build_object(
    'unit_obligation','BUILD_BINDINGS_AND_FAIL_CLOSED_CRITERIA_RESOLVER',
    'completion_boundary','FUNCTION_AND_BINDINGS_PUBLISHED_TESTED_NO_OWN_GATE',
    'release_obligation_owner','M9.0',
    'release_publication_is_prerequisite_for_m713_done',false,
    'candidate_evidence_is_not_release',true,
    'receipt_source','CANONICAL_EXISTING_QUALIFICATION_FRAMEWORK',
    'never_assume_missing_receipts_pass',true,
    'function_signature','programacion.fn_ig_release_criteria_controls_v1(bigint,uuid,uuid,text)'
   )),
  '{action_specs_v1,CRITERIA_AS_CONTROLS,assertion_contract,pass_when}',
  '{"git_merged":true,"readback_passed":true,"implementation_written":true,"positive_and_negative_behavior_tested":true,"does_not_authorize_release":true}'::jsonb
 )
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND unit_code='M7.13';
