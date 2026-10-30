"""Synthetic B4 tests. PASS-like input is never provider authenticity."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "b4", Path(__file__).with_name("pg00_c36_b4_postapply_fixture_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def expected():
    return {"proposal_id": "P-1", "catalog_version": "0.8.0",
            "release_catalog_sha256": "a"*64}


class PostapplyTests(unittest.TestCase):
    def check(self, report=None, expectation=None, rows=None):
        if report is None:
            report = {"result": "PASS"}
        if expectation is None:
            expectation = expected()
        if rows is None:
            rows = [expected()]
        out = mod.inspect_postapply(report, expectation, rows)
        self.assertEqual(out["verdict"], "BLOCKED")
        self.assertEqual(out["authority"], "NONE")
        self.assertFalse(out["consumable_by_pg"])
        self.assertIn("AUTHENTICATED_POSTAPPLY_READBACK_REQUIRED",
                      out["reason_codes"])
        return out["reason_codes"]

    def test_matching_fixture_never_authorizes(self):
        self.assertEqual(self.check(), ["AUTHENTICATED_POSTAPPLY_READBACK_REQUIRED"])

    def test_train_blocked(self):
        self.assertIn("TRAIN_RECEIPT_NOT_VERIFIED",
                      self.check(report={"result": "BLOCKED"}))

    def test_train_fail(self):
        self.assertIn("TRAIN_RECEIPT_NOT_VERIFIED",
                      self.check(report={"result": "FAIL"}))

    def test_missing_report(self):
        self.assertIn("TRAIN_RECEIPT_NOT_VERIFIED",
                      self.check(report={}))

    def test_wrong_proposal(self):
        row = expected()
        row["proposal_id"] = "P-OTHER"
        self.assertIn("CATALOG_EXACT_ROW_NOT_UNIQUE", self.check(rows=[row]))

    def test_wrong_version(self):
        row = expected()
        row["catalog_version"] = "0.7.0"
        self.assertIn("CATALOG_EXACT_ROW_NOT_UNIQUE", self.check(rows=[row]))

    def test_wrong_digest(self):
        row = expected()
        row["release_catalog_sha256"] = "b"*64
        self.assertIn("CATALOG_EXACT_ROW_NOT_UNIQUE", self.check(rows=[row]))

    def test_duplicate_rows(self):
        self.assertIn("CATALOG_EXACT_ROW_NOT_UNIQUE",
                      self.check(rows=[expected(), expected()]))

    def test_extra_row(self):
        self.assertIn("UNSCOPED_READBACK_ROWS",
                      self.check(rows=[expected(), dict(expected(), proposal_id="P-OTHER")]))

    def test_malformed_row(self):
        self.assertIn("INVALID_CATALOG_ROW_SHAPE",
                      self.check(rows=[{"proposal_id": "P-1"}]))

    def test_missing_digest(self):
        e = expected()
        e.pop("release_catalog_sha256")
        self.assertIn("EXPECTATION_FIELDS_MISMATCH", self.check(expectation=e))

    def test_fake_approval_fields(self):
        row = expected()
        row["approved_by"] = "FAKE"
        self.assertIn("INVALID_CATALOG_ROW_SHAPE", self.check(rows=[row]))

    def test_no_catalog_rows(self):
        self.assertIn("CATALOG_EXACT_ROW_NOT_UNIQUE", self.check(rows=[]))


if __name__ == "__main__":
    unittest.main()
