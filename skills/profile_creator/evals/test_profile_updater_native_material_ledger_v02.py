"""Focused tests for real-ledger row shape; rows below are test doubles."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_updater_native_material_ledger_v02 import make_native_review_ledger_reader

RID = "1fe788e8-5d18-4f62-a09a-c0bd46d7ea2f"


def ledger_row():
    return {
        "receipt_id": RID, "reviewer_execution_id": "REVIEW-2",
        "capability_code": "INDEPENDENT_ASSURANCE",
        "receipt_kind": "INDEPENDENT_REVIEW_RECEIPT",
        "subject_type": "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
        "subject_ref": "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5",
        "subject_sha256": "a"*64,
        "verification_state": "VERIFIED", "verified_at": "2026-10-16T01:00:00Z",
        "resolver_active": True, "trust_level": "TRUSTED_PROVIDER_BOUND",
        "provider": "SUPABASE", "resolver_provider": "SUPABASE",
        "verification_method": "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "resolver_method": "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "receipt_payload": {
            "semantic_verdict": "PASS",
            "plan_code": "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1",
            "checkpoint_code": "PE10_C5",
            "review_scope": "NATIVE_MATERIAL_CONTENT_ONLY",
            "positive_controls_passed": True, "negative_controls_passed": True,
            "method_qualification_claimed": False, "cutover_eligible": False,
            "handoff_sha256": "b"*64, "profile_slug": "repair", "run_id": "RUN-1"
        },
        "verification_payload": {"verified": True},
    }


class LedgerBridgeTests(unittest.TestCase):
    def test_trusted_bound_receipt_positive(self):
        calls=[]
        def query(sql,params):
            calls.append((sql,params))
            return ledger_row()
        resolved=make_native_review_ledger_reader(query)(RID)
        self.assertEqual(resolved["subject_raw_sha256"],"a"*64)
        self.assertEqual(resolved["verdict"],"PASS")
        self.assertEqual(calls[0][1],(RID,))
        self.assertIn("private.lf_evidence_resolver_registry_v1",calls[0][0])

    def test_invalid_identifier_stopped_before_query(self):
        n=[]
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:n.append(1))("1' OR true --"))
        self.assertEqual(n,[])

    def test_missing_ledger_receipt_blocks(self):
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:None)(RID))

    def test_untrusted_resolver_blocks(self):
        row=ledger_row();row["trust_level"]="UNTRUSTED"
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_inactive_resolver_blocks(self):
        row=ledger_row();row["resolver_active"]=False
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_wrong_subject_blocks(self):
        row=ledger_row();row["subject_ref"]="OTHER_PLAN/PE10_C5"
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_claimed_cutover_blocks(self):
        row=ledger_row();row["receipt_payload"]["cutover_eligible"]=True
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_self_review_blocks(self):
        row=ledger_row();row["reviewer_execution_id"]="RUN-1"
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_unverified_receipt_blocks(self):
        row=ledger_row();row["verification_state"]="PENDING"
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

    def test_negative_controls_missing_blocks(self):
        row=ledger_row();row["receipt_payload"]["negative_controls_passed"]=False
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:row)(RID))

if __name__=="__main__":
    unittest.main()
