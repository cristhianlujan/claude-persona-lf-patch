-- Read-only negative receipt fixture; no business data, no fake authorization.
WITH q AS (
SELECT private.fn_lf_d2_facade_receipt_readback_v1(
 '00000000-0000-0000-0000-000000000001'::uuid,
 'db://lf_ops.cargas_lotes', 'EXEC-SYNTHETIC-NO-EVIDENCE') v
)
SELECT v->>'decision' decision,
 CASE WHEN v->>'decision' IN
  ('BLOCK_CANONICAL_RECEIPT_NOT_FOUND','BLOCK_LEDGER_ACL_DENIED')
 AND v->>'business_answer_authorized'='false'
 AND v->>'actor_session_reverified'='false'
 AND v->>'business_rows_returned'='false'
 AND v->>'effects_executed'='false'
 THEN 'PASS' ELSE 'FAIL' END verdict
FROM q;
