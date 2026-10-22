"""Regression of the single Profile Updater assessment -> selector v2 -> plan path.

Only source-only, synthetic evidence. No runtime/model invocation or authority writes.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
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



class AuthorityReadbackRegression(unittest.TestCase):
    """Source-only test doubles; never a genuine Supabase authority receipt."""

    def _plan(self, reader=None, mutate_data=None, mutate_registry=None):
        proof = lambda status: {"status": status, "refs": ["fixture://evidence"]}
        data = {"evidence": {"domain_task_uplift": proof("FAIL"),
                             "architecture_fit": proof("PASS")},
                "signals": {"risk": "HIGH", "complexity": "MEDIUM"}}
        if mutate_data:
            data.update(mutate_data)
        registry = dict(REGISTRY)
        if mutate_registry:
            registry.update(mutate_registry)
        with patch.object(planner, "evaluate_s26", return_value={"decision": "NO_UPDATE_REQUIRED", "blocking_codes": []}), patch.object(planner, "evaluate_learning_preflight", return_value={"status": "PASS"}):
            return planner.build_evolution_plan(ROOT, "quality_pack", {}, data, CATALOG, POLICY, registry, trusted_source_readback=reader)

    def test_missing_reader_fails_closed(self):
        result = self._plan()
        self.assertIn("METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED", result["blocking_codes"])
        self.assertFalse(result["candidate_materialization_allowed"])
        self.assertFalse(result["profile_source_write_allowed"])
        self.assertEqual(result["source_readback"]["status"], "UNRESOLVED")

    def test_caller_claims_do_not_grant_authority(self):
        result = self._plan(mutate_data={"method_catalog_released": True}, mutate_registry={"provider_verified": True})
        self.assertFalse(result["candidate_materialization_allowed"])

    def test_stale_and_failing_readback_block(self):
        stale = lambda slug, reg, assess: {"status": "VERIFIED_CURRENT",
            "registry_sha256": reg, "assessment_sha256": "stale", "registry_version": "1.0.0",
            "authority_ref": "fixture://not-real", "method_catalog_released": True,
            "assessment_evidence_verified": True}
        failure = lambda slug, reg, assess: (_ for _ in ()).throw(RuntimeError("offline"))
        for reader in (stale, failure):
            with self.subTest(reader=reader):
                result = self._plan(reader=reader)
                self.assertFalse(result["candidate_materialization_allowed"])
                self.assertIn("METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED", result["blocking_codes"])

    def test_matching_reader_enables_only_reversible_candidate(self):
        # Synthetic trusted-reader test double; no claim about current Supabase.
        def fake_reader(slug, reg, assess):
            return {"status": "VERIFIED_CURRENT",
                "registry_sha256": reg, "assessment_sha256": assess,
                "registry_version": "test-fixture", "authority_ref": "fixture://trusted-mock",
                "method_catalog_released": True, "assessment_evidence_verified": True,
                "qualified_method_ids": []}
        result = self._plan(reader=fake_reader)
        self.assertEqual(result["source_readback"]["status"], "VERIFIED_CURRENT")
        self.assertTrue(result["candidate_materialization_allowed"])
        self.assertFalse(result["profile_source_write_allowed"])
        self.assertFalse(result["automatic_runtime_activation"])
        self.assertFalse(result["automatic_production_activation"])

    def test_selected_unqualified_method_blocks_candidacy(self):
        data = {"precondition_evidence": {"candidate_exists": "fixture://candidate"},
                "method_evidence": {"candidate_ref": "fixture://candidate",
                                    "challenge_criteria": "fixture://rubric"}}
        def fake_reader(slug, reg, assess):
            return {"status": "VERIFIED_CURRENT",
                    "registry_sha256": reg, "assessment_sha256": assess,
                    "registry_version": "test", "authority_ref": "fixture://readback",
                    "method_catalog_released": True, "assessment_evidence_verified": True,
                    "qualified_method_ids": []}
        result = self._plan(reader=fake_reader, mutate_data=data)
        self.assertIn("METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED", result["blocking_codes"])
        self.assertFalse(result["candidate_materialization_allowed"])



class SourceBoundEvidenceRegression(unittest.TestCase):
    """Source/evidence callbacks are simulated; never real Ledger receipts."""

    def test_bound_assessment_and_rejection_of_stale_refs(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            skill = repo / "profiles/quality_pack/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text("# source under test\n", encoding="utf-8")
            sha = hashlib.sha256(skill.read_bytes()).hexdigest()
            head = "a" * 40
            def src(slug, revision):
                return {"status": "VERIFIED_CURRENT", "profile_slug": slug,
                        "source_head_sha": revision,
                        "source_path": "profiles/quality_pack/SKILL.md",
                        "source_sha256": sha,
                        "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                        "resolver_active": True,
                        "resolver_trust_level": "TRUSTED_PROVIDER_BOUND"}
            def proof(ref, slug, revision):
                return {"status": "VERIFIED", "ref": ref,
                        "profile_slug": slug, "source_head_sha": revision,
                        "observed_status": "FAIL",
                        "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                        "resolver_active": True,
                        "resolver_trust_level": "TRUSTED_PROVIDER_BOUND"}
            data = {"evidence": {
                "structural_compatibility": {"status": "PASS", "refs": ["s26://13-of-13"]},
                "domain_task_uplift": {"status": "FAIL", "refs": ["proof://domain"]},
                "architecture_fit": {"status": "PASS", "refs": ["proof://arch"]}},
                "signals": {"risk": "MEDIUM"}}
            normalized, candidate = planner._verify_assessment_input(
                repo, "quality_pack", head, data, src, proof)
            self.assertEqual(candidate["status"], "EVIDENCE_CHECKED")
            self.assertEqual(normalized["evidence"]["domain_task_uplift"]["status"], "FAIL")
            self.assertFalse(candidate["receipt_issued"])
            self.assertFalse(candidate["ledger_write_performed"])
            self.assertEqual(candidate["subject_type"], "PROFILE_ASSESSMENT")
            self.assertIn("architecture_fit", candidate["unknown_dimensions"])
            invalid = lambda ref, slug, revision: {**proof(ref,slug,revision),
                "source_head_sha": "b"*40}
            norm, _ = planner._verify_assessment_input(
                repo, "quality_pack", head, data, src, invalid)
            self.assertEqual(norm["evidence"]["domain_task_uplift"]["status"], "UNKNOWN")
            self.assertEqual(norm["evidence"]["domain_task_uplift"]["refs"], [])
            skill.write_text("altered", encoding="utf-8")
            _, stale = planner._verify_assessment_input(
                repo, "quality_pack", head, data, src, proof)
            self.assertEqual(stale["reason"], "PROFILE_SOURCE_NOT_VERIFIED")

    def test_missing_trusted_reader_cannot_issue_receipt(self):
        normalized, result = planner._verify_assessment_input(
            ROOT, "quality_pack", "a"*40, {"evidence": {}, "signals": {}}, None, None)
        self.assertEqual(result["status"], "UNVERIFIED")
        self.assertFalse(result["receipt_issued"])
        self.assertFalse(result["ledger_write_performed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
