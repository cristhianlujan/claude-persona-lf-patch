-- IG M9.9 / FALSE_PASS: isolated READ-ONLY decision probe.
-- One case per invocation. This proves decision routing only, never automatic rollback.
BEGIN TRANSACTION READ ONLY;
WITH policy AS (SELECT coalesce((select (unit_metadata#>>'{canary_rollback_policy_v1,timeout_limit_ms}')::integer from programacion.engineering_plan_units where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.9'),0) AS limit_ms),
 verdict AS (SELECT programacion.fn_ig_m99_canary_rollback_decision_v1(jsonb_build_object('false_pass_detected',true,'divergence_level','D0','elapsed_ms',100000,'execution_error',false,'receipt_present',true,'receipt_verified',true),policy.limit_ms) AS result FROM policy)
SELECT 'FALSE_PASS' AS case_code,
       'DECISION_ONLY_EXECUTION_UNPROVEN' AS evidence_level,
       (result->>'action'='ROLLBACK_REQUIRED' AND result->'reason_codes' ? 'FALSE_PASS'
        AND result->>'rollback_executed'='false') AS decision_contract_pass,
       result->>'rollback_executed' AS rollback_executed,
       result AS decision_receipt
FROM verdict;
ROLLBACK;
