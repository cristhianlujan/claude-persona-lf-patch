"""Unit tests for governed step 70 consumer: never execute a real Supabase write."""
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "lf_profile_step70_consume_v3.py"
spec = importlib.util.spec_from_file_location("step70", SCRIPT)
step70 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(step70)


def verdict():
    return {
        "verdict": "PASS_INDEPENDENT_SEMANTIC",
        "decision_checks": {k: {"result": True, "reason": "Verified against source", "source_refs": ["supabase://test"]} for k in step70.CHECKS},
        "producer_independence_proven": True,
        "model_call_count": 1,
        "unsupported_claims": [],
        "blocking_codes": [],
        "source_refs": ["supabase://test"],
        "resolved_context_refs": ["supabase://context"],
        "independent_semantic_receipt_ref": "github://independent-review",
        "router_direct_consistency": "NOT_TESTED",
        "counterfactual_result": "PASS",
    }


class Step70Tests(unittest.TestCase):
    def test_complete_v3_verdict(self):
        step70.check_verdict(verdict())

    def test_missing_one_of_twelve_checks_blocks(self):
        v = verdict()
        del v["decision_checks"]["counterfactual_trajectory"]
        with self.assertRaisesRegex(ValueError, "Exactly 12"):
            step70.check_verdict(v)

    def test_self_judgment_rejected(self):
        v = verdict()
        v["producer_independence_proven"] = False
        with self.assertRaisesRegex(ValueError, "Independence"):
            step70.check_verdict(v)

    def test_missing_model_call_blocks(self):
        v = verdict()
        v["model_call_count"] = 0
        with self.assertRaisesRegex(ValueError, "model call"):
            step70.check_verdict(v)

    def test_unsupported_claim_blocks(self):
        v = verdict()
        v["unsupported_claims"] = ["invented endpoint"]
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            step70.check_verdict(v)

    def test_route_divergence_blocks(self):
        v = verdict()
        v["router_direct_consistency"] = "FAIL"
        with self.assertRaisesRegex(ValueError, "divergence"):
            step70.check_verdict(v)


if __name__ == "__main__":
    unittest.main()
