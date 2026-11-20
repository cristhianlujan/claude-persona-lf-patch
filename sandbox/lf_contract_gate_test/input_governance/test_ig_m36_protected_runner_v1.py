#!/usr/bin/env python3
"""Negative/positive tests of exact-HEAD M36 main-only rollback path.

This suite never connects to PostgreSQL or uses protected credentials.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import ig_m36_protected_runner_v1 as runner


class M36TrustedRunnerTests(unittest.TestCase):
    def test_01_exact_pin_has_real_candidate_blobs(self):
        self.assertEqual(runner.PR, 4075)
        self.assertEqual(runner.HEAD, "55f7f74f1b626ce965efa564dedd890fc417cbfb")
        self.assertEqual(runner.BLOBS, {
            runner.MIGRATION: "2cc1aa1f06be2a7a215885e14ec7f8ca6a8a1092",
            runner.HARNESS: "7f27e78db27d458ab01aaa27514516abde528c9c",
        })
        self.assertGreater(runner.TRIGGER_PR, 4075)
        src, receipts = runner.pinned_sources()
        self.assertIn("EXPLICIT_FIELD_REFERENCE_NONCURRENT", src[runner.MIGRATION])
        self.assertIn("CANDIDATE_AUTHORITY", src[runner.MIGRATION])
        for path, sha in runner.BLOBS.items():
            self.assertEqual(receipts[path]["git_blob"], sha)
            self.assertEqual(len(receipts[path]["sha256"]), 64)

    def test_02_other_head_rejected(self):
        with mock.patch.object(runner, "HEAD", "0" * 40):
            with self.assertRaisesRegex(RuntimeError, "^CANDIDATE_HEAD_CHANGED$"):
                runner.pinned_sources()

    def test_03_any_altered_blob_rejected(self):
        for name in runner.BLOBS:
            with self.subTest(file=name):
                wrong = {**runner.BLOBS, name: "0" * 40}
                with mock.patch.object(runner, "BLOBS", wrong):
                    with self.assertRaisesRegex(RuntimeError, "^PINNED_BLOB_DRIFT:"):
                        runner.pinned_sources()

    def test_04_one_real_sql_transaction_and_post_readback(self):
        sql, post, receipts = runner.assemble()
        self.assertEqual(len(receipts), 2)
        self.assertEqual(runner.guard.top_level_sql_statements(sql).count(("BEGIN",)), 1)
        self.assertEqual(runner.guard.top_level_sql_statements(sql).count(("ROLLBACK",)), 1)
        self.assertEqual(runner.guard.top_level_sql_statements(post), [("DO",)])
        self.assertEqual(sql.count("DO $m36$"), 1)
        self.assertIn("IG_M36_CANDIDATE_AUTHORITY_PASS", sql)
        self.assertIn("IG_M36_ALL_42_REGRESSION_PASS", sql)
        self.assertIn("IG_M36_POST_ROLLBACK_PASS", post)
        self.assertNotIn("\\ir", sql)
        self.assertNotIn("\\echo", sql)
        self.assertNotIn("\\set", sql)
        self.assertNotIn("COMMIT;", sql)

    def test_05_reject_top_level_transaction_escape(self):
        sql, _, _ = runner.assemble()
        original = "\nROLLBACK;"
        self.assertEqual(sql.count(original), 1)
        for instruction in ("COMMIT;", "END;", "PREPARE TRANSACTION 'x';",
                            "ROLLBACK PREPARED 'x';"):
            with self.subTest(instruction=instruction):
                injected = sql.replace(original, "\n" + instruction + original, 1)
                with self.assertRaisesRegex(RuntimeError, "COMMIT_FORBIDDEN"):
                    runner.guard.assert_safe_transaction_control(injected)

    def test_06_reject_new_psql_directives_even_if_other_blobs_are_re_pinned(self):
        src, _ = runner.pinned_sources()
        poisoned = src[runner.HARNESS].replace(
            r"\echo IG_M36_TX_BEGIN", r"\! env", 1
        )
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "candidate-readonly"
            for path, txt in ((runner.MIGRATION, src[runner.MIGRATION]),
                              (runner.HARNESS, poisoned)):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(txt)
            wrong = {**runner.BLOBS,
                     runner.HARNESS: runner.git_blob(poisoned.encode())}
            with mock.patch.object(runner, "BLOBS", wrong):
                with mock.patch.object(runner.subprocess, "check_output",
                                       return_value=runner.HEAD + "\n"):
                    with self.assertRaisesRegex(RuntimeError, "HARNESS_PSQL_DIRECTIVE_DRIFT"):
                        runner.assemble(root)

    def test_07_train_event_gates_reject_untrusted_context(self):
        variables = {"GITHUB_REPOSITORY": runner.REPO, "GITHUB_REF": "refs/heads/main",
                     "GITHUB_EVENT_NAME": "push", "GITHUB_ACTOR": "lf-migration-train[bot]"}
        cases = {
            "branch": {"GITHUB_REF": "refs/heads/dev"},
            "pull_request": {"GITHUB_EVENT_NAME": "pull_request"},
            "actor": {"GITHUB_ACTOR": "stranger"},
            "repo": {"GITHUB_REPOSITORY": "other/repo"},
        }
        for title, changes in cases.items():
            with self.subTest(title=title), mock.patch.dict(os.environ, variables | changes, clear=True):
                with self.assertRaises(RuntimeError):
                    runner.governance_check()

    def test_08_main_workflow_keeps_secrets_from_pr_jobs(self):
        text = (ROOT / ".github/workflows/lf-router-level2-advisory-tests.yml").read_text()
        self.assertIn("ig-m36-4075-trusted-static:", text)
        self.assertIn("ig-m36-4075-rollback-after-a2-train:", text)
        body = text.split("  ig-m36-4075-rollback-after-a2-train:\n", 1)[1]
        self.assertIn("github.event_name == 'push'", body)
        self.assertIn("github.actor == 'lf-migration-train[bot]'", body)
        self.assertIn("environment: lf-merge-train", body)
        self.assertIn("secrets.LF_SUPABASE_DB_PASSWORD", body)
        self.assertIn("persist-credentials: false", body)
        self.assertIn("actions/upload-artifact@v4", body)
        self.assertIn(str(runner.TRIGGER_PR), body)

    def test_09_trusted_runner_is_readback_only_and_produces_hashes(self):
        source = (HERE / "ig_m36_protected_runner_v1.py").read_text()
        for fragment in ("assembled_sql_sha256", "postgresql_log_sha256",
                         "independent_log_sha256", "report.json", "PINNED_BLOB_DRIFT",
                         "PR4075_HEAD_DRAFT_OR_BASE_DRIFT", "a2" if False else "A2_TRAIN_MERGE_IDENTITY_MISMATCH"):
            self.assertIn(fragment, source)
        self.assertNotIn("supabase db push", source)
        self.assertNotIn("git push", source)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(M36TrustedRunnerTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():
        print("IG_M36_A2_STATIC_NEGATIVE_POSITIVE_PASS 9/9")
    raise SystemExit(0 if result.wasSuccessful() else 1)
