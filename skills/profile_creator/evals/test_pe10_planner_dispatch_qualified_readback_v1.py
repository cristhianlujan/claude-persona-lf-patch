"""PE10: real planner -> dispatcher boundary, using explicitly labelled fixtures.

Prevents losing a verified method portfolio between plan_profile_evolution
and execute_profile_evolution_v02. This is a SOURCE integration regression,
not evidence of provider qualification or production cutover.
"""
from __future__ import annotations

import sys
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
import plan_profile_evolution as planner
from execute_profile_evolution_v02 import execute_profile_evolution_v02

HEAD = "a" * 40
DIGEST = "b" * 64


def make_plan(*, verified=True, qualified=("SELF_REFINE",)):
    methods = [{
        "method_id": "SELF_REFINE",
        "eligible_for_composition": True,
        "within_budget": True,
    }]
    composition = {
        "method_requirements": methods,
        "selected_capabilities": [],
        "execution_authorized": False,
        "fallback_state": "CLEAR",
    }

    def trusted_readback(slug, registry_sha, assessment_sha):
        assert slug == "quality_pack"
        return {
            "status": "VERIFIED_CURRENT" if verified else "UNRESOLVED",
            "registry_sha256": registry_sha,
            "assessment_sha256": assessment_sha,
            "registry_version": "1.0.0",
            "authority_ref": "fixture://trusted-authority",
            "method_catalog_released": True,
            "assessment_evidence_verified": True,
            "qualified_method_ids": list(qualified),
            "assessment_receipt_ref": "fixture-assessment-receipt",
        }

    with ExitStack() as stack:
        for name, value in (
            ("evaluate_s26", {"decision": "NO_UPDATE_REQUIRED"}),
            ("evaluate_learning_preflight", {"status": "PASS"}),
            ("assess_profile", {
                "assessment_status": "EVIDENCE_SUFFICIENT",
                "profile_gaps": [], "evolution_mode": "ADAPT",
            }),
            ("compose_capabilities", composition),
            ("candidate_output_gate", {}),
        ):
            stack.enter_context(patch.object(planner, name, return_value=value))
        return planner.build_evolution_plan(
            ROOT, "quality_pack", {}, {"signals": {}, "evidence": {}},
            [], {}, {"schema_version": "fixture", "methods": []},
            trusted_source_readback=trusted_readback,
        )


class PlannerDispatcherReadbackRegression(unittest.TestCase):
    def test_verified_methods_survive_planner_to_dispatcher(self):
        plan = make_plan()
        self.assertEqual(plan["source_readback"]["status"], "VERIFIED_CURRENT")
        self.assertEqual(plan["source_readback"]["qualified_method_ids"], ["SELF_REFINE"])
        self.assertEqual(plan["blocking_codes"], [])
        trace = []

        def method_readback(mid, run_id, source_sha):
            trace.append("readback")
            return {
                "method_id": mid, "qualification_state": "QUALIFIED",
                "verification_state": "VERIFIED", "current_source_sha": source_sha,
                "exact_version": "1.0.0",
                "qualification_receipt_id": "fixture-only-not-attested",
                "method_subject_sha256": DIGEST,
            }

        def invoke(mid, payload):
            trace.append("invoke")
            return {
                "method_id": mid, "execution_id": payload["execution_id"],
                "source_head_sha": payload["source_head_sha"],
                "status": "COMPLETED", "receipt_id": "fixture-only-not-attested",
                "output_sha256": DIGEST,
            }

        def verify(*args):
            trace.append("verify")
            return True

        def record(run_id, selection, decision):
            trace.append("record")
            self.assertEqual(selection["selected_methods"][0]["method_id"], "SELF_REFINE")
            self.assertFalse(selection["method_execution_permitted"])
            self.assertFalse(decision["github_write_permitted"])
            return {
                "execution_id": run_id,
                "method_selection": "STEP_PASS_WITH_EVIDENCE",
                "evolution_decision": "STEP_PASS_WITH_EVIDENCE",
            }

        result = execute_profile_evolution_v02(
            plan,
            operation_binding={
                "execution_id": "FIXTURE-PE10-E2E",
                "operation_code": "ACTUALIZACION_PERFIL_LF",
                "operation_version": "v0.2",
                "authenticated_oidc": True,
                "profile_slug": "quality_pack",
                "source_head_sha": HEAD,
                "selector_version": "1.0.0",
                "method_registry_version": "1.0.0",
            },
            trusted_method_readback=method_readback,
            invoke_governed_method=invoke,
            verify_method_output=verify,
            record_evolution_steps=record,
        )
        self.assertEqual(result["status"], "STEPS_RECORDED", result)
        self.assertEqual(trace, ["readback", "invoke", "verify", "record"])
        self.assertFalse(result["production_activated"])

    def test_unqualified_method_never_becomes_verified(self):
        plan = make_plan(qualified=())
        self.assertEqual(plan["source_readback"]["status"], "UNRESOLVED")
        self.assertNotIn("qualified_method_ids", plan["source_readback"])
        self.assertIn("METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED", plan["blocking_codes"])

    def test_untrusted_status_cannot_supply_qualified_ids(self):
        plan = make_plan(verified=False)
        self.assertEqual(plan["source_readback"]["status"], "UNRESOLVED")
        self.assertNotIn("qualified_method_ids", plan["source_readback"])
        self.assertFalse(plan["candidate_materialization_allowed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
