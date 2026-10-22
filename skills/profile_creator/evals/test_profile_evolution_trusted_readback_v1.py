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
METHOD_RECEIPT = {"subject_type": "METHOD_QUALIFICATION",
                  "subject_ref": "SELF_REFINE@1.0.0", "provider_ref": "evidence://holdout",
                  "verification_state": "VERIFIED", "resolver_id": "LF_SUPABASE_READBACK_V1",
                  "resolver_active": True, "resolver_trust_level": "TRUSTED_PROVIDER_BOUND",
                  "receipt_id": "method-receipt"}
RECEIPT = {"subject_type": "PROFILE_ASSESSMENT", "subject_ref": "quality_pack",
           "receipt_kind": "PROFILE_ASSESSMENT_RESULT",
           "source_head_sha": "a" * 40,
           "subject_sha256": D, "verification_state": "VERIFIED",
           "provider": "SUPABASE",
           "verification_method": "SUPABASE_SQL_READBACK_PLUS_DB_DIGEST",
           "provider_ref": "supabase://verified-profile-assessment",
           "receipt_sha256": "d" * 64, "verified_at": "2026-10-22T01:29:16Z",
           "resolver_id": "LF_SUPABASE_READBACK_V1", "resolver_active": True,
           "resolver_trust_level": "TRUSTED_PROVIDER_BOUND",
           "receipt_id": "9f758577-c9f6-4744-852b-a03827b466f6"}


class TestTrustedReadback(unittest.TestCase):
    def make(self, cap=REG, evidence=RECEIPT, method_receipt=METHOD_RECEIPT):
        return make_trusted_profile_readback(
            lambda name: cap, lambda slug, digest: evidence,
            lambda mid, version, ref: method_receipt)

    def test_positive_remains_receipt_only(self):
        result = self.make()("quality_pack", D, D)
        self.assertEqual(result["status"], "VERIFIED_CURRENT")
        self.assertEqual(result["qualified_method_ids"], ["SELF_REFINE"])
        self.assertTrue(result["method_catalog_released"])
        self.assertEqual(result["assessment_source_head_sha"], "a" * 40)

    def test_real_github_resolver_contract_with_empty_portfolio(self):
        # Fixture modeled on existing provider receipt; not a live SQL verification.
        empty = {**REG, "manifest": {
            "catalog_payload_sha256": D, "qualified_method_portfolio": []}}
        valid = {**RECEIPT,
                 "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                 "provider": "GITHUB",
                 "verification_method": "GITHUB_API_READBACK_PLUS_OFFLINE_HASH",
                 "provider_ref": "github-api://repos/owner/repo@" + "a" * 40 + "/actions/runs/1"}
        result = self.make(cap=empty, evidence=valid)("quality_pack", D, D)
        self.assertEqual(result["status"], "VERIFIED_CURRENT")
        self.assertEqual(result["qualified_method_ids"], [])
        self.assertEqual(result["assessment_receipt_ref"], valid["receipt_id"])
        self.assertEqual(result["assessment_source_head_sha"], "a" * 40)

    def test_unmatched_github_resolver_provider_or_revision_blocks(self):
        valid = {**RECEIPT, "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                 "provider": "GITHUB",
                 "verification_method": "GITHUB_API_READBACK_PLUS_OFFLINE_HASH",
                 "provider_ref": "github-api://repos/owner/repo@" + "a" * 40 + "/actions/runs/1"}
        bad = (
            {**valid, "provider": "SUPABASE"},
            {**valid, "verification_method": "OTHER"},
            {**valid, "provider_ref": "github-api://repos/owner/repo@" + "b" * 40 + "/actions/runs/1"},
            {**valid, "source_head_sha": "b" * 40},
            {**valid, "receipt_sha256": "wrong"},
            {**valid, "verified_at": None},
            {**valid, "resolver_active": False},
            {**valid, "receipt_kind": "SOURCE_SNAPSHOT"},
            {**valid, "receipt_id": "not-a-uuid"},
        )
        for receipt in bad:
            with self.subTest(receipt=receipt):
                result = self.make(evidence=receipt)("quality_pack", D, D)
                self.assertEqual(result["reason"], "ASSESSMENT_RECEIPT_INVALID_OR_UNTRUSTED")

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

    def test_method_missing_ledger_receipt(self):
        self.assertEqual(self.make(method_receipt=None)("quality_pack", D, D)["reason"],
                         "METHOD_QUALIFICATION_RECEIPT_UNVERIFIED")

    def test_method_receipt_wrong_benchmark(self):
        wrong = {**METHOD_RECEIPT, "provider_ref": "forged"}
        self.assertEqual(self.make(method_receipt=wrong)("quality_pack", D, D)["reason"],
                         "METHOD_QUALIFICATION_RECEIPT_UNVERIFIED")

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
        reader = make_trusted_profile_readback(error, lambda slug, digest: RECEIPT,
                                               lambda mid, version, ref: METHOD_RECEIPT)
        self.assertEqual(reader("quality_pack", D, D)["reason"], "TRUSTED_SOURCE_UNAVAILABLE")

    def test_bad_hash(self):
        self.assertEqual(self.make()("quality_pack", "BAD", D)["reason"], "SOURCE_SHA_INVALID")


class TestSQLBinding(unittest.TestCase):
    def test_parameterized_read_only_queries(self):
        from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import make_postgres_trusted_readback
        calls = []
        def fetch(query, params):
            calls.append((query, params))
            return [REG] if len(params) == 1 else [METHOD_RECEIPT] if "@" in params[0] else [RECEIPT]
        result = make_postgres_trusted_readback(fetch)("quality_pack", D, D)
        self.assertEqual(result["status"], "VERIFIED_CURRENT")
        self.assertEqual([params for _, params in calls],
                         [("METHOD_PACK_REGISTRY",), ("quality_pack", D),
                          ("SELF_REFINE@1.0.0", "evidence://holdout")])
        self.assertTrue(all("SELECT" in query and "INSERT" not in query and "DELETE" not in query
                            for query, _ in calls))

    def test_actual_missing_rows_fail_closed(self):
        from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import make_postgres_trusted_readback
        reader = make_postgres_trusted_readback(lambda query, params: [])
        self.assertEqual(reader("quality_pack", D, D)["reason"],
                         "METHOD_REGISTRY_NOT_REGISTERED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
