"""Regression for the Product Director RAW-origin qualifier-loss incident.

Exercises the canonical Product Director validator and the existing bridge hook;
no live Router/Edge/Supabase writes or simulated model claim.
"""
import ast
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
VALIDATORS = ROOT / "profiles/product_director_lf/validators"
sys.path.insert(0, str(VALIDATORS))
from prepare_output_for_submission import prepare
from validate_product_director_output import validate


def valid_fixture():
    """Reuse existing Product Director fixture without unrelated jsonschema dependency."""
    source = ROOT / "profiles/product_director_lf/evals/remediation_20260827/run_cases.py"
    tree = ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
    definition = next(node for node in tree.body
                      if isinstance(node, ast.FunctionDef) and node.name == "good_output")
    scope = {}
    exec(compile(ast.Module(body=[definition], type_ignores=[]), str(source), "exec"), scope)
    return scope["good_output"]()


def broken_fixture():
    raw = valid_fixture()
    raw["deliverable_created"]["handoff_to_next"]["qualifiers_to_preserve"] = ["referencial"]
    return raw


class ProductDirectorOriginPreflightTest(unittest.TestCase):
    def test_canonical_validator_still_rejects_original(self):
        receipt = validate(broken_fixture())
        self.assertFalse(receipt["valid"])
        self.assertEqual(receipt["blocking_codes"], ["HANDOFF_QUALIFIER_LOSS"])

    def test_exact_lossless_one_attempt_repairs(self):
        original = broken_fixture()
        before = copy.deepcopy(original)
        repaired = prepare(original)
        self.assertEqual(repaired["status"], "SELF_REPAIRED_HANDOFF_QUALIFIERS")
        self.assertEqual(repaired["added_qualifiers"], ["sujeta a validación"])
        self.assertTrue(validate(repaired["profile_output"])["valid"])
        self.assertEqual(original, before)
        self.assertEqual(
            repaired["profile_output"]["deliverable_created"]["product_decision"],
            original["deliverable_created"]["product_decision"])
        self.assertEqual(
            repaired["profile_output"]["deliverable_created"]["decision_lineage"],
            original["deliverable_created"]["decision_lineage"])

    def test_clean_output_passes_without_rewriting(self):
        original = valid_fixture()
        prepared = prepare(original)
        self.assertEqual(prepared["status"], "UNCHANGED_VALID")
        self.assertEqual(prepared["profile_output"], original)
        self.assertEqual(prepared["added_qualifiers"], [])

    def test_material_claim_error_cannot_be_hidden_by_qualifier_repair(self):
        broken = broken_fixture()
        broken["deliverable_created"]["material_claims"][0]["authority_ref"] = "missing://authority"
        got = prepare(broken)
        self.assertEqual(got["status"], "BLOCKED")
        self.assertIsNone(got["profile_output"])
        self.assertIn("CLAIM_AUTHORITY_MISSING", got["original_blocking_codes"])

    def test_bad_input_fails_closed(self):
        self.assertEqual(prepare(None)["status"], "BLOCKED")

    def test_bridge_creates_original_and_repair_receipt_but_does_not_touch_other_profiles(self):
        original = broken_fixture()
        originals = (ROOT / "profile-native-output-original.json", ROOT / "profile-native-origin-repair.json")
        for p in originals:
            self.assertFalse(p.exists(), "test must not overwrite preexisting audit artifacts")
        try:
            with patch.dict(os.environ, {"LF_PROFILE_EDGE_URL": "https://unit.example/functions/v1/bridge"}):
                mod = runpy.run_path(str(ROOT / "scripts/lf_profile_native_resume.py"), run_name="origin_preflight_test")
            hook = mod["prepare_product_director_raw"]
            corrected = hook("profiles/product_director_lf/SKILL.md", original)
            self.assertTrue(validate(corrected)["valid"])
            receipt = json.loads(originals[1].read_text(encoding="utf-8"))
            stored_original = originals[0].read_bytes()
            self.assertEqual(json.loads(stored_original), original)
            self.assertEqual(receipt["original_output_sha256"], hashlib.sha256(stored_original).hexdigest())
            self.assertFalse(receipt["model_invoked_by_repair"])
            self.assertFalse(receipt["semantic_claims_rewritten"])
            self.assertEqual(receipt["added_qualifiers"], ["sujeta a validación"])
            other = {"worker": "other_profile"}
            self.assertIs(hook("profiles/ui_architect/SKILL.md", other), other)
        finally:
            for p in originals:
                p.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
