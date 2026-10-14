"""Regression of the single Profile Updater assessment -> selector v2 -> plan path.

Only source-only, synthetic evidence. No runtime/model invocation or authority writes.
"""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
CAP = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
ASSESS = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
VAL = ROOT / "skills/profile_creator/validators"
for path in (CAP, ASSESS, VAL):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from capability_selector_v1 import select_capabilities
from capability_selector_v2 import compose_capabilities
from profile_assessment_v1 import assess_profile
import plan_profile_evolution as planner

REGISTRY = json.loads((ROOT / "sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json").read_text(encoding="utf-8"))
CATALOG = [
    {"capability_code": "INDEPENDENT_ASSURANCE", "signal_type": "risk",
     "accepted_values": ["HIGH", "CRITICAL"], "rank": 10, "state": "AVAILABLE"},
    {"capability_code": "PACK_VALIDATION_HARNESS", "signal_type": "complexity",
     "accepted_values": ["MEDIUM", "HIGH"], "rank": 5, "state": "AVAILABLE"},
    {"capability_code": "CAUSAL_EFFECT_LINEAGE", "signal_type": "causal_requirement",
     "accepted_values": ["REQUIRED"], "rank": 15, "state": "AVAILABLE"},
]
POLICY = {"fallback_capabilities": ["PACK_VALIDATION_HARNESS"]}


class CompositionRegression(unittest.TestCase):
    def compose(self, context, registry=None):
        return compose_capabilities(context, CATALOG, POLICY, REGISTRY if registry is None else registry)

    def hostile(self, result):
        return next(m for m in result["method_requirements"] if m["method_id"] == "HOSTILE_CHALLENGE")

    def test_canonical_provider_unchanged(self):
        result = select_capabilities([{"type": "risk", "value": "HIGH"}], CATALOG, POLICY)
        self.assertEqual(result["selected_capabilities"], ["INDEPENDENT_ASSURANCE"])

    def test_missing_evidence_blocks_method_not_base_capability(self):
        result = self.compose({"risk": "HIGH"})
        self.assertEqual(self.hostile(result)["missing_preconditions"], ["candidate_exists"])
        self.assertEqual(self.hostile(result)["missing_evidence"], ["candidate_ref", "challenge_criteria"])
        self.assertFalse(self.hostile(result)["eligible_for_composition"])
        self.assertEqual(result["estimated_cost"]["method_cost_points"], 0)
        self.assertEqual(result["composition_order"], result["selected_capabilities"])
        self.assertFalse(result["execution_authorized"])

    def test_positive_evidence_selects_method_but_never_authorizes(self):
        context = {
            "risk": "HIGH",
            "precondition_evidence": {"candidate_exists": "fixture://candidate"},
            "method_evidence": {"candidate_ref": "fixture://candidate", "challenge_criteria": "fixture://rubric"},
            "budget": {"max_method_cost_points": 3},
        }
        result = self.compose(context)
        self.assertTrue(self.hostile(result)["eligible_for_composition"])
        self.assertEqual(result["estimated_cost"]["method_cost_points"], 3)
        self.assertFalse(result["execution_authorized"])
        self.assertEqual(result["selection_evidence_authority"], "CALLER_DECLARED_UNVERIFIED")

    def test_budget_and_malformed_registry_fail_safely(self):
        context = {"risk": "HIGH",
                   "precondition_evidence": {"candidate_exists": "fixture://a"},
                   "method_evidence": {"candidate_ref": "fixture://b", "challenge_criteria": "fixture://c"},
                   "budget": {"max_method_cost_points": 1}}
        result = self.compose(context)
        self.assertFalse(self.hostile(result)["eligible_for_composition"])
        self.assertEqual(result["estimated_cost"]["method_cost_points"], 0)
        for invalid in (-1, True, "3"):
            other = self.compose({**context, "budget": {"max_method_cost_points": invalid}})
            self.assertEqual(other["fallback_state"], "CAPABILITY_FAILURE")
        registry = copy.deepcopy(REGISTRY)
        registry["execution_permission"] = True
        self.assertEqual(self.compose(context, registry)["fallback_state"], "CAPABILITY_FAILURE")
        registry = copy.deepcopy(REGISTRY)
        registry["methods"].append(registry["methods"][0])
        self.assertEqual(self.compose(context, registry)["fallback_state"], "CAPABILITY_FAILURE")

    def test_twelve_signal_patterns_without_method_evidence(self):
        scenarios = [
            {"causal_requirement": "REQUIRED"}, {"risk": "HIGH"},
            {"evidence_paths": "MULTIPLE_INDEPENDENT"}, {},
            {"complexity": "MEDIUM"}, {"risk": "HIGH", "complexity": "MEDIUM"},
            {"complexity": "HIGH"}, {"complexity": "MEDIUM"},
            {"causal_requirement": "REQUIRED"}, {"risk": "HIGH"},
            {"optimization_need": "REQUIRED"},
            {"risk": "HIGH", "causal_requirement": "REQUIRED"},
        ]
        self.assertEqual(len(scenarios), 12)
        for context in scenarios:
            result = self.compose(context)
            self.assertFalse(result["execution_authorized"])
            self.assertTrue(all(not m["eligible_for_composition"] for m in result["method_requirements"]))

    def test_plan_forwards_evidence_and_remains_read_only(self):
        proof = lambda state: {"status": state, "refs": ["fixture://evidence"]}
        data = {"evidence": {"domain_task_uplift": proof("FAIL"),
                             "architecture_fit": proof("PASS"),
                             "strategy_routing": proof("FAIL")},
                "signals": {"risk": "HIGH", "complexity": "MEDIUM"},
                "precondition_evidence": {"candidate_exists": "fixture://candidate"},
                "method_evidence": {"candidate_ref": "fixture://candidate", "challenge_criteria": "fixture://rubric"}}
        with patch.object(planner, "evaluate_s26", return_value={"decision": "NO_UPDATE_REQUIRED", "blocking_codes": []}), patch.object(planner, "evaluate_learning_preflight", return_value={"status": "PASS"}):
            result = planner.build_evolution_plan(ROOT, "quality_pack", {}, data, CATALOG, POLICY, REGISTRY)
        self.assertEqual(result["evolution_mode"], "SPECIALIZE")
        self.assertTrue(self.hostile(result["selection"])["eligible_for_composition"])
        self.assertFalse(result["profile_source_write_allowed"])
        self.assertFalse(result["automatic_production_activation"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
