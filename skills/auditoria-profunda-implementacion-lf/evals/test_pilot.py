"""Regression witnesses for observed LF behavior, not a claim of repair."""
import sys
import unittest
from pathlib import Path
PACK = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACK / "scripts"))
from run_step70_pilot import observe


class Step70Pilot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.actual = observe()

    def test_actual_run_argument_binding_gap_is_reproducible(self):
        r = self.actual["run_binding"]
        self.assertEqual(r["valid_explicit_evaluator_status"], "PASS")
        self.assertEqual(r["wrong_run_evaluator_status"], "PASS")
        self.assertEqual(r["explicit_binding_rejects"], "STEP70_RUN_ID_DRIFT")

    def test_actual_material_failure_masking_is_reproducible(self):
        r = self.actual["eval_masking"]
        self.assertEqual(r["failing_nested_eval_error"], "STEP70_SEPARATE_EVALUATOR_NOT_PASS")
        self.assertEqual(r["normalized_verdict"], "PASS_REVIEWED_CURRENT_CONTEXT")
        self.assertFalse(r["original_receipt_retained"])
        self.assertTrue(r["content_continuation_allowed"])
        self.assertTrue(r["downstream_validator"]["accepted"])

    def test_spec_and_eval_mismatch_is_reproducible(self):
        r = self.actual["schema_eval"]
        self.assertEqual(r["evaluator_status"], "PASS")
        self.assertTrue(r["schema_errors"])
        self.assertEqual(r["valid_schema_errors"], [])
        self.assertEqual(r["valid_evaluator_status"], "PASS")


if __name__ == "__main__":
    unittest.main()
