-- M9.9 TIMEOUT. Boundary: elapsed == limit does not trigger; elapsed > limit does.
-- READ ONLY. No elapsed clock is measured here. Never claim runtime timeout or rollback.
BEGIN TRANSACTION READ ONLY;
WITH policy AS (
 SELECT (unit_metadata#>>'{canary_rollback_policy_v1,timeout_limit_ms}')::int AS t
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
), two AS (
 SELECT ('AT_LIMIT') AS probe_code,t AS elapsed,t FROM policy
 UNION ALL
 SELECT ('OVER_LIMIT') AS probe_code,t+1 AS elapsed,t FROM policy
), verdict AS (
 SELECT probe_code,programacion.fn_ig_m99_canary_rollback_decision_v1(
  jsonb_build_object('false_pass_detected',false,'divergence_level','D0',
  'elapsed_ms',elapsed,'execution_error',false,'receipt_present',true,'receipt_verified',true),t) AS r
 FROM two
)
SELECT 'TIMEOUT' AS case_code,probe_code,'DECISION_ONLY_EXECUTION_UNPROVEN' AS evidence_level,
 CASE WHEN probe_code='OVER_LIMIT'
 THEN (r->>'action'='ROLLBACK_REQUIRED' AND r->'reason_codes' ? 'TIMEOUT')
 ELSE (r->>'action'='CONTINUE_OBSERVATION' AND NOT (r->'reason_codes' ? 'TIMEOUT')) END
 AND r->>'rollback_executed'='false' AS decision_contract_pass,r AS decision_receipt
FROM verdict ORDER BY probe_code;
ROLLBACK;
