"""IG M9.12 CP3: verify an ACTUAL signed CUTOVER_READY receipt, never a simulated PASS.

The issuer must run separately through the authorized protected function. This
readback consumes only persisted source/current ledger evidence. It cannot issue
receipts, mutate production, or substitute a Python fixture for a DB assertion.
"""
READBACK_SQL = r"""WITH pinned AS (
 SELECT r.*
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 JOIN programacion.provenance_receipts r
   ON r.id=substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.0'
 AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE'
), prerequisite_units AS (
 SELECT u.unit_code,w.status,COUNT(*) total,
 COUNT(*) FILTER (WHERE c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL) attested,
 bool_or(u.unit_code='M9.8' AND c.checkpoint_code='GATE_VERDICT_READBACK'
   AND c.status='DONE' AND c.evidence_ref LIKE '%fn_ig_m98_engineering_assurance_v7%'
   AND u.unit_metadata#>>'{m9_8_gate_contract_v2,technical_positive_state}'
      ='TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED') technical,
 bool_or(u.unit_code='M9.10' AND c.checkpoint_code='DRILL_READBACK'
   AND c.status='DONE') drill,
 bool_or(u.unit_code='M9.11' AND c.checkpoint_code='SOAK_READBACK'
   AND c.status='DONE') soak
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code IN ('M9.0','M9.8','M9.10','M9.11')
 GROUP BY u.unit_code,w.status
), gate AS (
 SELECT (SELECT count(*)=4 AND bool_and(status='DONE' AND total=attested AND total>0)
          FROM prerequisite_units) all_done,
 (SELECT bool_or(technical) FROM prerequisite_units) m98_technical,
 (SELECT bool_or(drill) FROM prerequisite_units) m910_drill,
 (SELECT bool_or(soak) FROM prerequisite_units) m911_soak,
 (SELECT count(*)=0 FROM programacion.promotions) promotions_zero,
 (SELECT id FROM pinned LIMIT 1) bundle_receipt_id,
 (SELECT subject_sha256 FROM pinned LIMIT 1) bundle_sha256,
 (SELECT head_sha FROM pinned LIMIT 1) bundle_head
), selected AS (
 SELECT r.*,g.*
 FROM gate g
 LEFT JOIN LATERAL (
 SELECT r.*
 FROM programacion.provenance_receipts r
 WHERE r.subject_type='IG_CUTOVER_READINESS'
   AND r.subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
   AND r.payload->>'bundle_sha256'=g.bundle_sha256
 ORDER BY r.id DESC LIMIT 1
 ) r ON true
)
SELECT
 CASE WHEN
  all_done AND m98_technical AND m910_drill AND m911_soak
  AND promotions_zero
  AND receipt_kind='EVIDENCE_VERIFICATION'
  AND issuer_channel='EVIDENCE_VERIFIER_V1'
  AND payload->>'verification_status'='VERIFIED'
  AND payload->>'readiness_status'='CUTOVER_READY'
  AND payload->>'production_inactive'='true'
  AND head_sha=bundle_head
  AND subject_sha256=programacion.fn_v09_sha256_jsonb(payload->'manifest')
  AND receipt_sha256=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
   'schema_version',1,'receipt_kind',receipt_kind,'execution_id',execution_id,
   'head_sha',head_sha,'subject_type',subject_type,'subject_ref',subject_ref,
   'subject_sha256',subject_sha256,'issuer_channel',issuer_channel,
   'issuer_identity',issuer_identity,'verification_ref',verification_ref,
   'payload',payload))
 THEN 'PASS_SIGNED_IG_CUTOVER_READY' ELSE 'BLOCKED_MISSING_OR_STALE_RECEIPT' END status,
 COALESCE(all_done AND m98_technical AND m910_drill AND m911_soak,FALSE) prerequisites_current,
 COALESCE(promotions_zero,FALSE) production_inactive,
 COALESCE(issuer_channel='EVIDENCE_VERIFIER_V1' AND
  subject_sha256=programacion.fn_v09_sha256_jsonb(payload->'manifest') AND
  receipt_sha256=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
   'schema_version',1,'receipt_kind',receipt_kind,'execution_id',execution_id,
   'head_sha',head_sha,'subject_type',subject_type,'subject_ref',subject_ref,
   'subject_sha256',subject_sha256,'issuer_channel',issuer_channel,
   'issuer_identity',issuer_identity,'verification_ref',verification_ref,
   'payload',payload)),FALSE) semantic_authority_bound,
 COALESCE(payload->>'verification_status'='VERIFIED' AND
  payload->>'readiness_status'='CUTOVER_READY' AND
  payload->>'bundle_sha256'=bundle_sha256,FALSE) verified_cutover_receipt_current,
 id AS receipt_id,bundle_receipt_id,bundle_sha256
FROM selected;"""

def assert_cutover_row(row: dict) -> dict:
    required = ("prerequisites_current","production_inactive",
                "semantic_authority_bound","verified_cutover_receipt_current")
    if row.get("status") != "PASS_SIGNED_IG_CUTOVER_READY" or any(
        row.get(key) is not True for key in required
    ) or not isinstance(row.get("receipt_id"), int):
        raise AssertionError("M912_ACTUAL_SIGNED_READINESS_RECEIPT_REQUIRED")
    return {"test_passed":True,"test_exit_code":0,
            **{key:True for key in required},
            "receipt_id":row["receipt_id"],
            "bundle_receipt_id":row["bundle_receipt_id"]}

if __name__ == "__main__":
    # Only adversarial assertion-helper tests; NO synthetic DB PASS.
    negative_cases = [
        {}, {"status":"PASS_SIGNED_IG_CUTOVER_READY"},
        {"status":"PASS_SIGNED_IG_CUTOVER_READY","receipt_id":1},
        {"status":"PASS_SIGNED_IG_CUTOVER_READY","receipt_id":1,
         "prerequisites_current":True,"production_inactive":True,
         "semantic_authority_bound":False,"verified_cutover_receipt_current":True},
    ]
    for row in negative_cases:
        try:
            assert_cutover_row(row)
        except AssertionError:
            pass
        else:
            raise AssertionError("M912_NEGATIVE_CASE_FALSE_PASS")
    print("NEGATIVE_ASSERTION_HELPER_PASS; DB_READBACK_NOT_RUN")
