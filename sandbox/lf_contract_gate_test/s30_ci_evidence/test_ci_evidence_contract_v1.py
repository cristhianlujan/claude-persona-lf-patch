#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / "LF_CI_EVIDENCE_CONTRACT_V1.json").read_text(encoding="utf-8"))
SOURCE = (HERE / "lf_ci_evidence_aggregator_v1.py").read_text(encoding="utf-8")


class CIEvidenceContractV1Test(unittest.TestCase):
    def test_aggregator_is_offline_and_not_a_provider(self) -> None:
        boundary = CONTRACT["authority_boundary"]
        self.assertFalse(boundary["aggregator_is_ci_producer"])
        self.assertFalse(boundary["aggregator_may_call_github_rest"])
        self.assertFalse(boundary["aggregator_may_call_remote_currentness"])
        lower = SOURCE.lower()
        for forbidden in ("urllib", "requests", "api.github.com", "gh api", "subprocess", "urlopen"):
            self.assertNotIn(forbidden, lower)

    def test_contract_check_requires_real_deep_proof(self) -> None:
        spec = CONTRACT["provider_codes"]["LF_CONTRACT_CHECK"]
        self.assertEqual(spec["accepted_modes"], ["DEEP_RUN"])
        self.assertFalse(spec["exact_deep_reuse_supported_in_v1"])
        self.assertEqual(spec["deep_job_name"], "lf-contract-check")
        self.assertEqual(spec["audit_artifact_name_pattern"], "r8-continuous-audit-{run_id}")

    def test_currentness_keeps_base_authority_separate_from_candidate_head(self) -> None:
        boundary = CONTRACT["authority_boundary"]
        spec = CONTRACT["provider_codes"]["CURRENTNESS_AUTHORITY"]
        self.assertEqual(boundary["currentness_provider"], "S31_CURRENTNESS_AUTHORITY")
        self.assertFalse(boundary["aggregator_may_call_remote_currentness"])
        self.assertEqual(spec["authority_revision_binding"], "AGGREGATE_BASE_SHA")
        self.assertEqual(spec["authority_ref_binding"], "refs/heads/{target_branch}")
        self.assertEqual(spec["authority_receipt_schema"], "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1")
        self.assertEqual(spec["attestation_receipt_schema"], "LF_SOURCE_ATTESTATION_RECEIPT_V1")
        self.assertTrue(spec["durable_anchor_required"])
        self.assertEqual(spec["provider_kind"], "SOURCE_ATTESTATION")
        self.assertFalse(spec["network_reverification_by_aggregator"])

    def test_post_merge_v7_is_not_generic_ci_authority(self) -> None:
        spec = CONTRACT["provider_codes"]["EXTERNAL_RECONCILIATION_V7"]
        self.assertEqual(spec["scope"], "LF_SKILL_ARTIFACT_POST_MERGE_ONLY")
        self.assertTrue(spec["not_generic_ci_authority"])

    def test_ci_pass_never_closes_other_authorities(self) -> None:
        forbidden = set(CONTRACT["forbidden_claims"])
        expected = {
            "E2E_PASS_FROM_CI_PASS",
            "QUALIFICATION_PASS_FROM_CI_PASS",
            "SEMANTIC_REVIEW_PASS_FROM_CI_PASS",
            "MERGE_AUTHORIZED_FROM_CI_PASS",
            "RUNTIME_AUTHORIZED_FROM_CI_PASS",
            "PRODUCTION_AUTHORIZED_FROM_CI_PASS",
            "GOLDEN_AUTHORIZED_FROM_CI_PASS",
        }
        self.assertTrue(expected.issubset(forbidden))
        self.assertEqual(CONTRACT["claim_ceiling"], "CI_EVIDENCE_ONLY_NOT_DOMAIN_CLOSURE")

    def test_profiles_are_explicit_not_heuristic(self) -> None:
        profiles = CONTRACT["requirement_profiles"]
        self.assertEqual(
            profiles["PRE_MERGE_STANDARD"]["required_providers"],
            ["VALIDATE_LF_PACKS", "LF_CONTRACT_CHECK", "LF_BOOTSTRAP_REPRODUCIBILITY"],
        )
        self.assertIn("CURRENTNESS_AUTHORITY", profiles["PRE_MERGE_WITH_CURRENTNESS"]["required_providers"])
        self.assertEqual(
            profiles["POST_MERGE_ARTIFACT_RECONCILIATION"]["required_providers"],
            ["CURRENTNESS_AUTHORITY", "EXTERNAL_RECONCILIATION_V7"],
        )


if __name__ == "__main__":
    unittest.main()
