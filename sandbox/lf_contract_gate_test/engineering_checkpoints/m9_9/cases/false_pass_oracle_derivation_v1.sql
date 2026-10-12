-- M9.9 FALSE_PASS independent prior-art derivation. No writes, no canary closure.
BEGIN TRANSACTION READ ONLY;
WITH s AS (
 SELECT suite_run_id,status,tests_total,tests_passed,tests_failed,tests_blocked,
 tests_review_required,manifest,
 programacion.fn_engineering_run_test_receipt_bundle_v1(suite_run_id) b
 FROM public.lf_test_suite_runs
 WHERE metadata->>'unit_code'='M4.9' AND metadata->>'checkpoint_code'='RUN_CAMPAIGN'
 ORDER BY created_at DESC LIMIT 1
), o AS (
 SELECT tr.test_code,tr.status,ar.actual_value v,c.expected_output->>'decision' expected
 FROM s JOIN public.lf_test_runs tr USING(suite_run_id)
 JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
 JOIN public.lf_test_suite_cases c ON c.test_code=tr.test_code
 WHERE ar.assertion_code=tr.test_code||'_ASSERT'
), q AS (
 SELECT count(*) n,count(*) FILTER(WHERE status='PASS' AND v->>'detected'='true'
 AND v->>'false_pass'='false' AND expected='DETECTED_FAIL_CLOSED') ok,
 count(*) FILTER(WHERE v->>'detection_surface'='VALIDATOR_CLASSIFIER_MISMATCH') generic
 FROM o
), derived AS (
 SELECT q.*,s.status='PASSED' AND s.tests_total=10 AND s.tests_passed=10
 AND s.tests_failed=0 AND s.tests_blocked=0 AND s.tests_review_required=0
 AND s.b->>'status'='VERIFIED' AND s.manifest->>'false_pass_count'='0'
 AND q.n=10 AND q.ok=10 AS prior_art_verified FROM q CROSS JOIN s
)
SELECT 'FALSE_PASS' case_code, 'M49_ORACLE_HISTORICAL_NOT_LIVE_CANARY' proof_level,
 prior_art_verified,n AS typed_cases,ok AS detected,generic AS generic_classified,
 prior_art_verified AS can_derive_against_known_mutations,
 false AS signed_live_canary_proven,false AS independent_canary_comparison_proven,
 false AS actual_automatic_rollback_proven,false AS checkpoint_close_allowed
FROM derived;
ROLLBACK;
