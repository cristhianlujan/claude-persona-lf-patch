"""Regression: check11 cannot block Router-only, cannot fabricate direct PASS.

All inputs are synthetic and no production RPCs are performed.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


bridge = load("scripts/lf_profile_native_resume.py", "lf_native_resume_for_check11")
feedback = load("scripts/lf_semantic_fail_feedback.py", "lf_feedback_for_check11")


def review():
    checks = {name: {
        "result": True, "reason": "A source-bound positive check with evidence.",
        "source_refs": ["supabase://source"],
    } for name in bridge.SEMANTIC_CHECKS}
    checks["router_direct_consistency"] = {
        "result": "not_applicable", "applicability": "ROUTER_ONLY",
        "reason": "ACT-0001 is the only authorized operational route; no direct pair exists.",
        "source_refs": ["supabase://router/authorized"],
    }
    return {
        "execution_id": "EXEC-CHECK11-SYNTHETIC",
        "verdict": "PASS_INDEPENDENT_SEMANTIC",
        "decision_checks": checks,
        "producer_independence_proven": True,
        "model_call_count": 1,
        "unsupported_claims": [],
        "blocking_codes": [],
        "source_refs": ["supabase://source"],
        "resolved_context_refs": ["supabase://context"],
        "router_direct_consistency": "NOT_TESTED",
        "counterfactual_result": "PASS",
        "candidate_sha256": "a" * 64,
        "scope_packet_sha256": "b" * 64,
    }


class RouterOnlyCheck11Tests(unittest.TestCase):
    def test_router_only_na_allowed_with_all_other_checks_pass(self):
        bridge.validate_independent_semantic_review(review())

    def test_absent_direct_pair_is_not_auto_pass(self):
        r = review()
        r["decision_checks"]["router_direct_consistency"]["result"] = True
        with self.assertRaisesRegex(ValueError, "APPLICABILITY_INVALID"):
            bridge.validate_independent_semantic_review(r)

    def test_na_cannot_hide_a_different_failed_check(self):
        r = review()
        r["decision_checks"]["acceptance_detects_wrong_implementation"]["result"] = False
        with self.assertRaisesRegex(ValueError, "CHECK_FAILED"):
            bridge.validate_independent_semantic_review(r)

    def test_fake_direct_pair_rejected(self):
        r = review()
        r["router_direct_consistency"] = "PASS"
        r["decision_checks"]["router_direct_consistency"].update({
            "result": True, "applicability": "AUTHORIZED_COMPARISON",
        })
        with self.assertRaisesRegex(ValueError, "COMPARISON_UNPROVEN"):
            bridge.validate_independent_semantic_review(r)

    def test_direct_pair_only_with_two_distinct_cited_execution_refs(self):
        r = review()
        r["router_direct_consistency"] = "PASS"
        r["decision_checks"]["router_direct_consistency"].update({
            "result": True, "applicability": "AUTHORIZED_COMPARISON",
            "router_execution_ref": "actions://router/1",
            "direct_execution_ref": "actions://direct/2",
            "source_refs": ["actions://router/1", "actions://direct/2"],
        })
        bridge.validate_independent_semantic_review(r)
        r["decision_checks"]["router_direct_consistency"]["direct_execution_ref"] = "actions://router/1"
        with self.assertRaisesRegex(ValueError, "COMPARISON_UNPROVEN"):
            bridge.validate_independent_semantic_review(r)

    def test_unproven_independence_still_blocks(self):
        r = review()
        r["producer_independence_proven"] = False
        with self.assertRaisesRegex(ValueError, "INDEPENDENCE"):
            bridge.validate_independent_semantic_review(r)

    def test_failure_feedback_does_not_send_na_to_producer(self):
        r = review()
        r["verdict"] = "FAIL_ACCEPTANCE_WEAK"
        r["decision_checks"]["acceptance_detects_wrong_implementation"]["result"] = False
        r["decision_checks"]["acceptance_detects_wrong_implementation"]["reason"] = "Falsifier passed"
        out = feedback.classify_failure(r, r["execution_id"], "PERFIL-PRODUCT-DIRECTOR-LF")
        self.assertEqual(out["outcome"], "RETURN_TO_WORKER")
        self.assertEqual([c["check"] for c in out["failed_checks"]],
                         ["acceptance_detects_wrong_implementation"])

    def test_na_cannot_be_used_for_another_check(self):
        r = review()
        r["verdict"] = "FAIL_ACCEPTANCE_WEAK"
        r["decision_checks"]["evidence_supported"].update({
            "result": "not_applicable", "applicability": "ROUTER_ONLY",
        })
        with self.assertRaisesRegex(ValueError, "UNAUTHORIZED_NOT_APPLICABLE"):
            feedback.classify_failure(r, r["execution_id"], "PERFIL-PRODUCT-DIRECTOR-LF")


if __name__ == "__main__":
    unittest.main()
