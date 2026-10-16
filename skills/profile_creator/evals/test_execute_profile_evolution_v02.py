"""Operational v0.2 dispatch integration regressions.
The provider fixtures are labelled NOT real method qualifications.
No production operation status or verified Supabase receipt is asserted.
"""
from __future__ import annotations

import copy
import hashlib
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
from execute_profile_evolution_v02 import execute_profile_evolution_v02 as run

HEAD = "a" * 40
DIGEST = "b" * 64


def plan(mode="ADAPT", method_ids=("CAUSAL_ANALYSIS",)):
    requirements = [
        {"method_id": mid, "eligible_for_composition": True, "within_budget": True}
        for mid in method_ids
    ]
    return {
        "schema": "PROFILE_EVOLUTION_PLAN_V1",
        "profile_slug": "systemic_root_cause_repair_lf",
        "profile_assessment": {"assessment_status": "EVIDENCE_SUFFICIENT"},
        "source_readback": {"status": "VERIFIED_CURRENT",
                            "qualified_method_ids": list(method_ids),
                            "assessment_receipt_ref": "verified-assessment-receipt",
                            "assessment_sha256": DIGEST, "registry_version": "1.0.0"},
        "selection": {"method_requirements": requirements, "fallback_state": "MULTI",
                      "execution_authorized": False},
        "blocking_codes": [],
        "evolution_mode": mode,
        "step_candidates": {
            "method_selection": {"selected_method_ids": list(method_ids),
                                 "method_execution_permitted": False},
            "evolution_decision": {"github_write_permitted": False},
        },
        "profile_source_write_allowed": False,
    }


