-- IG M9.9 FALSE_PASS: independently read canonical M4.9 typed mutation evidence.
-- This is qualification of PRIOR ART, not a signed IG canary receipt or automatic rollback.
BEGIN TRANSACTION READ ONLY;
WITH latest AS (
 SELECT s.suite_run_id,s.status,s.tests_total,s.tests_passed,s.tests_failed,
        s.tests_blocked,s.tests_review_required,s.manifest,s.created_at
 FROM public.lf_test_suite_runs s
 WHERE s.metadata->>'plan_code'='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND s.metadata->>'unit_code'='M4.9'
   AND s.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
 ORDER BY s.created_at DESC LIMIT 1
), typed AS (
 SELECT count(*) AS assertions,
        count(distinct tr.test_code) AS distinct_cases,
        count(*) FILTER (WHERE tr.status='PASS' AND ar.actual_value->>'detected'='true'
                    AND ar.actual_value->>'false_pass'='false') AS correct_detections,
        count(*) FILTER (WHERE ar.actual_value->>'detection_surface'='VALIDATOR_CLASSIFIER_MISMATCH') AS generic_classifications
 FROM latest s
 JOIN public.lf_test_runs tr ON tr.suite_run_id=s.suite_run_id
 JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
 WHERE ar.assertion_code=tr.test_code||'_ASSERT'
), joined AS (
 SELECT s.*,t.*,programacion.fn_engineering_run_test_receipt_bundle_v1(s.suite_run_id) AS bundle
 FROM latest s CROSS JOIN typed t
), proof AS (
 SELECT *,
   (status='PASSED' AND tests_total=10 AND tests_passed=10
     AND tests_failed=0 AND tests_blocked=0 AND tests_review_required=0
     AND (manifest->>'false_pass_count')::int=0
     AND assertions=10 AND distinct_cases=10 AND correct_detections=10
     AND bundle->>'status'='VERIFIED') AS original_qualified
 FROM joined
)
SELECT 'FALSE_PASS' AS case_code,'REUSED_M49_PRIOR_ART_ONLY' AS evidence_level,
       suite_run_id,created_at,assertions,correct_detections,generic_classifications,
       original_qualified AS prior_art_qualified,
       false AS independent_canary_oracle_proven,
       false AS real_m99_canary_receipts_verified,
       false AS automatic_rollback_proven,
       false AS checkpoint_closure_authorized
FROM proof;
ROLLBACK;
