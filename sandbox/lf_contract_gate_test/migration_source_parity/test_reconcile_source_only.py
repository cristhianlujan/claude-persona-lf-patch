import importlib.util
import pathlib
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = pathlib.Path(__file__).with_name("reconcile_source_only.py")
spec = importlib.util.spec_from_file_location("reconcile_source_only", TARGET)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
import sys
sys.path.insert(0, str(ROOT))
import migration_transport_normalization as transport


def item(v):
    return f"supabase/migrations/{v}_demo.sql"


class ReconcileTests(unittest.TestCase):
    def setUp(self):
        self.versions = [f"20261009{i:06d}" for i in range(69)]
        self.new = {item(v): "select 1;\n" for v in self.versions}
        self.old = {item(v): "select 1;\n" for v in self.versions}
        self.ledger = {v: {"name": "demo",
                           "sha256": transport.sha256(transport.canonical("select 1;\n")),
                           "statement_count": 1} for v in self.versions}

    def run_rows(self, rows):
        return m.verify_rows(rows,
            lambda path, old=False: (self.old if old else self.new)[path],
            lambda version: self.ledger.get(version))

    def test_69_renames_fixture_matching_pr_2154_count(self):
        rows = [{"filename": item(v), "status": "renamed", "previous_filename": item(v.replace("20261009","20261008",1))} for v in self.versions]
        self.assertEqual(len(self.run_rows(rows)["migrations"]), 69)

    def test_69_added_from_ledger(self):
        rows = [{"filename": item(v), "status": "added"} for v in self.versions]
        self.assertEqual(len(self.run_rows(rows)["migrations"]), 69)

    def test_removed_added_pair(self):
        v=self.versions[0]
        self.assertEqual(self.run_rows([{"filename":item(v),"status":"removed"},
                        {"filename":item(v),"status":"added"}])["status"],"PASS")

    def test_content_diff_block(self):
        v=self.versions[0]
        self.new[item(v)]="select 2;"
        with self.assertRaisesRegex(Exception,"CONTENT_MISMATCH"):
            self.run_rows([{"filename":item(v),"status":"added"}])

    def test_missing_ledger_block(self):
        v=self.versions[0]
        self.ledger.clear()
        with self.assertRaisesRegex(ValueError,"VERSION_NOT_IN_LEDGER"):
            self.run_rows([{"filename":item(v),"status":"added"}])

    def test_unpaired_removed_block(self):
        v=self.versions[0]
        with self.assertRaisesRegex(ValueError,"NO_RECONCILIATION_TARGETS"):
            self.run_rows([{"filename":item(v),"status":"removed"}])

    def test_non_migration_file_block(self):
        v=self.versions[0]
        with self.assertRaisesRegex(ValueError,"NON_MIGRATION"):
            self.run_rows([{"filename":"README.md","status":"modified"},
                          {"filename":item(v),"status":"added"}])

    def test_modified_block(self):
        v=self.versions[0]
        with self.assertRaisesRegex(ValueError,"CHANGE_STATUS_INVALID"):
            self.run_rows([{"filename":item(v),"status":"modified"}])

    def test_duplicate_version_block(self):
        v=self.versions[0]
        with self.assertRaisesRegex(ValueError,"DUPLICATE_TARGET_VERSION"):
            self.run_rows([{"filename":item(v),"status":"added"},
                           {"filename":item(v),"status":"added"}])


if __name__ == "__main__":
    unittest.main()
