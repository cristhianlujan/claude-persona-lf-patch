-- M9.9 EXECUTION_ERROR. READ ONLY: error bit asserted, not a real process exception.
BEGIN TRANSACTION READ ONLY;
WITH policy AS (
 SELECT (unit_metadata#>>'{canary_rollback_policy_v1,timeout_limit_ms}')::int AS t
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
), verdict AS (
 SELECT programacion.fn_ig_m99_canary_rollback_decision_v1(
  jsonb_build_object('false_pass_detected',false,'divergence_level','D0',
  'elapsed_ms',100000,'execution_error',true,'receipt_present',true,'receipt_verified',true),t) AS r
 FROM policy
)
SELECT 'EXECUTION_ERROR' AS case_code,'DECISION_ONLY_EXECUTION_UNPROVEN' AS evidence_level,
 (r->>'action'='ROLLBACK_REQUIRED' AND r->'reason_codes' ? 'EXECUTION_ERROR'
 AND r->>'rollback_executed'='false') AS decision_contract_pass,r AS decision_receipt
FROM verdict;
ROLLBACK;
