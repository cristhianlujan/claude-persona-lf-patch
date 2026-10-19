"""Canonical independent review-v3 + raw SOURCE_SNAPSHOT: TEST DOUBLES only."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_updater_native_material_ledger_v02 import make_native_review_ledger_reader

RID = "1fe788e8-5d18-4f62-a09a-c0bd46d7ea2f"
SRC = "bfe788e8-5d18-4f62-a09a-c0bd46d7ea2f"


def ledger_row():
    return {
        "receipt_id": RID, "reviewer_execution_id": "REVIEW-2",
        "capability_code": "INDEPENDENT_ASSURANCE",
        "receipt_kind": "INDEPENDENT_REVIEW_RECEIPT",
        "subject_type": "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
        "subject_ref": "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5",
        "subject_sha256": "a"*64, "source_head_sha":"1"*40,
        "verification_state": "VERIFIED", "verified_at": "2026-10-16T01:00:00Z",
        "resolver_active": True, "trust_level": "TRUSTED_PROVIDER_BOUND",
        "provider": "SUPABASE", "resolver_provider": "SUPABASE",
        "verification_method": "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "resolver_method": "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "receipt_payload": {"verdict": "PASS", "evidence_refs":["source_sha:abc"]},
        "verification_payload": {
            "reviewer_execution_id":"REVIEW-2", "producer_execution_id":"PRODUCER-1"
        },
        "operation_code": "REVISION_INDEPENDIENTE_ESTRATEGIA_LF",
        "reviewer_operation_status":"COMPLETED",
        "reviewer_manifest": {"review_scope":"NATIVE_MATERIAL_CONTENT_ONLY",
            "subject_sha256":"a"*64, "producer_execution_id":"PRODUCER-1",
            "subject_receipt_id":SRC},
        "source_receipt_id":SRC, "producer_execution_id":"PRODUCER-1",
        "source_receipt_kind":"SOURCE_SNAPSHOT",
        "source_capability_code":"EVIDENCE_LEDGER",
        "source_subject_type":"PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
        "source_subject_ref":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5",
        "source_subject_sha256":"a"*64, "source_head":"1"*40,
        "source_verification_state":"VERIFIED",
        "source_provider":"SUPABASE", "source_resolver_provider":"SUPABASE",
        "source_verification_method":"SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "source_resolver_method":"SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
        "source_resolver_active":True,"source_trust_level":"TRUSTED_PROVIDER_BOUND",
        "source_verification":{"provider_readback_verified":True,"digest_recomputed":True},
        "source_payload":{
            "handoff_sha256":"b"*64,"capture_sha256":"c"*64,
            "source_manifest_sha256":"d"*64,
            "profile_slug":"repair","run_id":"RUN-1",
            "native_conversation_scope":"EXISTING_CONVERSATION_ONLY",
            "api_invocation":False,"session_creation":False,
            "cutover_eligible":False,"method_execution_certified":False,
        },
        "clean_review_steps":6,
        "semantic_payload":{
            "verdict":"PASS","review_context":"INDEPENDENT_OPERATION_CONTEXT",
            "independence_measure":{"state":"INDEPENDENT"},
            "positive_controls_passed":True,"negative_controls_passed":True},
    }


class LedgerBridgeTests(unittest.TestCase):
    def assert_blocks(self, modify):
        row=ledger_row();modify(row)
        self.assertIsNone(make_native_review_ledger_reader(lambda sql,parameters:row)(RID))

    def test_trusted_bound_receipt_positive(self):
        calls=[]
        def query(sql,params):
            calls.append((sql,params))
            return ledger_row()
        resolved=make_native_review_ledger_reader(query)(RID)
        self.assertEqual(resolved["subject_raw_sha256"],"a"*64)
        self.assertEqual(resolved["verdict"],"PASS")
        self.assertEqual(resolved["run_id"],"RUN-1")
        self.assertEqual(calls[0][1],(RID,))
        self.assertIn("private.lf_evidence_resolver_registry_v1",calls[0][0])
        self.assertIn("public.lf_operation_execution_steps",calls[0][0])

    def test_invalid_identifier_stopped_before_query(self):
        calls=[]
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:calls.append(1))("1' OR true --"))
        self.assertEqual(calls,[])

    def test_missing_ledger_receipt_blocks(self):
        self.assertIsNone(make_native_review_ledger_reader(lambda s,p:None)(RID))

    def test_untrusted_resolver_blocks(self):
        self.assert_blocks(lambda r:r.update(trust_level="UNTRUSTED"))

    def test_inactive_resolver_blocks(self):
        self.assert_blocks(lambda r:r.update(resolver_active=False))

    def test_wrong_subject_blocks(self):
        self.assert_blocks(lambda r:r.update(subject_ref="OTHER_PLAN/PE10_C5"))

    def test_claimed_cutover_blocks(self):
        self.assert_blocks(lambda r:r["source_payload"].update(cutover_eligible=True))

    def test_self_review_blocks(self):
        self.assert_blocks(lambda r:(r.update(reviewer_execution_id="PRODUCER-1"),
            r["verification_payload"].update(reviewer_execution_id="PRODUCER-1")))

    def test_unverified_receipt_blocks(self):
        self.assert_blocks(lambda r:r.update(verification_state="PENDING"))

    def test_negative_controls_missing_blocks(self):
        self.assert_blocks(lambda r:r["semantic_payload"].update(negative_controls_passed=False))

    def test_wrong_source_digest_blocks(self):
        self.assert_blocks(lambda r:r.update(source_subject_sha256="f"*64))

    def test_wrong_source_head_blocks(self):
        self.assert_blocks(lambda r:r.update(source_head="f"*40))

    def test_incomplete_six_steps_blocks(self):
        self.assert_blocks(lambda r:r.update(clean_review_steps=5))

    def test_wrong_operation_blocks(self):
        self.assert_blocks(lambda r:r.update(operation_code="ANOTHER_OPERATION"))

    def test_unverified_source_blocks(self):
        self.assert_blocks(lambda r:r.update(source_verification_state="PENDING"))

    def test_global_c3_review_cannot_be_reused(self):
        self.assert_blocks(lambda r:r["reviewer_manifest"].update(review_scope="PE10_C3_GLOBAL"))

    def test_source_resolver_untrusted_blocks(self):
        self.assert_blocks(lambda r:r.update(source_trust_level="UNTRUSTED"))

if __name__=="__main__":
    unittest.main()
