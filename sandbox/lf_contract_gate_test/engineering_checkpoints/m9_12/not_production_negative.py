"""IG M9.12 CP4 — source-bound adversarial non-production assurance.

Execute NEGATIVE_PROBES_SQL via Supabase under the protected service context.
Then run READBACK_SQL, and feed its actual JSON row to assert_negative_row.
No mock positive data and no production activation.
"""
NEGATIVE_PROBES_SQL = r"""DO $m912_negative$
DECLARE before_n bigint; after_n bigint; rejected_missing bool := false; rejected_stale bool := false;
BEGIN
 SELECT count(*) INTO before_n
 FROM programacion.provenance_receipts WHERE subject_type='IG_CUTOVER_READINESS';
 BEGIN
   PERFORM programacion.fn_ig_m912_cutover_ready_receipt_v1(NULL);
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='M912_BUNDLE_SHA_REQUIRED' THEN rejected_missing:=true; ELSE RAISE; END IF;
 END;
 BEGIN
   PERFORM programacion.fn_ig_m912_cutover_ready_receipt_v1(repeat('f',64));
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='M912_M90_PINNED_BUNDLE_CURRENTNESS_MISMATCH'
   THEN rejected_stale:=true; ELSE RAISE; END IF;
 END;
 SELECT count(*) INTO after_n
 FROM programacion.provenance_receipts WHERE subject_type='IG_CUTOVER_READINESS';
 IF NOT rejected_missing OR NOT rejected_stale OR after_n<>before_n
 THEN RAISE EXCEPTION 'M912_NEGATIVE_TEST_FALSE_PASS'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.promotions)
 THEN RAISE EXCEPTION 'M912_PRODUCTION_PROMOTION_DETECTED'; END IF;
END $m912_negative$;"""

READBACK_SQL = r"""WITH pin AS (
 SELECT r.id,r.subject_sha256
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 JOIN programacion.provenance_receipts r
 ON r.id=substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.0'
 AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE'
), state AS (
 SELECT (SELECT count(*) FROM programacion.promotions) total_promotions,
 (SELECT count(*) FROM programacion.promotions WHERE status='PRODUCTION_ACTIVE') production_active,
 (SELECT count(*) FROM programacion.provenance_receipts
 WHERE subject_type='IG_CUTOVER_READINESS' AND receipt_kind='EVIDENCE_VERIFICATION'
 AND issuer_channel='EVIDENCE_VERIFIER_V1'
 AND payload->>'verification_status'='VERIFIED') verified_receipts,
 (SELECT count(*) FROM programacion.provenance_receipts
 WHERE subject_type='IG_CUTOVER_READINESS' AND payload->>'bundle_sha256' IS NULL)
 receipt_missing_sha,
 (SELECT count(*) FROM programacion.provenance_receipts r
 WHERE r.subject_type='IG_CUTOVER_READINESS'
 AND r.payload->>'bundle_sha256' IS DISTINCT FROM
 (SELECT subject_sha256 FROM pin LIMIT 1)) receipt_stale_sha,
 (SELECT subject_sha256 FROM pin LIMIT 1) pinned_bundle_sha,
 (SELECT count(*) FROM programacion.provenance_receipts
 WHERE subject_type='IG_CUTOVER_READINESS'
 AND payload->>'bundle_sha256'=(SELECT subject_sha256 FROM pin LIMIT 1)) current_receipts
)
SELECT CASE WHEN total_promotions=0 AND production_active=0
 AND verified_receipts>=1 AND current_receipts=verified_receipts
 AND receipt_missing_sha=0 AND receipt_stale_sha=0
 THEN 'PASS_NON_PRODUCTION_SIGNED_NEGATIVE' ELSE 'BLOCKED_NEGATIVE_CURRENTNESS' END status,
 total_promotions,production_active,verified_receipts,receipt_missing_sha,receipt_stale_sha,
 pinned_bundle_sha,current_receipts
FROM state;"""

def assert_negative_row(row: dict, *, missing_sha_rejected: bool,
                        stale_sha_rejected: bool) -> dict:
    """Only call after actual protected NEGATIVE_PROBES_SQL succeeded."""
    if (row.get("status") != "PASS_NON_PRODUCTION_SIGNED_NEGATIVE"
        or row.get("total_promotions") != 0
        or row.get("production_active") != 0
        or row.get("verified_receipts", 0) < 1
        or row.get("current_receipts") != row.get("verified_receipts")
        or row.get("receipt_missing_sha") != 0
        or row.get("receipt_stale_sha") != 0
        or not missing_sha_rejected or not stale_sha_rejected):
        raise AssertionError("M912_ADVERSARIAL_PROVENANCE_NOT_PROVED")
    return {"test_passed":True,"test_exit_code":0,
            "semantic_authority_bound":True,"adversarial_case_executed":True,
            "missing_sha_rejected":True,"stale_sha_rejected":True,
            "zero_production_active":True}

if __name__ == "__main__":
    for row, missing, stale in [
      ({},False,False),
      ({"status":"PASS_NON_PRODUCTION_SIGNED_NEGATIVE"},True,True),
      ({"status":"PASS_NON_PRODUCTION_SIGNED_NEGATIVE","total_promotions":1,
         "production_active":0,"verified_receipts":1,"current_receipts":1,
         "receipt_missing_sha":0,"receipt_stale_sha":0},True,True),
      ({"status":"PASS_NON_PRODUCTION_SIGNED_NEGATIVE","total_promotions":0,
         "production_active":0,"verified_receipts":1,"current_receipts":1,
         "receipt_missing_sha":0,"receipt_stale_sha":0},False,True),
    ]:
        try:
            assert_negative_row(row,missing_sha_rejected=missing,stale_sha_rejected=stale)
        except AssertionError:
            pass
        else:
            raise AssertionError("M912_NEGATIVE_HELPER_FALSE_PASS")
    print("PASS_NEGATIVE_HELPER_CASES; NO_DB_EXECUTION_YET")
