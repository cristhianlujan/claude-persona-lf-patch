"""PASE-ATOM-F07-X01: Train receipt provenance, owner rule D1 and receipt emission."""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))

import lf_train_execution_recorder as recorder  # noqa: E402

MIGRATION = ROOT / "supabase/migrations/20261013210000_lf_migration_train_receipt_v1.sql"
OLD = "supabase/migrations/20261013100000_lf_x_v1.sql"
NEW = "supabase/migrations/20261013110000_lf_x_v1.sql"


def sh(repo: str, *args: str, env: dict | None = None) -> str:
    full = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t", **(env or {})}
    out = subprocess.run(["git", *args], cwd=repo, text=True, capture_output=True, check=True, env=full)
    return out.stdout.strip()


def write(repo: str, path: str, text: str) -> None:
    p = pathlib.Path(repo, path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


class TrainHistory:
    """Reproduces the Train: authorized head, main advance, merge-tree sync, retimestamp."""

    def __init__(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        r = self.repo = self.tmp.name
        sh(r, "init", "-q", "-b", "main")
        write(r, "a.txt", "a\n")
        sh(r, "add", "-A"); sh(r, "commit", "-qm", "base")
        sh(r, "checkout", "-qb", "pr")
        write(r, OLD, "select 1;\n")
        sh(r, "add", "-A"); sh(r, "commit", "-qm", "migration")
        self.authorized = sh(r, "rev-parse", "HEAD")
        self.blob = sh(r, "rev-parse", f"HEAD:{OLD}")
        sh(r, "checkout", "-q", "main")
        write(r, "b.txt", "b\n")
        sh(r, "add", "-A"); sh(r, "commit", "-qm", "main advances")
        self.main = sh(r, "rev-parse", "HEAD")
        tree = sh(r, "merge-tree", "--write-tree", self.authorized, self.main).splitlines()[0]
        self.synced = sh(r, "commit-tree", tree, "-p", self.authorized, "-p", self.main, "-m", "sync")

    def commit_on(self, parent: str, changes: dict[str, str | None], msg: str = "c") -> str:
        r = self.repo
        sh(r, "checkout", "-q", "--detach", parent)
        for path, text in changes.items():
            if text is None:
                sh(r, "rm", "-q", path)
            else:
                write(r, path, text)
        sh(r, "add", "-A"); sh(r, "commit", "-qm", msg)
        return sh(r, "rev-parse", "HEAD")

    def retimestamp(self, parent: str, new_path: str = NEW, text: str = "select 1;\n") -> str:
        return self.commit_on(parent, {OLD: None, new_path: text}, "assign version")


class RuleD1Test(unittest.TestCase):
    def setUp(self) -> None:
        self.h = TrainHistory()
        self.addCleanup(self.h.tmp.cleanup)

    def classify(self, final: str, target: str = NEW) -> dict:
        h = self.h
        return recorder.classify_head_diff(h.authorized, h.main, final, target, h.blob, cwd=h.repo)

    def test_no_change(self) -> None:
        self.assertEqual(self.classify(self.h.authorized, OLD)["class"], recorder.DIFF_NO_CHANGE)

    def test_sync_only(self) -> None:
        self.assertEqual(self.classify(self.h.synced, OLD)["class"], recorder.DIFF_SYNC_ONLY)

    def test_sync_and_retimestamp(self) -> None:
        final = self.h.retimestamp(self.h.synced)
        self.assertEqual(self.classify(final)["class"], recorder.DIFF_SYNC_ONLY)

    def test_retimestamp_without_sync_needed(self) -> None:
        h = self.h
        final = h.retimestamp(h.authorized)
        res = recorder.classify_head_diff(h.authorized, sh(h.repo, "rev-parse", "main~1"), final, NEW, h.blob, cwd=h.repo)
        self.assertEqual(res["class"], recorder.DIFF_SYNC_ONLY)

    def test_extra_file_is_unexpected(self) -> None:
        final = self.h.commit_on(self.h.retimestamp(self.h.synced), {"c.txt": "c\n"})
        res = self.classify(final)
        self.assertEqual(res["class"], recorder.DIFF_UNEXPECTED)
        self.assertIn("c.txt", res["unexpected_paths"])

    def test_migration_content_change_is_unexpected(self) -> None:
        final = self.h.retimestamp(self.h.synced, text="select 2;\n")
        self.assertEqual(self.classify(final)["class"], recorder.DIFF_UNEXPECTED)

    def test_migration_name_change_is_unexpected(self) -> None:
        other = "supabase/migrations/20261013110000_lf_other_v1.sql"
        final = self.h.retimestamp(self.h.synced, new_path=other)
        self.assertEqual(self.classify(final, other)["class"], recorder.DIFF_UNEXPECTED)

    def test_main_file_reverted_is_unexpected(self) -> None:
        final = self.h.commit_on(self.h.synced, {"b.txt": None})
        self.assertEqual(self.classify(final, OLD)["class"], recorder.DIFF_UNEXPECTED)

    def test_missing_commit_is_not_evaluated(self) -> None:
        self.assertEqual(self.classify("f" * 40)["class"], recorder.DIFF_NOT_EVALUATED)


CTX = {"pr": "2500", "version": "20261013110000", "name": "lf_x_v1", "path": NEW,
       "source_blob": "a" * 40, "source_sha256": "b" * 64, "repo": "o/r",
       "head_sha": "c" * 40, "persisted_head_sha": "d" * 40, "run_id": "777"}


class ProvenanceAndReceiptTest(unittest.TestCase):
    def test_authorization_from_event(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"label": {"name": "ready-to-merge"}, "sender": {"login": "paulozterra"},
                       "pull_request": {"head": {"sha": "1" * 40}}}, f)
        self.addCleanup(os.unlink, f.name)
        env = {"GITHUB_EVENT_PATH": f.name, "GITHUB_ACTOR": "paulozterra",
               "GITHUB_TRIGGERING_ACTOR": "paulozterra", "GITHUB_RUN_ATTEMPT": "1"}
        with patch.dict(os.environ, env):
            auth = recorder.authorization_from_env()
        self.assertEqual(auth["label"], "ready-to-merge")
        self.assertEqual(auth["authorized_by"], "paulozterra")
        self.assertEqual(auth["authorized_head"], "1" * 40)

    def test_begin_stops_on_unexpected_changes_before_any_database_call(self) -> None:
        prov = {"label": "ready-to-merge", "diff_class": recorder.DIFF_UNEXPECTED, "diff_unexpected_paths": ["x.py"]}
        def no_db(sql, **params):
            raise AssertionError("database touched before D1")
        with patch.object(recorder, "capture_provenance", return_value=prov), \
             patch.object(recorder, "call", side_effect=no_db):
            with self.assertRaisesRegex(RuntimeError, "TRAIN_EXEC_D1_UNEXPECTED_CHANGES:x.py"):
                recorder.begin(dict(CTX))

    def test_not_evaluated_does_not_block(self) -> None:
        recorder.enforce_d1({"label": "ready-to-merge", "diff_class": recorder.DIFF_NOT_EVALUATED})

    def test_close_records_receipt_with_provenance(self) -> None:
        ids = recorder.identity(CTX["pr"], CTX["version"], CTX["run_id"])
        ids.update({"lease_fence": "3"})
        prov = {"label": "ready-to-merge", "authorized_by": "paulozterra", "authorized_head": "1" * 40,
                "final_head": CTX["head_sha"], "main_before": "2" * 40, "diff_class": recorder.DIFF_SYNC_ONLY,
                "diff_unexpected_paths": []}
        state = {"context": dict(CTX), "ids": ids, "provenance": prov}
        seen = {}
        def fake_call(sql, **params):
            if "supabase_migrations.schema_migrations" in sql:
                return {"version": CTX["version"], "name": CTX["name"]}
            if "lf_operation_execution_steps" in sql:
                return {}
            if "lf_record_db_operation_step_v1" in sql:
                return {"outcome": "STEP_RECORDED", "status": "PASS_CLEAN"}
            if "lf_close_db_operation_execution_v1" in sql:
                return {"result": "EXECUTION_COMPLETED"}
            if "lf_record_migration_train_receipt_v1" in sql:
                seen.update(params)
                return {"outcome": "TRAIN_RECEIPT_RECORDED", "event_id": 1}
            raise AssertionError(sql)
        with patch.object(recorder, "call", side_effect=fake_call):
            out = recorder.close(state, "e" * 40, "PASS")
        self.assertEqual(out["result"], "TRAIN_EXECUTION_COMPLETED")
        self.assertEqual(out["receipt"]["outcome"], "TRAIN_RECEIPT_RECORDED")
        self.assertEqual(seen["exec"], ids["execution_id"])
        self.assertEqual(seen["actor"], ids["actor"])
        self.assertEqual(json.loads(seen["prov"])["main_before"], "2" * 40)

    def test_close_fails_visibly_if_receipt_fails(self) -> None:
        ids = recorder.identity(CTX["pr"], CTX["version"], CTX["run_id"])
        ids.update({"lease_fence": "3"})
        state = {"context": dict(CTX), "ids": ids, "provenance": {"label": "ready-to-merge"}}
        def fake_call(sql, **params):
            if "supabase_migrations.schema_migrations" in sql:
                return {"version": CTX["version"], "name": CTX["name"]}
            if "lf_operation_execution_steps" in sql:
                return {"status": "PASS_CLEAN"}
            if "lf_close_db_operation_execution_v1" in sql:
                return {"result": "EXECUTION_COMPLETED"}
            if "lf_record_migration_train_receipt_v1" in sql:
                raise RuntimeError("TRAIN_EXEC_SQL_FAILED:TRAIN_RECEIPT_PROVENANCE_INVALID")
            raise AssertionError(sql)
        with patch.object(recorder, "call", side_effect=fake_call):
            with self.assertRaisesRegex(RuntimeError, "TRAIN_RECEIPT_PROVENANCE_INVALID"):
                recorder.close(state, "e" * 40, "PASS")

    def test_abort_keeps_abort_when_receipt_fails(self) -> None:
        ids = recorder.identity(CTX["pr"], CTX["version"], CTX["run_id"])
        ids.update({"lease_fence": "3", "lease_owner": "lf-migration-train-777"})
        state = {"context": dict(CTX), "ids": ids, "provenance": {"label": "ready-to-merge"}}
        def fake_call(sql, **params):
            if "lf_fail_db_operation_execution_v1" in sql:
                return {"result": "EXECUTION_BLOCKED_NO_LEDGER_EFFECT"}
            if "lf_record_migration_train_receipt_v1" in sql:
                raise RuntimeError("boom")
            raise AssertionError(sql)
        with patch.object(recorder, "call", side_effect=fake_call):
            out = recorder.abort(state, "777", "Apply", "failed")
        self.assertEqual(out["result"], "TRAIN_EXECUTION_ABORTED")
        self.assertIn("boom", out["receipt_error"])

    def test_migration_defines_writer_and_governed_event_type(self) -> None:
        sql = MIGRATION.read_text()
        self.assertIn("CREATE OR REPLACE FUNCTION public.lf_record_migration_train_receipt_v1(", sql)
        self.assertIn("fn_create_lf_event_type_contract_request_v2", sql)
        self.assertIn("fn_approve_lf_event_type_contract_request_v2", sql)
        self.assertIn("fn_apply_lf_event_type_contract_change_v2", sql)
        self.assertIn("REVOKE ALL ON FUNCTION public.lf_record_migration_train_receipt_v1(text, jsonb, text) FROM PUBLIC", sql)
        source = (HERE / "lf_train_execution_recorder.py").read_text()
        self.assertIn("public.lf_record_migration_train_receipt_v1(:'exec', (:'prov')::jsonb, :'actor')", source)


if __name__ == "__main__":
    unittest.main()
