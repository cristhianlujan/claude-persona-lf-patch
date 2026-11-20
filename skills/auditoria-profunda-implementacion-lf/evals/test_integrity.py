"""Negative controls for evidence, false closure, authority and package regressions."""
import copy
import json
import sys
import unittest
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
sys.path.insert(0, str(PACK / "validators"))
sys.path.insert(0, str(PACK / "scripts"))
from validate_report import validate
from assess_contracts import assess_authorization, snapshot
from test_acceptance import policy_fixture


class ReportIntegrity(unittest.TestCase):
    def setUp(self):
        self.report = json.loads((PACK / "reports/pilot_report.json").read_text())

    def test_literal_commit_hash_and_consumers_resolve(self):
        self.assertEqual(validate(self.report, ROOT), [])

    def test_changed_literal_is_rejected(self):
        self.report["findings"][0]["found_code"] = "invented code"
        self.assertTrue(any("LITERAL_SOURCE_MISMATCH" in e for e in validate(self.report, ROOT)))

    def test_evidence_hash_drift_is_rejected(self):
        key = next(iter(self.report["evidence_files"]))
        self.report["evidence_files"][key] = "0" * 64
        self.assertTrue(any("EVIDENCE_HASH_MISMATCH" in e for e in validate(self.report, ROOT)))

    def test_unexecuted_confirmation_is_rejected(self):
        self.report["findings"][0]["negative_test"]["executed"] = False
        self.assertTrue(any("CONFIRMATION_EVIDENCE_INSUFFICIENT" in e for e in validate(self.report, ROOT)))

    def test_fix_without_before_after_is_rejected(self):
        self.report["findings"][0]["status"] = "FIX_VERIFIED"
        self.assertTrue(any("FIX_BEFORE_AFTER_REQUIRED" in e for e in validate(self.report, ROOT)))

    def test_missing_ref_and_nonexistent_json_pointer_are_rejected(self):
        self.report["findings"][0]["readback"]["evidence_refs"] = ["unknown.json"]
        self.assertTrue(any("EVIDENCE_UNRESOLVED" in e for e in validate(self.report, ROOT)))
        self.setUp()
        ref = self.report["findings"][0]["positive_test"]["evidence_ref"].split("#")[0]
        self.report["findings"][0]["positive_test"]["evidence_ref"] = ref + "#/missing"
        self.assertTrue(any("EVIDENCE_UNRESOLVED" in e for e in validate(self.report, ROOT)))

    def test_authority_cannot_be_created_by_report_flag(self):
        self.report["promotion_authorized"] = True
        self.assertIn("PROMOTION_AUTHORITY_READBACK_REQUIRED", validate(self.report, ROOT))

    def test_unrelated_bound_evidence_cannot_masquerade_as_authority(self):
        self.report["promotion_authorized"] = True
        self.report["authority_ref"] = self.report["findings"][0]["positive_test"]["evidence_ref"]
        self.assertIn("AUTHORITY_READBACK_CONTRACT_INVALID", validate(self.report, ROOT))

    def test_path_escape_and_duplicate_ids_rejected(self):
        self.report["evidence_files"]["../outside.json"] = "a" * 64
        self.report["findings"][1]["id"] = self.report["findings"][0]["id"]
        errors = validate(self.report, ROOT)
        self.assertTrue(any("EVIDENCE_PATH_OUTSIDE_REPOSITORY" in e for e in errors))
        self.assertTrue(any("DUPLICATE_FINDING_ID" in e for e in errors))

    def test_policy_strict_types_and_nonhex_hash_never_authorize(self):
        for key, value in (("requires_independence", 0), ("allow_contextual", 1),
                           ("verified", "true"), ("current", 1), ("sha256", "z" * 64),
                           ("effect", "DELETE")):
            e, p, evidence = policy_fixture(); p[key] = value
            with self.subTest(key=key): self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])

    def test_snapshot_missing_identity_rejected(self):
        with self.assertRaises(ValueError):
            snapshot({}, run_id="", tenant="t", object_id="o", source_revision="v1", authority_sha256="a" * 64)


if __name__ == "__main__":
    unittest.main()
