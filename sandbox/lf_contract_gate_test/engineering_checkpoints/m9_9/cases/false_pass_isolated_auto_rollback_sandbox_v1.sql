-- IG M9.9 / FALSE_PASS sandbox execution probe only.
-- Uses authentic historical M4.9 mutation oracle; producer PASS is authored/adversarial.
-- Rollback is caused by a SQL exception after a real TEMP-state mutation.
-- NO live canary, NO authority pointer mutation, NO signed receipt.
BEGIN;
CREATE TEMP TABLE m99_false_pass_state_v1(k int primary key,v text) ON COMMIT DROP;
INSERT INTO pg_temp.m99_false_pass_state_v1 VALUES(1,'BASELINE');
CREATE TEMP TABLE m99_false_pass_proof_v1(
 case_code text,oracle_case text,decision text,automatic_temp_rollback boolean,
 state_restored boolean,real_canary_receipt boolean) ON COMMIT DROP;
DO $fp$
DECLARE v_suite record;v_case text;v_decision jsonb;v_wrote boolean:=false;
BEGIN
 SELECT suite_run_id,status,tests_total,tests_passed,tests_failed,
   tests_blocked,tests_review_required,manifest
 INTO v_suite FROM public.lf_test_suite_runs
 WHERE metadata->>'unit_code'='M4.9' AND metadata->>'checkpoint_code'='RUN_CAMPAIGN'
 ORDER BY created_at DESC LIMIT 1;
 IF v_suite.status IS DISTINCT FROM 'PASSED' OR v_suite.tests_total<>10
 OR v_suite.tests_passed<>10 OR v_suite.tests_failed<>0
 OR v_suite.tests_blocked<>0 OR v_suite.tests_review_required<>0
 OR v_suite.manifest->>'false_pass_count'<>'0'
 OR programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite.suite_run_id)->>'status'<>'VERIFIED'
 THEN RAISE EXCEPTION 'M99_FALSE_PASS_PRIOR_ART_NOT_VERIFIED'; END IF;
 SELECT tr.test_code INTO v_case
 FROM public.lf_test_runs tr
 JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
 JOIN public.lf_test_suite_cases c ON c.test_code=tr.test_code
 WHERE tr.suite_run_id=v_suite.suite_run_id AND tr.status='PASS'
 AND ar.assertion_code=tr.test_code||'_ASSERT'
 AND ar.actual_value->>'detected'='true' AND ar.actual_value->>'false_pass'='false'
 AND c.expected_output->>'decision'='DETECTED_FAIL_CLOSED'
 AND ar.actual_value->>'detection_surface'<>'VALIDATOR_CLASSIFIER_MISMATCH'
 ORDER BY tr.test_code LIMIT 1;
 IF v_case IS NULL THEN RAISE EXCEPTION 'M99_NO_TYPED_ORACLE_CASE'; END IF;
 BEGIN
  UPDATE pg_temp.m99_false_pass_state_v1 SET v='CANDIDATE' WHERE k=1;
  v_wrote:=true;
  v_decision:=programacion.fn_ig_m99_canary_rollback_decision_v1(
   jsonb_build_object('false_pass_detected',true,'divergence_level','D0',
    'elapsed_ms',100000,'execution_error',false,'receipt_present',true,
    'receipt_verified',true),150000);
  IF v_decision->>'action'<>'ROLLBACK_REQUIRED'
   OR NOT (v_decision->'reason_codes' ? 'FALSE_PASS')
  THEN RAISE EXCEPTION 'M99_FALSE_PASS_DECISION_NOT_TRIGGERED'; END IF;
  RAISE EXCEPTION USING ERRCODE='ZX091',MESSAGE='AUTO_ROLLBACK_FALSE_PASS';
 EXCEPTION WHEN SQLSTATE 'ZX091' THEN
  IF NOT v_wrote OR (SELECT v FROM pg_temp.m99_false_pass_state_v1 WHERE k=1)<>'BASELINE'
  THEN RAISE EXCEPTION 'M99_AUTO_TEMP_ROLLBACK_FAILED'; END IF;
  INSERT INTO pg_temp.m99_false_pass_proof_v1
   VALUES('FALSE_PASS',v_case,'ROLLBACK_REQUIRED',true,true,false);
 END;
END $fp$;
SELECT * FROM pg_temp.m99_false_pass_proof_v1;
ROLLBACK;
