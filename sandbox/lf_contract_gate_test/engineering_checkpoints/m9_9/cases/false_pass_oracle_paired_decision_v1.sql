-- M9.9 FALSO PASS: independent oracle-derived signal (AUTHORED adversarial pairs).
-- M4.9 assertion is real historical evidence; hypothetical producer PASS/FAIL is NOT a live canary.
BEGIN TRANSACTION READ ONLY;
WITH s AS (
 SELECT suite_run_id,status,tests_total,tests_passed,tests_failed,tests_blocked,
 tests_review_required,manifest,programacion.fn_engineering_run_test_receipt_bundle_v1(suite_run_id) b
 FROM public.lf_test_suite_runs
 WHERE metadata->>'unit_code'='M4.9' AND metadata->>'checkpoint_code'='RUN_CAMPAIGN'
 ORDER BY created_at DESC LIMIT 1
), o AS (
 SELECT tr.test_code,tr.status,ar.actual_value v,c.expected_output->>'decision' expected
 FROM s JOIN public.lf_test_runs tr USING(suite_run_id)
 JOIN public.lf_test_assertion_results ar ON ar.test_run_id=tr.test_run_id
 JOIN public.lf_test_suite_cases c ON c.test_code=tr.test_code
 WHERE ar.assertion_code=tr.test_code||'_ASSERT'
), gate AS (
 SELECT s.status='PASSED' AND s.tests_total=10 AND s.tests_passed=10
 AND s.tests_failed=0 AND s.tests_blocked=0 AND s.tests_review_required=0
 AND s.b->>'status'='VERIFIED' AND s.manifest->>'false_pass_count'='0'
 AND count(o.test_code)=10
 AND count(o.test_code) FILTER(WHERE o.status='PASS' AND o.v->>'detected'='true'
 AND o.v->>'false_pass'='false' AND o.expected='DETECTED_FAIL_CLOSED')=10 AS qualified
 FROM s JOIN o ON true GROUP BY s.status,s.tests_total,s.tests_passed,s.tests_failed,
 s.tests_blocked,s.tests_review_required,s.b,s.manifest
), pairs AS (
 SELECT o.test_code,p.producer_decision,
 g.qualified AND o.expected='DETECTED_FAIL_CLOSED'
 AND o.status='PASS' AND o.v->>'detected'='true'
 AND o.v->>'false_pass'='false' AND p.producer_decision='PASS' AS independently_derived_false_pass
 FROM o CROSS JOIN gate g CROSS JOIN (VALUES('PASS'::text),('FAIL'::text)) p(producer_decision)
), decisions AS (
 SELECT p.*,programacion.fn_ig_m99_canary_rollback_decision_v1(
 jsonb_build_object('false_pass_detected',independently_derived_false_pass,
 'divergence_level','D0','elapsed_ms',100000,'execution_error',false,
 'receipt_present',true,'receipt_verified',true),150000) verdict
 FROM pairs p
)
SELECT count(*) AS authored_pairs,
 count(*) FILTER (WHERE independently_derived_false_pass) AS independently_derived_positive_cases,
 count(*) FILTER (WHERE NOT independently_derived_false_pass) AS negative_controls,
 bool_and(CASE WHEN independently_derived_false_pass
 THEN verdict->>'action'='ROLLBACK_REQUIRED' AND verdict->'reason_codes' ? 'FALSE_PASS'
 ELSE verdict->>'action'='CONTINUE_OBSERVATION' AND NOT (verdict->'reason_codes' ? 'FALSE_PASS')
 END AND verdict->>'rollback_executed'='false') AS derived_decision_pair_pass,
 'AUTHORED_PAIRS_ON_REAL_M49_ORACLE_NOT_LIVE_CANARY' AS evidence_level,
 false AS auto_rollback_verified,false AS checkpoint_done
FROM decisions;
ROLLBACK;
