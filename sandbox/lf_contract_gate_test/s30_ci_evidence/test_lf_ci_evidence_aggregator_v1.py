#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("lf_ci_evidence_aggregator_v1", HERE / "lf_ci_evidence_aggregator_v1.py")
assert SPEC is not None and SPEC.loader is not None
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def load_case() -> dict:
    return json.loads((HERE / "first_real_case_pr788_20260914.json").read_text(encoding="utf-8"))


def rehash(row: dict) -> dict:
    return MOD.finalize_receipt(row)


def authority_receipt(base_sha: str) -> dict:
    row = {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": "CURRENT",
        "ready": True,
        "evidence_revision": base_sha,
        "bound_revision": base_sha,
        "current_revision": base_sha,
        "changed_material_ids": [],
        "bounded_validation_required": False,
    }
    return rehash(row)


def attestation_receipt(repo: str, base_sha: str, target_branch: str) -> dict:
    row = {
        "schema_version": "LF_SOURCE_ATTESTATION_RECEIPT_V1",
        "issuer": "LF_GOVERNED_GIT_BROKER_OR_ATTESTOR",
        "attestor_version": "1.0.0-candidate",
        "authority_level": "CANDIDATE_LOCAL_INTEGRITY",
        "durable_evidence_anchor_required": True,
        "repo_identity": f"github://{repo}",
        "authority_ref": f"refs/heads/{target_branch}",
        "resolved_revision": base_sha,
        "commit_sha": base_sha,
        "tree_sha": "1" * 40,
        "binding_sha256": "2" * 64,
        "material_specs": [],
        "material_fingerprints": {},
        "material_blobs": {},
        "network_required_for_verification": False,
    }
    return rehash(row)


def currentness_provider(request: dict) -> dict:
    row = {
        "receipt_version": "LF_CI_PROVIDER_RECEIPT_V1",
        "provider_code": "CURRENTNESS_AUTHORITY",
        "provider_kind": "SOURCE_ATTESTATION",
        "provider_mode": "OFFLINE_S31_CURRENTNESS",
        "repository_full_name": request["repository_full_name"],
        "candidate_head_sha": request["candidate_head_sha"],
        "base_sha": request["base_sha"],
        "target_branch": request["target_branch"],
        "pr_number": request["pr_number"],
        "result": "PASS",
        "source_ref": "github-actions://currentness-authority/123",
        "observed_at": "2026-09-14T16:45:00Z",
        "authority_receipt": authority_receipt(request["base_sha"]),
        "attestation_receipt": attestation_receipt(request["repository_full_name"], request["base_sha"], request["target_branch"]),
        "durable_anchor": {
            "anchor_type": "GITHUB_WORKFLOW_RUN",
            "workflow_name": "LF Currentness Authority",
            "workflow_path": ".github/workflows/lf-material-currentness.yml",
            "conclusion": "success",
            "authority_revision": request["base_sha"],
            "run_id": 123,
            "source_ref": "github-actions://123",
        },
    }
    return rehash(row)


