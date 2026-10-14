"""Readback adapter regression with fake trusted database readers, not live admission."""
from __future__ import annotations

import unittest
from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import make_trusted_profile_readback

D = "a" * 64
M = "b" * 64
REG = {
    "capability_code": "METHOD_PACK_REGISTRY", "registry_status": "ACTIVE",
    "version": "1.0.0", "release_state": "RELEASED", "current_version": "1.0.0",
    "manifest_sha256": M, "current_manifest_sha256": M,
    "manifest": {"catalog_payload_sha256": D, "qualified_method_portfolio": [
        {"method_id": "SELF_REFINE", "exact_version": "1.0.0",
         "qualification_state": "QUALIFIED", "benchmark_receipt_ref": "evidence://holdout"}]}
}
RECEIPT = {"subject_type": "PROFILE_ASSESSMENT", "subject_ref": "quality_pack",
           "subject_sha256": D, "verification_state": "VERIFIED",
           "resolver_id": "LF_SUPABASE_READBACK_V1", "resolver_active": True,
           "resolver_trust_level": "TRUSTED_PROVIDER_BOUND", "receipt_id": "fixture-receipt"}


class TestTrustedReadback(unittest.TestCase):
    def make(self, cap=REG, evidence=RECEIPT):
        return make_trusted_profile_readback(lambda name: cap, lambda slug, digest: evidence)

    def test_positive_remains_receipt_only(self):
        result = self.make()("quality_pack", D, D)
        self.assertEqual(result["status"], "VERIFIED_CURRENT")
        self.assertEqual(result["qualified_method_ids"], ["SELF_REFINE"])
        self.assertTrue(result["method_catalog_released"])

    def test_absent_registry(self):
        self.assertEqual(self.make(None)("quality_pack", D, D)["reason"], "METHOD_REGISTRY_NOT_REGISTERED")

    def test_registry_not_released(self):
        self.assertEqual(self.make({**REG, "release_state": "LEGACY_IMPORTED"})("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_old_current_sha(self):
        self.assertEqual(self.make({**REG, "current_manifest_sha256": "c"*64})("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_payload_digest_mismatch(self):
        record = {**REG, "manifest": {"catalog_payload_sha256": "c"*64, "qualified_method_portfolio": []}}
        self.assertEqual(self.make(record)("quality_pack", D, D)["reason"], "CATALOG_PAYLOAD_SHA_MISMATCH")

    def test_missing_method_qualification(self):
        record = {**REG, "manifest": {"catalog_payload_sha256": D}}
        self.assertEqual(self.make(record)("quality_pack", D, D)["reason"], "METHOD_QUALIFICATION_UNRESOLVED")

    def test_incomplete_method_qualification(self):
        record = {**REG, "manifest": {"catalog_payload_sha256": D, "qualified_method_portfolio": [{"method_id": "SELF_REFINE"}]}}
        self.assertEqual(self.make(record)("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_missing_assessment(self):
        self.assertEqual(self.make(evidence=None)("quality_pack", D, D)["reason"], "ASSESSMENT_RECEIPT_MISSING")

    def test_wrong_resolver(self):
        self.assertEqual(self.make(evidence={**RECEIPT, "resolver_id": "USER"})("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_unverified_receipt(self):
        self.assertEqual(self.make(evidence={**RECEIPT, "verification_state": "UNKNOWN"})("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_different_profile_ref(self):
        self.assertEqual(self.make(evidence={**RECEIPT, "subject_ref": "ui_architect"})("quality_pack", D, D)["status"], "UNRESOLVED")

    def test_reader_failure(self):
        def error(_):
            raise RuntimeError("no DB")
        reader = make_trusted_profile_readback(error, lambda slug, digest: RECEIPT)
        self.assertEqual(reader("quality_pack", D, D)["reason"], "TRUSTED_SOURCE_UNAVAILABLE")

    def test_bad_hash(self):
        self.assertEqual(self.make()("quality_pack", "BAD", D)["reason"], "SOURCE_SHA_INVALID")


class TestSQLBinding(unittest.TestCase):
    def test_parameterized_read_only_queries(self):
        from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import make_postgres_trusted_readback
        calls = []
        def fetch(query, params):
            calls.append((query, params))
            return [REG] if len(params) == 1 else [RECEIPT]
        result = make_postgres_trusted_readback(fetch)("quality_pack", D, D)
        self.assertEqual(result["status"], "VERIFIED_CURRENT")
        self.assertEqual([params for _, params in calls],
                         [("METHOD_PACK_REGISTRY",), ("quality_pack", D)])
        self.assertTrue(all("SELECT" in query and "INSERT" not in query and "DELETE" not in query
                            for query, _ in calls))

    def test_actual_missing_rows_fail_closed(self):
        from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import make_postgres_trusted_readback
        reader = make_postgres_trusted_readback(lambda query, params: [])
        self.assertEqual(reader("quality_pack", D, D)["reason"],
                         "METHOD_REGISTRY_NOT_REGISTERED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
