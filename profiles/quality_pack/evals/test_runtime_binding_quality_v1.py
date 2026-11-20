#!/usr/bin/env python3
"""Negative checks for the additive Quality Pack native binding."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from runtime_validate import validate
from runtime_semantic_utility import evaluate


def conservative():
    return {
        "review_id": "QUALITY-B2B-CARGA-002-CONSERVATIVE",
        "reviewed_artifact": "github://cristhianlujan/claude-persona-lf-patch@b9409cf9c703ff66942f268e00c9d61e483d34c2/sandbox/lf_contract_gate_test/edge_function_operation/fixtures/b2b_carga002_solution_candidate_v1.json",
        "verdict": "RETURN_TO_ORCHESTRATOR",
        "score_breakdown": {
            "contract_schema_compliance": 4, "evidence_integrity": 3,
            "lf_safety_governance": 4, "handoff_readiness": 3,
            "leakage_scope_control": 5, "total": 19,
        },
        "evidence_map": [{
            "area": "candidate_artifact",
            "source_ref": "github://cristhianlujan/claude-persona-lf-patch@b9409cf9c703ff66942f268e00c9d61e483d34c2/sandbox/lf_contract_gate_test/edge_function_operation/fixtures/b2b_carga002_solution_candidate_v1.json",
            "observed": "GitHub candidate retrieved; independent 5-gate proof missing",
            "status": "SOURCE_OBSERVED_NOT_GOV037_PASS",
        }],
        "blocking_codes": ["QUALITY_SEMANTIC_INDEPENDENCE_NOT_PROVEN"],
        "repair_actions": [{
            "target_worker": "ACT-0001_ORCHESTRATOR",
            "missing_or_failed_item": "Independent Quality semantic receipt",
            "why_it_fails": "Producer Step70 has NOT_PROVEN independence",
            "required_fix": "Resolve exact SHA and independent quality receipt",
            "blocking_code": "QUALITY_SEMANTIC_INDEPENDENCE_NOT_PROVEN",
        }],
        "remaining_risks": ["Not a live backend integration test"],
        "next_gate": "ACT-0001_QUALITY_INDEPENDENT_SEMANTIC_REVIEW_REQUIRED",
        "routing": {
            "activation_path": "ROUTER", "via": "ORCHESTRATOR",
            "pipeline_action": "RETURN_TO_ORCHESTRATOR",
            "resolution_target": "AUTHORITY_OR_CONTEXT_RESOLUTION",
        },
    }


class QualityNativeGateTests(unittest.TestCase):
    def test_utility_is_not_an_independent_judge(self):
        outcome = evaluate(conservative(), {"status": "PASS"})
        self.assertEqual(outcome["status"], "PASS")
        self.assertIs(outcome["independent_review_executed"], False)

    def test_conservative_return_is_structurally_valid_not_pass(self):
        self.assertEqual(validate(conservative()), {"valid": True, "errors": []})

    def test_broken_score(self):
        payload = conservative()
        payload["score_breakdown"]["total"] = 25
        self.assertIn("QUALITY_SCORE_TOTAL_MISMATCH", validate(payload)["errors"])

    def test_direct_route_is_rejected(self):
        payload = conservative()
        payload["routing"]["target_profile"] = "PERFIL-QUALITY-PACK"
        self.assertFalse(validate(payload)["valid"])

    def test_missing_repair_action_is_rejected(self):
        payload = conservative()
        payload["repair_actions"] = []
        self.assertIn("QUALITY_RETURN_REPAIR_ACTION_REQUIRED", validate(payload)["errors"])

    def test_unsupported_evidence_is_not_silent_pass(self):
        payload = conservative()
        payload["evidence_map"] = [{"area": "missing", "source_ref": "pass", "observed": "", "status": "PASS"}]
        self.assertFalse(validate(payload)["valid"])

    def test_positive_verdict_requires_independent_gov037_bundle(self):
        payload = conservative()
        payload["verdict"] = "PASS_TO_COMPOSER"
        payload["score_breakdown"] = {
            "contract_schema_compliance": 5, "evidence_integrity": 5,
            "lf_safety_governance": 5, "handoff_readiness": 5,
            "leakage_scope_control": 5, "total": 25,
        }
        payload["blocking_codes"] = []
        payload["repair_actions"] = []
        payload["routing"]["pipeline_action"] = "CONTINUE"
        payload["routing"]["resolution_target"] = "COMPOSER"
        self.assertIn("QUALITY_GOV037_FULL_GATE_BUNDLE_REQUIRED", validate(payload)["errors"])
        payload["quality_gate_bundle"] = {
            "final_verdict": "PASS_TO_COMPOSER",
            "gates": {name: {"applicable": True, "status": "PASS", "evidence": [{"ref": "fake", "sha256": "a" * 64}]}
                      for name in ("structural", "provenance", "semantic", "artifact", "upstream")},
        }
        self.assertFalse(validate(payload)["valid"])


if __name__ == "__main__":
    unittest.main()