class CIEvidenceAggregatorV1Test(unittest.TestCase):
    def test_first_real_pr788_passes_ci_only(self) -> None:
        result = MOD.aggregate(load_case())
        self.assertEqual(result["result"], "PASS_CI_EVIDENCE_AGGREGATED")
        self.assertTrue(result["ci_evidence_complete"])
        self.assertEqual(result["verified_provider_codes"], [
            "LF_BOOTSTRAP_REPRODUCIBILITY",
            "LF_CONTRACT_CHECK",
            "VALIDATE_LF_PACKS",
        ])
        for key in (
            "e2e_closed", "qualification_closed", "semantic_review_closed",
            "merge_authorized", "runtime_authorized", "production_authorized", "golden_authorized",
        ):
            self.assertFalse(result[key], key)

    def test_missing_bootstrap_blocks(self) -> None:
        req = load_case()
        req["provider_receipts"] = [r for r in req["provider_receipts"] if r["provider_code"] != "LF_BOOTSTRAP_REPRODUCIBILITY"]
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_MISSING")

    def test_duplicate_provider_blocks(self) -> None:
        req = load_case()
        req["provider_receipts"].append(copy.deepcopy(req["provider_receipts"][0]))
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_DUPLICATE")

    def test_unknown_provider_blocks(self) -> None:
        req = load_case()
        unknown = copy.deepcopy(req["provider_receipts"][0])
        unknown["provider_code"] = "UNKNOWN_CI_PROVIDER"
        unknown = rehash(unknown)
        req["provider_receipts"].append(unknown)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_UNKNOWN")

    def test_subject_head_mismatch_blocks_even_with_valid_receipt_hash(self) -> None:
        req = load_case()
        row = copy.deepcopy(req["provider_receipts"][0])
        row["candidate_head_sha"] = "a" * 40
        req["provider_receipts"][0] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_SUBJECT_MISMATCH")

    def test_provider_fail_blocks(self) -> None:
        req = load_case()
        row = copy.deepcopy(req["provider_receipts"][0])
        row["result"] = "FAIL"
        req["provider_receipts"][0] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_RESULT_INVALID")

    def test_contract_workflow_success_without_deep_proof_blocks(self) -> None:
        req = load_case()
        for i, row in enumerate(req["provider_receipts"]):
            if row["provider_code"] == "LF_CONTRACT_CHECK":
                row = copy.deepcopy(row)
                row.pop("audit_artifact", None)
                row.pop("deep_job_id", None)
                req["provider_receipts"][i] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CONTRACT_DEEP_PROOF_INVALID")

    def test_contract_expired_artifact_blocks(self) -> None:
        req = load_case()
        for i, row in enumerate(req["provider_receipts"]):
            if row["provider_code"] == "LF_CONTRACT_CHECK":
                row = copy.deepcopy(row)
                row["audit_artifact"]["expired"] = True
                req["provider_receipts"][i] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CONTRACT_DEEP_PROOF_INVALID")

    def test_contract_artifact_head_mismatch_blocks(self) -> None:
        req = load_case()
        for i, row in enumerate(req["provider_receipts"]):
            if row["provider_code"] == "LF_CONTRACT_CHECK":
                row = copy.deepcopy(row)
                row["audit_artifact"]["head_sha"] = "b" * 40
                req["provider_receipts"][i] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CONTRACT_DEEP_PROOF_INVALID")

    def test_exact_deep_reuse_is_not_admitted_in_v1(self) -> None:
        req = load_case()
        for i, row in enumerate(req["provider_receipts"]):
            if row["provider_code"] == "LF_CONTRACT_CHECK":
                row = copy.deepcopy(row)
                row["provider_mode"] = "EXACT_DEEP_REUSE"
                req["provider_receipts"][i] = rehash(row)
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_RESULT_INVALID")

    def test_currentness_profile_requires_currentness_provider(self) -> None:
        req = load_case()
        req["evidence_purpose"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["requirement_profile"] = "PRE_MERGE_WITH_CURRENTNESS"
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_PROVIDER_MISSING")

    def test_currentness_profile_passes_with_dual_receipts_and_durable_anchor(self) -> None:
        req = load_case()
        req["evidence_purpose"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["requirement_profile"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["provider_receipts"].append(currentness_provider(req))
        result = MOD.aggregate(req)
        self.assertEqual(result["result"], "PASS_CI_EVIDENCE_AGGREGATED")
        self.assertIn("CURRENTNESS_AUTHORITY", result["verified_provider_codes"])

    def test_currentness_wrong_base_blocks(self) -> None:
        req = load_case()
        req["evidence_purpose"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["requirement_profile"] = "PRE_MERGE_WITH_CURRENTNESS"
        row = currentness_provider(req)
        row["authority_receipt"] = authority_receipt("c" * 40)
        req["provider_receipts"].append(rehash(row))
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CURRENTNESS_RECEIPT_INVALID")

    def test_currentness_without_durable_anchor_blocks(self) -> None:
        req = load_case()
        req["evidence_purpose"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["requirement_profile"] = "PRE_MERGE_WITH_CURRENTNESS"
        row = currentness_provider(req)
        row.pop("durable_anchor")
        req["provider_receipts"].append(rehash(row))
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CURRENTNESS_RECEIPT_INVALID")

    def test_currentness_attestation_tamper_blocks(self) -> None:
        req = load_case()
        req["evidence_purpose"] = "PRE_MERGE_WITH_CURRENTNESS"
        req["requirement_profile"] = "PRE_MERGE_WITH_CURRENTNESS"
        row = currentness_provider(req)
        row["attestation_receipt"]["commit_sha"] = "d" * 40
        req["provider_receipts"].append(rehash(row))
        self.assertEqual(MOD.aggregate(req)["result"], "BLOCK_CI_CURRENTNESS_RECEIPT_INVALID")

    def test_valid_optional_currentness_can_be_superset_of_standard_profile(self) -> None:
        req = load_case()
        req["provider_receipts"].append(currentness_provider(req))
        result = MOD.aggregate(req)
        self.assertEqual(result["result"], "PASS_CI_EVIDENCE_AGGREGATED")
        self.assertIn("CURRENTNESS_AUTHORITY", result["verified_provider_codes"])


if __name__ == "__main__":
    unittest.main()
