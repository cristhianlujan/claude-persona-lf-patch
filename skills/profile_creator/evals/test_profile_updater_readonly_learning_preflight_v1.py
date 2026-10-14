"""Read-only evidence assessment must precede (never replace) strict pre-write."""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
sys.path.insert(0,str(HERE.parent / "validators"))
from s26_learning_preflight_matrix import mod, payload, HEAD


class ReadOnlyLearningPreflight(unittest.TestCase):
    def test_assessment_without_write_binding(self):
        p=payload()
        p.pop("execution_binding")
        p.pop("authorized_scope")
        out=mod.evaluate_learning_preflight(p,"demo",current_revision=HEAD,assessment_only=True)
        self.assertEqual(out["status"],"PASS")
        self.assertEqual(out["preflight_phase"],"READ_ONLY_ASSESSMENT")
        self.assertFalse(out["write_preflight_authorized"])

    def test_write_without_binding_still_blocked(self):
        p=payload()
        p.pop("execution_binding")
        p.pop("authorized_scope")
        out=mod.evaluate_learning_preflight(p,"demo",current_revision=HEAD)
        self.assertEqual(out["status"],"BLOCKED")
        self.assertIn("EXECUTION_BINDING_MISSING",out["blocking_codes"])
        self.assertFalse(out["write_preflight_authorized"])

    def test_readonly_stale_revision_blocks(self):
        p=payload()
        p.pop("execution_binding")
        out=mod.evaluate_learning_preflight(p,"demo",current_revision="c"*40,assessment_only=True)
        self.assertEqual(out["status"],"BLOCKED")
        self.assertIn("STALE_MAIN_REVISION",out["blocking_codes"])

    def test_readonly_false_ekb_execution_blocks(self):
        p=payload()
        p["ekb_preflight"]["prevention_checks"][0]["executed"]=False
        out=mod.evaluate_learning_preflight(p,"demo",current_revision=HEAD,assessment_only=True)
        self.assertEqual(out["status"],"BLOCKED")
        self.assertTrue(any("EKB_PREVENTION_EXECUTION_RECEIPT_INVALID" in x for x in out["blocking_codes"]))

    def test_write_strict_original_positive(self):
        out=mod.evaluate_learning_preflight(payload(),"demo",current_revision=HEAD)
        self.assertEqual(out["status"],"PASS")
        self.assertEqual(out["preflight_phase"],"PRE_WRITE")
        self.assertTrue(out["write_preflight_authorized"])

    def test_readonly_cross_profile_replay_blocks(self):
        p=payload()
        p["profile_slug"]="other"
        out=mod.evaluate_learning_preflight(p,"demo",current_revision=HEAD,assessment_only=True)
        self.assertEqual(out["status"],"BLOCKED")
        self.assertIn("LEARNING_PREFLIGHT_PROFILE_MISMATCH",out["blocking_codes"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
