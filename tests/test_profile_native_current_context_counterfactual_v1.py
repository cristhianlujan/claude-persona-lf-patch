"""Regression: current-context V3 evidence stays truthful and the canonical bridge can retry step 70."""
import importlib.util
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("LF_PROFILE_EDGE_URL", "https://example.invalid")
spec = importlib.util.spec_from_file_location("lf_profile_resume_counterfactual", ROOT / "scripts/lf_profile_native_resume.py")
resume = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resume)
MIGRATION = ROOT / "supabase/migrations/20261109043500_lf_profile_step70_counterfactual_retry_v1.sql"


class CurrentContextCounterfactualTests(unittest.TestCase):
    def review(self, result, mode="CURRENT_CONTEXT_REVIEW"):
        return {
            "review_mode": mode,
            "counterfactual_result": result,
            "candidate_sha256": "a" * 64,
            "scope_packet_sha256": "b" * 64,
        }

    def test_structured_pass_keeps_three_original_counterexamples(self):
        evidence = {"status": "PASS", "counterfactuals": [
            {"deviation": "MFA promoted without proof", "verdict": "FAIL_IMPLEMENTATION"},
            {"deviation": "Rate requests confused with bad passwords", "verdict": "FAIL_THRESHOLD"},
            {"deviation": "Implementation despite no-write", "verdict": "FAIL_UNAUTHORIZED"},
        ]}
        original = self.review(evidence)
        normalized = resume.normalize_current_context_counterfactual(original)
        self.assertEqual(normalized["counterfactual_result"], "PASS")
        self.assertEqual(normalized["counterfactual_details"], evidence)
        self.assertIs(normalized["counterfactual_details"]["counterfactuals"], evidence["counterfactuals"])
        self.assertIs(original["counterfactual_result"], evidence)  # RAW input unchanged
        receipt = resume.build_semantic_receipt(original)
        self.assertEqual(receipt["judge_v3_evidence"]["counterfactual_result"], "PASS")
        self.assertEqual(receipt["judge_v3_evidence"]["counterfactual_details"], evidence)
        self.assertEqual(receipt["review_mode"], "CURRENT_CONTEXT_REVIEW")
        self.assertFalse(receipt["producer_independence_proven"])
        self.assertEqual(receipt["model_call_count"], 0)

    def test_legacy_scalar_pass_is_preserved(self):
        original = self.review("PASS")
        self.assertIs(resume.normalize_current_context_counterfactual(original), original)
        self.assertEqual(resume.build_semantic_receipt(original)["judge_v3_evidence"]["counterfactual_result"], "PASS")

    def test_independent_mode_not_reinterpreted(self):
        evidence = {"status": "PASS", "counterfactuals": [{"verdict": "FAIL"}]}
        original = self.review(evidence, mode="INDEPENDENT_SEMANTIC")
        self.assertIs(resume.normalize_current_context_counterfactual(original), original)
        self.assertEqual(resume.build_semantic_receipt(original)["judge_v3_evidence"]["counterfactual_result"], evidence)

    def test_fail_and_empty_counterfactuals_do_not_become_pass(self):
        for invalid in (
            {"status": "FAIL", "counterfactuals": [{"verdict": "FAIL"}]},
            {"status": "PASS", "counterfactuals": []},
            {"status": "PASS"},
            {"status": "PASS", "counterfactuals": "fake"},
            "FAIL",
            True,
        ):
            with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, "PROFILE_CURRENT_CONTEXT_COUNTERFACTUAL_NOT_PASS"):
                resume.normalize_current_context_counterfactual(self.review(invalid))

    def test_retry_bridge_only_enables_canonical_blocked_states(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN", sql)
        self.assertIn("public.lf_record_profile_execution_step_v1(", sql)
        self.assertIn("IF v_clean<>10 THEN", sql)
        self.assertIn("ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN", sql)
        self.assertIn("LF_PROFILE_STEP70_BRIDGE_SOURCE_DRIFT", sql)
        self.assertIn("SECURITY DEFINER", sql)
        self.assertNotIn("GRANT EXECUTE", sql)
        self.assertNotIn("UPDATE public.lf_operation_execution_steps", sql)
        self.assertTrue(sql.endswith("\n"))


if __name__ == "__main__":
    unittest.main()
