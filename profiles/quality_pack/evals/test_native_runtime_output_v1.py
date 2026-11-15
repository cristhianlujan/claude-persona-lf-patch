#!/usr/bin/env python3
"""Regression negatives for native Quality Step50 binding (candidate-only)."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from validate_native_runtime_output import validate


def nonpass():
    return {
        "review_id": "QUALITY-NATIVE-BOUND-TEST",
        "reviewed_artifact": "github://owner/repo@" + "a" * 40 + "/candidate.json",
        "verdict": "RETURN_TO_ORCHESTRATOR",
        "score_breakdown": {
            "contract_schema_compliance": 4, "evidence_integrity": 3,
            "lf_safety_governance": 4, "handoff_readiness": 3,
            "leakage_scope_control": 5, "total": 19,
        },
        "evidence_map": [{"source_ref": "github://owner/repo@" + "a" * 40 + "/candidate.json"}],
        "blocking_codes": ["QUALITY_INDEPENDENCE_UNPROVEN"],
        "repair_actions": [{"required_fix": "Independent resolution required"}],
        "remaining_risks": ["No backend integration test"],
        "next_gate": "ACT-0001_INDEPENDENT_REVIEW",
        "routing": {
            "activation_path": "ROUTER", "via": "ORCHESTRATOR",
            "pipeline_action": "RETURN_TO_ORCHESTRATOR",
            "resolution_target": "AUTHORITY_OR_CONTEXT_RESOLUTION",
        },
    }


class NativeQualityBindingTests(unittest.TestCase):
    def test_nonpass_is_structurally_admitted_without_pass_claim(self):
        self.assertTrue(validate(nonpass())["valid"])

    def test_producer_or_candidate_cannot_self_authorize_pass(self):
        data = nonpass()
        data["verdict"] = "PASS_TO_COMPOSER"
        data["blocking_codes"] = []
        data["repair_actions"] = []
        data["routing"]["pipeline_action"] = "CONTINUE"
        data["routing"]["resolution_target"] = "COMPOSER"
        self.assertIn("QUALITY_PASS_INDEPENDENT_GOV037_GATE_REQUIRED", validate(data)["errors"])

    def test_score_mismatch_rejected(self):
        data = nonpass()
        data["score_breakdown"]["total"] = 25
        self.assertIn("QUALITY_SCORE_TOTAL_MISMATCH", validate(data)["errors"])

    def test_direct_unauthorized_routing_rejected(self):
        data = nonpass()
        data["routing"]["via"] = "QUALITY_DIRECT"
        self.assertIn("QUALITY_ROUTING_MUST_RETURN_THROUGH_ORCHESTRATOR", validate(data)["errors"])

    def test_nonpass_without_blocking_code_rejected(self):
        data = nonpass()
        data["blocking_codes"] = []
        self.assertIn("QUALITY_NONPASS_BLOCKING_CODE_REQUIRED", validate(data)["errors"])

    def test_evidence_declaration_only_not_approval(self):
        data = nonpass()
        data["evidence_map"] = []
        self.assertIn("QUALITY_EVIDENCE_MAP_REQUIRED", validate(data)["errors"])

    def test_promotion_false_by_default_and_cannot_claim_true(self):
        data = nonpass()
        data["promotion_authorized"] = True
        self.assertIn("QUALITY_PROMOTION_AUTHORITY_FORBIDDEN", validate(data)["errors"])


if __name__ == "__main__":
    unittest.main()
