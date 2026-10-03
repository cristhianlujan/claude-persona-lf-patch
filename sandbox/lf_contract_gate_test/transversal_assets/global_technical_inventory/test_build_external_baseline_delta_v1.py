#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from build_external_baseline_delta_v1 import (
    DeltaBuildError,
    _last_commits_one_pass,
    build_delta,
)

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "external_baseline_delta_v1" / "report.template.json"


def run(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    return proc.stdout.strip()


def blob(repo: Path, rev_path: str) -> str:
    return run(repo, "rev-parse", rev_path)


class ExternalBaselineDeltaBuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        run(self.repo, "init", "-q")
        run(self.repo, "config", "user.email", "fixture@example.invalid")
        run(self.repo, "config", "user.name", "Fixture")

        (self.repo / "repo").mkdir()
        (self.repo / "repo" / "stale.py").write_text("old\n", encoding="utf-8")
        (self.repo / "repo" / "missing.sql").write_text("select 1;\n", encoding="utf-8")
        run(self.repo, "add", ".")
        run(self.repo, "commit", "-q", "-m", "fixture initial")
        self.stale_old_blob = blob(self.repo, "HEAD:repo/stale.py")
        self.missing_old_blob = blob(self.repo, "HEAD:repo/missing.sql")

        (self.repo / "repo" / "stale.py").write_text("new bytes\n", encoding="utf-8")
        (self.repo / "repo" / "new.txt").write_bytes(b"new\x00bytes\n")
        run(self.repo, "add", ".")
        run(self.repo, "commit", "-q", "-m", "fixture change")
        self.change_commit = run(self.repo, "rev-parse", "HEAD")
        self.stale_new_blob = blob(self.repo, "HEAD:repo/stale.py")
        self.new_blob = blob(self.repo, "HEAD:repo/new.txt")

        (self.repo / "repo" / "missing.sql").unlink()
        run(self.repo, "add", "-A")
        run(self.repo, "commit", "-q", "-m", "fixture remove")
        self.head = run(self.repo, "rev-parse", "HEAD")

        template = FIXTURE.read_text(encoding="utf-8")
        replacements = {
            "$HEAD": self.head,
            "$NEW_BLOB": self.new_blob,
            "$STALE_OLD_BLOB": self.stale_old_blob,
            "$STALE_NEW_BLOB": self.stale_new_blob,
            "$MISSING_OLD_BLOB": self.missing_old_blob,
        }
        for old, new in replacements.items():
            template = template.replace(old, new)
        self.report = json.loads(template)
        self.report_path = Path(self.temp.name) / "report.json"
        self.write_report(self.report)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_report(self, report: dict) -> None:
        self.report_path.write_text(
            json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

    def test_builds_minimal_repo_and_edge_delta(self) -> None:
        delta = build_delta(self.report_path, self.repo, self.head)
        self.assertEqual(delta["counts"]["repository"], {"NEW": 1, "STALE": 1, "MISSING": 1})
        self.assertEqual(delta["counts"]["edge"], {"NEW": 1, "STALE": 1, "MISSING": 1})
        self.assertEqual(delta["counts"]["runtime_without_source"], 1)
        self.assertEqual(delta["counts"]["total"], 6)
        self.assertRegex(delta["sync_key"], r"^[0-9a-f]{64}$")

        items = {(i["kind"], i.get("path") or i.get("slug")): i for i in delta["items"]}
        new_item = items[("REPO", "repo/new.txt")]
        self.assertEqual(new_item["git_blob"], self.new_blob)
        self.assertEqual(new_item["file_last_commit"], self.change_commit)
        self.assertEqual(new_item["bytes"], len(b"new\x00bytes\n"))
        self.assertEqual(new_item["extension"], "txt")
        self.assertEqual(new_item["sha256"], hashlib.sha256(b"new\x00bytes\n").hexdigest())

        stale_item = items[("REPO", "repo/stale.py")]
        self.assertEqual(stale_item["file_last_commit"], self.change_commit)
        self.assertEqual(stale_item["extension"], "py")
        self.assertRegex(stale_item["sha256"], r"^[0-9a-f]{64}$")

        missing_item = items[("REPO", "repo/missing.sql")]
        self.assertIsNone(missing_item["git_blob"])
        self.assertIsNone(missing_item["sha256"])
        self.assertIsNone(missing_item["file_last_commit"])
        self.assertIsNone(missing_item["bytes"])
        self.assertEqual(missing_item["extension"], "sql")

        edge_new = items[("EDGE", "edge-new")]
        self.assertEqual(edge_new["ezbr_sha256"], "a" * 64)
        self.assertEqual(edge_new["runtime_version"], 7)
        self.assertFalse(edge_new["verify_jwt"])
        self.assertEqual(edge_new["source_state"], "RUNTIME_WITHOUT_SOURCE")

    def test_last_commit_history_is_one_git_log_pass(self) -> None:
        calls = []
        real_run = subprocess.run

        def counted(*args, **kwargs):
            command = args[0]
            if isinstance(command, list) and "log" in command:
                calls.append(command)
            return real_run(*args, **kwargs)

        with patch("build_external_baseline_delta_v1.subprocess.run", side_effect=counted):
            result = _last_commits_one_pass(self.repo, ["repo/new.txt", "repo/stale.py"])
        self.assertEqual(len(calls), 1)
        self.assertNotIn("rev-list", " ".join(calls[0]))
        self.assertEqual(result["repo/new.txt"], self.change_commit)
        self.assertEqual(result["repo/stale.py"], self.change_commit)

    def test_fails_closed_on_checkout_sha_mismatch(self) -> None:
        report = copy.deepcopy(self.report)
        report["observed_main_sha"] = "f" * 40
        report["repository"]["observed_main_sha"] = "f" * 40
        self.write_report(report)
        with self.assertRaisesRegex(DeltaBuildError, "DELTA_CHECKOUT_SHA_MISMATCH"):
            build_delta(self.report_path, self.repo, "f" * 40)

    def test_fails_closed_on_tree_truncated(self) -> None:
        report = copy.deepcopy(self.report)
        report["repository"]["tree_truncated"] = True
        self.write_report(report)
        with self.assertRaisesRegex(DeltaBuildError, "DELTA_TREE_TRUNCATED"):
            build_delta(self.report_path, self.repo, self.head)

    def test_fails_closed_on_duplicate_path(self) -> None:
        report = copy.deepcopy(self.report)
        report["repository"]["records"].append(copy.deepcopy(report["repository"]["records"][0]))
        report["repository"]["counts"]["NEW"] = 2
        self.write_report(report)
        with self.assertRaisesRegex(DeltaBuildError, "DELTA_REPO_DUPLICATE_PATH"):
            build_delta(self.report_path, self.repo, self.head)

    def test_fails_closed_on_null_blob_for_present_repo_item(self) -> None:
        report = copy.deepcopy(self.report)
        report["repository"]["records"][0]["observed_git_blob"] = None
        self.write_report(report)
        with self.assertRaisesRegex(DeltaBuildError, "DELTA_REPO_BLOB_INVALID"):
            build_delta(self.report_path, self.repo, self.head)

    def test_fails_closed_on_null_edge_hash(self) -> None:
        report = copy.deepcopy(self.report)
        report["edge"]["records"][0]["runtime_sha256"] = None
        self.write_report(report)
        with self.assertRaisesRegex(DeltaBuildError, "DELTA_EDGE_HASH_INVALID"):
            build_delta(self.report_path, self.repo, self.head)


if __name__ == "__main__":
    unittest.main()
