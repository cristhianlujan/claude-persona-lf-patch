from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lf_migration_reconcile_lane as lane
from lf_migration_source_parity_ci_context import classified


class ReconcileLaneTests(unittest.TestCase):
    sql = "create function public.probe() returns int language sql as $$ select 1 $$;\n"
    base_version = "20261014110000"
    dest_name = "ig_m8_2_per_family_resolver_hook_v1"
    dest_path = f"supabase/migrations/{base_version}_{dest_name}.sql"
    old_path = "supabase/migrations/20261014105900_legacy_filename.sql"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self.tmp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        self.base = self.commit({self.old_path: self.sql})
        self.ledger = [lane.LedgerEntry(self.base_version, self.dest_name, (self.sql,), 1)]

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()

    def commit(self, files):
        for old in self.repo.glob("supabase/migrations/*.sql"):
            old.unlink()
        (self.repo / "supabase/migrations").mkdir(parents=True, exist_ok=True)
        for path, content in files.items():
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def verify(self, files, ledger=None, *, base=None, changes=None):
        head = self.commit(files)
        if changes is None:
            return lane.verify(repo=self.repo, repo_label="owner/repo", pr=7,
                               base_sha=base or self.base, head_sha=head,
                               ledger_entries=ledger or self.ledger)
        rows = lane._verify_changes(repo=self.repo, base_sha=base or self.base,
                                    head_sha=head, changes=changes,
                                    ledger_entries=ledger or self.ledger)
        return lane.PASS, {"files": rows}

    def test_positive_rename_with_same_content(self):
        code, receipt = self.verify({self.dest_path: self.sql})
        self.assertEqual(code, 0)
        self.assertEqual(receipt["verdict"], "PASS")
        self.assertEqual(sum(x["verdict"] == "PASS_LEDGER_EXACT" for x in receipt["files"]), 1)

    def test_merged_lote3_classifier_exact_name_and_negative_versioned_variant(self):
        self.assertTrue(classified("ig_m8_2_per_family_resolver_hook_v1"))
        self.assertFalse(classified("20261008195346_ig_m8_2_per_family_resolver_hook_v1"))

    def test_g12_cross_baseline_name_waits_for_owner_decision(self):
        name = "lf_pilot_srcr_g12"
        path = f"supabase/migrations/{self.base_version}_{name}.sql"
        self.assertTrue(classified(name))
        ledger = [lane.LedgerEntry(self.base_version, name, (self.sql,), 1)]
        code, receipt = self.verify({path: self.sql}, ledger=ledger)
        self.assertEqual(code, 1)
        self.assertIn("OWNER_NAME_DECISION_PENDING", receipt["reason"])

    def test_positive_restore_from_ledger(self):
        self.commit({})
        code, receipt = self.verify({self.dest_path: self.sql})
        self.assertEqual((code, receipt["verdict"]), (0, "PASS"))

    def test_positive_content_correction_to_ledger(self):
        exact_path = f"supabase/migrations/{self.base_version}_{self.dest_name}.sql"
        wrong = self.sql + "select 2;\n"
        base = self.commit({exact_path: wrong})
        code, receipt = self.verify({exact_path: self.sql}, base=base)
        self.assertEqual((code, receipt["verdict"]), (0, "PASS"))

    def test_positive_git_delete_add_pair(self):
        changes = [lane.Change("D", self.old_path), lane.Change("A", self.dest_path)]
        code, result = self.verify({self.dest_path: self.sql}, changes=changes)
        self.assertEqual(code, 0)
        self.assertEqual(sum(x["verdict"] == "PASS_PAIRED_SOURCE_NOT_LEDGER" for x in result["files"]), 1)
        self.assertEqual(sum(x["verdict"] == "PASS_LEDGER_EXACT" for x in result["files"]), 1)

    def test_negative_content_differs_from_ledger(self):
        code, receipt = self.verify({self.dest_path: self.sql + "-- changed\n" + "select 2;\n"})
        self.assertEqual((code, receipt["verdict"]), (1, "FAIL"))
        self.assertIn("LEDGER_CONTENT_MISMATCH", receipt["reason"])

    def test_negative_version_outside_ledger(self):
        path = f"supabase/migrations/20261014110001_{self.dest_name}.sql"
        code, receipt = self.verify({path: self.sql})
        self.assertEqual(code, 1)
        self.assertIn("VERSION_OUTSIDE_LEDGER", receipt["reason"])

    def test_negative_name_mismatch(self):
        path = f"supabase/migrations/{self.base_version}_wrong_name.sql"
        code, receipt = self.verify({path: self.sql})
        self.assertEqual(code, 1)
        self.assertIn("LEDGER_NAME_MISMATCH", receipt["reason"])

    def test_negative_deletion_without_pair(self):
        code, receipt = self.verify({})
        self.assertEqual(code, 1)
        self.assertIn("DELETE_WITHOUT_UNIQUE_IDENTICAL_DESTINATION", receipt["reason"])

    def test_negative_path_outside_migrations(self):
        code, receipt = self.verify({self.old_path: self.sql, "docs/note.txt": "changed"})
        self.assertEqual(code, 1)
        self.assertIn("PATH_OUTSIDE_MIGRATIONS", receipt["reason"])

    def test_negative_duplicate_versions_in_result_tree(self):
        other = f"supabase/migrations/{self.base_version}_second.sql"
        code, receipt = self.verify({self.dest_path: self.sql, other: self.sql})
        self.assertEqual(code, 1)
        self.assertIn("HEAD_DUPLICATE_VERSION", receipt["reason"])

    def test_negative_batch_over_limit(self):
        files = {f"supabase/migrations/2026101412{i:04d}_probe_{i}.sql": self.sql for i in range(101)}
        code, receipt = self.verify(files)
        self.assertEqual(code, 1)
        self.assertIn("BATCH_EXCEEDS_MAX", receipt["reason"])

    def test_negative_head_does_not_contain_main(self):
        self.git("checkout", "--orphan", "independent")
        head = self.commit({self.dest_path: self.sql})
        code, receipt = lane.verify(repo=self.repo, repo_label="owner/repo", pr=7,
                                    base_sha=self.base, head_sha=head,
                                    ledger_entries=self.ledger)
        self.assertEqual((code, receipt["verdict"]), (1, "FAIL"))
        self.assertEqual(receipt["reason"], "HEAD_DOES_NOT_CONTAIN_MAIN")

    def test_negative_deleting_exact_ledger_entry(self):
        exact_file = f"supabase/migrations/{self.base_version}_{self.dest_name}.sql"
        self.commit({exact_file: self.sql})
        exact_base = self.git("rev-parse", "HEAD")
        self.ledger = [lane.LedgerEntry(self.base_version, self.dest_name, (self.sql,), 1)]
        code, receipt = self.verify({}, base=exact_base)
        self.assertEqual(code, 1)
        self.assertIn("DELETE_EXACT_LEDGER_ENTRY", receipt["reason"])

    def test_blocked_ledger_unreadable(self):
        with self.assertRaises(lane.LaneBlocked):
            lane._load_ledger_json(self.repo / "missing.json")

    def test_offline_ledger_json_cli_writes_versioned_receipt(self):
        head = self.commit({self.dest_path: self.sql})
        snapshot = self.repo / "ledger.json"
        snapshot.write_text(json.dumps({
            "schema_version": lane.LEDGER_SCHEMA,
            "rows": [{"version": self.base_version, "name": self.dest_name,
                      "statements": [self.sql]}],
        }), encoding="utf-8")
        out = self.repo / "receipt.json"
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            code = lane.main([
                "--repo", str(self.repo), "--repo-label", "owner/repo", "--pr-number", "7",
                "--base-sha", self.base, "--head-sha", head,
                "--ledger-json", str(snapshot), "--out", str(out),
            ])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out.read_text())["pr"], 7)
        self.assertEqual(json.loads(out.read_text())["verdict"], "PASS")
        self.assertEqual(json.loads(stream.getvalue())["schema_version"], lane.RECEIPT_SCHEMA)

    def test_blocked_ledger_json_schema(self):
        path = self.repo / "bad-ledger.json"
        path.write_text('{"rows": []}', encoding="utf-8")
        with self.assertRaisesRegex(lane.LaneBlocked, "LEDGER_JSON_SCHEMA_INVALID"):
            lane._load_ledger_json(path)

    def test_read_only_database_source_uses_only_select_and_readonly_session(self):
        statements = "select 1;\n"
        encoded = statements.encode("utf-8").hex()
        psql_result = SimpleNamespace(returncode=0, stdout=f"{self.base_version}\t{self.dest_name}\t1\t{encoded}\n".encode())
        with patch.dict("os.environ", {"TEST_LF_RO_URL": "postgresql://ro@example.invalid/db"}), \
             patch.object(lane.subprocess, "run", return_value=psql_result) as run:
            entries = lane._load_ledger_database("TEST_LF_RO_URL")
        argv = run.call_args.args[0]
        self.assertEqual(argv[0], "psql")
        self.assertIn("select version", argv[-1])
        self.assertNotIn("insert ", argv[-1].lower())
        self.assertEqual(run.call_args.kwargs["env"]["PGOPTIONS"], "-c default_transaction_read_only=on")
        self.assertEqual(entries[0].statement_count, 1)

    def test_blocked_invalid_sha(self):
        head = self.commit({self.dest_path: self.sql})
        code, receipt = lane.verify(repo=self.repo, repo_label="owner/repo", pr=7,
                                    base_sha="bad", head_sha=head,
                                    ledger_entries=self.ledger)
        self.assertEqual((code, receipt["verdict"]), (2, "BLOCKED"))
        self.assertEqual(receipt["reason"], "SHA_INVALID:base")

    def test_receipt_is_deterministic_byte_for_byte(self):
        head = self.commit({self.dest_path: self.sql})
        rendered = []
        for _ in range(2):
            code, receipt = lane.verify(repo=self.repo, repo_label="owner/repo", pr=7,
                                        base_sha=self.base, head_sha=head,
                                        ledger_entries=self.ledger)
            self.assertEqual(code, 0)
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                lane._write_receipt(None, receipt)
            rendered.append(stream.getvalue().encode("utf-8"))
        self.assertEqual(rendered[0], rendered[1])
        parsed = json.loads(rendered[0])
        self.assertEqual(len(parsed["receipt_sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