def binding():
    return {"execution_id": "EXEC-V02-ISOLATED-PROBE",
            "operation_code": "ACTUALIZACION_PERFIL_LF",
            "operation_version": "v0.2",
            "authenticated_oidc": True, "selector_version": "1.0.0",
            "method_registry_version": "1.0.0",
            "profile_slug": "systemic_root_cause_repair_lf",
            "source_head_sha": HEAD}


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.trace = []

    def method_reader(self, method_id, execution, source):
        self.trace.append(("qualification", method_id))
        return {"method_id": method_id, "qualification_state": "QUALIFIED",
                "verification_state": "VERIFIED", "current_source_sha": source,
                "exact_version": "1.0.0",
                "qualification_receipt_id": "test-receipt-not-real",
                "method_subject_sha256": DIGEST}

    def method_executor(self, mid, payload):
        self.trace.append(("invoke", mid))
        material = (mid + payload["execution_id"]).encode()
        return {"method_id": mid, "execution_id": payload["execution_id"],
                "source_head_sha": payload["source_head_sha"],
                "status": "COMPLETED", "receipt_id": "test-provider-output-not-real",
                "output_sha256": hashlib.sha256(material).hexdigest()}

    def verifier(self, result, mid, execution_id, source):
        self.trace.append(("verify", mid))
        expected = hashlib.sha256((mid + execution_id).encode()).hexdigest()
        return (result["source_head_sha"] == source
                and result["output_sha256"] == expected)

    def recorder(self, execution_id, methods, decision):
        self.trace.append(("record", execution_id))
        self.assertEqual(methods["profile_assessment_receipt_id"], "verified-assessment-receipt")
        self.assertEqual(methods["selector_version"], "1.0.0")
        self.assertEqual(methods["source_head_sha"], HEAD)
        self.assertFalse(methods["method_execution_permitted"])
        self.assertFalse(decision["github_write_permitted"])
        for item in methods["selected_methods"]:
            self.assertEqual(item["source_head_sha"], HEAD)
            self.assertEqual(item["subject_sha256"], DIGEST)
        return {"execution_id": execution_id, "method_selection": "STEP_PASS_WITH_EVIDENCE",
                "evolution_decision": "STEP_PASS_WITH_EVIDENCE"}

    def call(self, p, b=None, **overrides):
        deps = dict(trusted_method_readback=self.method_reader,
                    invoke_governed_method=self.method_executor,
                    verify_method_output=self.verifier,
                    record_evolution_steps=self.recorder)
        deps.update(overrides)
        return run(p, operation_binding=b or binding(), **deps)

    def test_one_method_end_to_end(self):
        result = self.call(plan())
        self.assertEqual(result["status"], "STEPS_RECORDED")
        self.assertEqual(result["executed_method_ids"], ["CAUSAL_ANALYSIS"])
        self.assertEqual([t[0] for t in self.trace],
                         ["qualification", "invoke", "verify", "record"])
        self.assertFalse(result["production_activated"])

    def test_two_methods_sequential_verified_receipts(self):
        result = self.call(plan(method_ids=("CAUSAL_ANALYSIS", "SELF_REFINE")))
        self.assertEqual(result["executed_method_ids"], ["CAUSAL_ANALYSIS", "SELF_REFINE"])
        self.assertEqual(self.trace[-1][0], "record")

    def test_no_change_no_methods_no_execution(self):
        result = self.call(plan(mode="NO_CHANGE", method_ids=()))
        self.assertEqual(result["decision"], "NO_CHANGE")
        self.assertEqual(self.trace, [("record", "EXEC-V02-ISOLATED-PROBE")])

    def test_unqualified_catalog_blocks_before_any_execution(self):
        p = plan()
        p["source_readback"]["qualified_method_ids"] = []  # Real Supabase current state.
        result = self.call(p)
        self.assertEqual(result["code"], "SELECTED_METHOD_NOT_QUALIFIED")
        self.assertEqual(self.trace, [])

    def test_fake_qualification_receipt_rejected(self):
        def bad_reader(mid, execution, head):
            return {**self.method_reader(mid, execution, head),
                    "verification_state": "UNVERIFIED"}
        result = self.call(plan(), trusted_method_readback=bad_reader)
        self.assertEqual(result["code"], "METHOD_QUALIFICATION_RECEIPT_INVALID")
        self.assertEqual([x[0] for x in self.trace], ["qualification"])

    def test_provider_claim_unverified_never_records(self):
        result = self.call(plan(), verify_method_output=lambda *_: False)
        self.assertEqual(result["code"], "METHOD_OUTPUT_NOT_PROVIDER_VERIFIED")
        self.assertNotIn("record", [x[0] for x in self.trace])

    def test_missing_authenticated_runtime_blocks(self):
        b = binding()
        b["authenticated_oidc"] = False
        self.assertEqual(self.call(plan(), b=b)["code"], "OPERATION_BINDING_UNVERIFIED")
        self.assertEqual(self.trace, [])

    def test_recorder_rejects_no_success_from_caller(self):
        def not_recorded(*_):
            return {"execution_id": "EXEC-V02-ISOLATED-PROBE",
                    "method_selection": "BLOCKED", "evolution_decision": "BLOCKED"}
        result = self.call(plan(), record_evolution_steps=not_recorded)
        self.assertEqual(result["code"], "CANONICAL_STEP_RECEIPTS_UNVERIFIED")
        self.assertFalse(result["step_recorded"])

    def test_mismatched_selection_rejected(self):
        p = plan()
        p["step_candidates"]["method_selection"]["selected_method_ids"] = ["SELF_REFINE"]
        self.assertEqual(self.call(p)["code"], "METHOD_SELECTION_CANDIDATE_MISMATCH")
        self.assertEqual(self.trace, [])

    def test_tampered_qualification_source_rejected(self):
        def bad_reader(mid, execution, source):
            return {**self.method_reader(mid, execution, source),
                    "current_source_sha": "0" * 40}
        self.assertEqual(self.call(plan(), trusted_method_readback=bad_reader)["code"],
                         "METHOD_QUALIFICATION_RECEIPT_INVALID")
        self.assertNotIn("invoke", [x[0] for x in self.trace])


if __name__ == "__main__":
    unittest.main()
