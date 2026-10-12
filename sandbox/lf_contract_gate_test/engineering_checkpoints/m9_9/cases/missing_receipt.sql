-- M9.9 MISSING_RECEIPT. Proves read-only fail-closed on absent selector.
-- No authentic missing-receipt runtime event is injected; no automatic rollback is claimed.
BEGIN TRANSACTION READ ONLY;
WITH current_pin AS (
 SELECT manifest_sha256 FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE'
), missing AS (
 SELECT coalesce((SELECT max(id) FROM programacion.provenance_receipts),0)+1 AS absent_id
), verdict AS (
 SELECT programacion.fn_ig_m99_canary_receipt_gate_v1(missing.absent_id,
 current_pin.manifest_sha256,'AUTH') AS r
 FROM current_pin CROSS JOIN missing
)
SELECT 'MISSING_RECEIPT' AS case_code,'DECISION_ONLY_EXECUTION_UNPROVEN' AS evidence_level,
 (r->>'action'='ROLLBACK_REQUIRED'
 AND r->'reason_codes' ? 'RECEIPT_MISSING_STALE_OR_UNATTESTED'
 AND r->>'rollback_executed'='false') AS decision_contract_pass,r AS decision_receipt
FROM verdict;
ROLLBACK;
