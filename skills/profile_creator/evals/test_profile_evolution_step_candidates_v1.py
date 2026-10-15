"""Isolated positive/negative checks for the proposed two Updater step receipts.

No mock result is an OIDC/GPT Native/independent provider attestation.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_evolution_step_candidates_v1 import derive_step_candidates


def plan(mode="PATCH", *, verified=True, eligible=True, sufficient=True, blockers=None):
    return {
        "schema": "PROFILE_EVOLUTION_PLAN_V1",
        "evolution_mode": mode,
        "blocking_codes": list(blockers or []),
        "profile_assessment": {
            "assessment_status": "EVIDENCE_SUFFICIENT" if sufficient else "NEEDS_MORE_EVIDENCE",
        },
        "source_readback": {"status": "VERIFIED_CURRENT" if verified else "UNRESOLVED"},
        "selection": {
            "schema": "CAPABILITY_SELECTOR_COMPOSITION_V2",
            "selected_capabilities": ["PACK_VALIDATION_HARNESS"] if eligible else [],
            "method_requirements": [{
                "method_id": "VERIFIER_GUIDED_SEARCH", "eligible_for_composition": eligible,
                "within_budget": eligible,
            }],
            "fallback_state": "CLEAR",
        },
        "candidate_materialization_allowed": mode not in {None, "NO_CHANGE"} and sufficient and verified and not blockers,
    }


class StepCandidateChecks(unittest.TestCase):
    def test_update_is_advisory(self):
        steps = derive_step_candidates(plan())
        self.assertEqual(steps["evolution_decision"]["decision"], "UPDATE_CANDIDATE")
        self.assertEqual(steps["method_selection"]["selected_method_ids"], ["VERIFIER_GUIDED_SEARCH"])
        self.assertFalse(steps["method_selection"]["method_execution_permitted"])
        self.assertFalse(steps["evolution_decision"]["github_write_permitted"])

    def test_no_change_is_advisory_without_write(self):
        steps = derive_step_candidates(plan("NO_CHANGE", eligible=False))
        self.assertEqual(steps["evolution_decision"]["decision"], "NO_CHANGE_CANDIDATE")
        self.assertEqual(steps["method_selection"]["status"], "NO_ADDITIONAL_METHOD_SELECTED")
        self.assertFalse(steps["evolution_decision"]["operational_decision_recorded"])

    def test_unresolved_method_authority(self):
        steps = derive_step_candidates(plan(verified=False))
        self.assertEqual(steps["method_selection"]["status"], "AUTHORITY_READBACK_REQUIRED")
        self.assertEqual(steps["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_no_change_without_authority_cannot_pass(self):
        self.assertEqual(derive_step_candidates(plan("NO_CHANGE", verified=False))["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_insufficient_assessment_cannot_pass(self):
        self.assertEqual(derive_step_candidates(plan(sufficient=False))["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_blocked_learning_prevents_update(self):
        self.assertEqual(derive_step_candidates(plan(blockers=["BLOCKED_LEARNING_PREFLIGHT"]))["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_selector_contradiction(self):
        data = plan()
        data["selection"]["fallback_state"] = "CONTRADICTORY"
        self.assertEqual(derive_step_candidates(data)["method_selection"]["status"], "SELECTOR_UNRESOLVED")
        self.assertEqual(derive_step_candidates(data)["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_selector_failure(self):
        data = plan()
        data["selection"]["fallback_state"] = "CAPABILITY_FAILURE"
        self.assertEqual(derive_step_candidates(data)["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_no_mode(self):
        self.assertEqual(derive_step_candidates(plan(None))["evolution_decision"]["decision"], "NEEDS_MORE_EVIDENCE")

    def test_invalid_mode(self):
        with self.assertRaisesRegex(ValueError, "PROFILE_EVOLUTION_MODE_INVALID"):
            derive_step_candidates(plan("MERGE"))

    def test_invalid_schema(self):
        data = plan()
        data["schema"] = "UNKNOWN"
        with self.assertRaisesRegex(ValueError, "PROFILE_EVOLUTION_PLAN_SCHEMA_INVALID"):
            derive_step_candidates(data)

    def test_duplicate_methods(self):
        data = plan()
        data["selection"]["method_requirements"].append(data["selection"]["method_requirements"][0].copy())
        with self.assertRaisesRegex(ValueError, "PROFILE_EVOLUTION_METHOD_DUPLICATE"):
            derive_step_candidates(data)

    def test_budget_conflict(self):
        data = plan()
        data["selection"]["method_requirements"][0]["within_budget"] = False
        with self.assertRaisesRegex(ValueError, "PROFILE_EVOLUTION_METHOD_BUDGET_CONFLICT"):
            derive_step_candidates(data)

    def test_missing_evidence_stays_bounded(self):
        data = plan(eligible=False)
        data["selection"]["method_requirements"][0]["missing_evidence"] = ["verifier_ref"]
        result = derive_step_candidates(data)
        self.assertEqual(result["method_selection"]["selected_method_ids"], [])
        self.assertFalse(result["method_selection"]["method_execution_permitted"])

    def test_all_modes_are_non_operational(self):
        for mode in ("PATCH", "SPECIALIZE", "ADAPT", "REARCHITECT", "OPTIMIZE", "NO_CHANGE"):
            with self.subTest(mode=mode):
                results = derive_step_candidates(plan(mode))
                self.assertFalse(results["evolution_decision"]["operational_decision_recorded"])
                self.assertFalse(results["evolution_decision"]["github_write_permitted"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
