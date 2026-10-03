#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import build_external_baseline_delta_v1 as delta


def git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc.stdout.strip()


def blob(repo: Path, sha: str, path: str) -> str:
    return git(repo, "rev-parse", f"{sha}:{path}")


class BaselineDeltaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        git(self.repo, "init", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.com")
        git(self.repo, "config", "user.name", "Test")

        (self.repo / "current.txt").write_bytes(b"current\n")
        (self.repo / "stale.txt").write_bytes(b"old\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-m", "initial")
        self.initial = git(self.repo, "rev-parse", "HEAD")

        (self.repo / "stale.txt").write_bytes(b"new bytes\n")
        (self.repo / "new.py").write_bytes(b"print('new')\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-m", "change stale and add new")
        self.head = git(self.repo, "rev-parse", "HEAD")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def report(self) -> dict:
        current_blob = blob(self.repo, self.head, "current.txt")
        stale_blob = blob(self.repo, self.head, "stale.txt")
        new_blob = blob(self.repo, self.head, "new.py")
        return {
            "schema_version": "LF_EXTERNAL_CURRENTNESS_REPORT_V1",
            "observed_main_sha": self.head,
            "pass_unknown_currentness": True,
            "repository": {
                "observed_main_sha": self.head,
                "tree_truncated": False,
                "unknown_currentness": 0,
                "counts": {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 1, "UNKNOWN": 0},
                "records": [
                    {"path": "current.txt", "state": "CURRENT", "observed_git_blob": current_blob},
                    {"path": "stale.txt", "state": "STALE", "observed_git_blob": stale_blob},
                    {"path": "missing.txt", "state": "MISSING", "observed_git_blob": None},
                    {"path": "new.py", "state": "NEW", "observed_git_blob": new_blob},
                ],
            },
            "edge": {
                "unknown_currentness": 0,
                "counts": {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 1, "UNKNOWN": 0},
                "records": [
                    {
                        "slug": "edge-current",
                        "state": "CURRENT",
                        "runtime_sha256": "1" * 64,
                        "runtime_version": 11,
                        "verify_jwt": False,
                        "source_state": "SOURCE_PRESENT",
                    },
                    {
                        "slug": "edge-stale",
                        "state": "STALE",
                        "runtime_sha256": "2" * 64,
                        "runtime_version": 12,
                        "verify_jwt": True,
                        "source_state": "SOURCE_PRESENT",
                    },
                    {
                        "slug": "edge-missing",
                        "state": "MISSING",
                        "runtime_sha256": None,
                        "runtime_version": None,
                        "verify_jwt": None,
                        "source_state": None,
                    },
                    {
                        "slug": "edge-new",
                        "state": "NEW",
                        "runtime_sha256": "3" * 64,
                        "runtime_version": 13,
                        "verify_jwt": False,
                        "source_state": "RUNTIME_WITHOUT_SOURCE",
                    },
                ],
            },
        }

    def test_builds_minimal_delta_and_uses_one_git_log_pass(self) -> None:
        report = self.report()
        original = delta._run_git
        calls: list[tuple[str, ...]] = []

        def recording(repo_root: Path, *args: str, **kwargs):
            calls.append(args)
            return original(repo_root, *args, **kwargs)

        with mock.patch.object(delta, "_run_git", side_effect=recording):
            result = delta.build_delta(report, self.repo, self.head)

        self.assertEqual(sum(1 for args in calls if args and args[0] == "log"), 1)
        self.assertEqual(result["expected_item_count"], 6)
        self.assertEqual(
            result["counts"],
            {
                "repository": {"NEW": 1, "STALE": 1, "MISSING": 1},
                "edge": {"NEW": 1, "STALE": 1, "MISSING": 1},
            },
        )
        self.assertEqual(result["runtime_without_source_count"], 1)
        self.assertRegex(result["sync_key"], r"^[0-9a-f]{64}$")

        items = {(x["source_kind"], x["object_key"]): x for x in result["items"]}
        stale = items[("REPO", "stale.txt")]
        self.assertEqual(stale["git_blob"], blob(self.repo, self.head, "stale.txt"))
        self.assertEqual(stale["definition_sha256"], hashlib.sha256(b"new bytes\n").hexdigest())
        self.assertEqual(stale["source_version"], self.head)
        self.assertEqual(stale["bytes"], len(b"new bytes\n"))
        self.assertEqual(stale["extension"], "txt")

        current = [x for x in result["items"] if x["object_key"] in ("current.txt", "edge-current")]
        self.assertEqual(current, [])
        self.assertEqual(items[("REPO", "missing.txt")], {"source_kind": "REPO", "object_key": "missing.txt", "state": "MISSING"})
        self.assertEqual(items[("EDGE", "edge-new")]["source_state"], "RUNTIME_WITHOUT_SOURCE")

    def test_sha_mismatch_fails_closed(self) -> None:
        report = self.report()
        report["observed_main_sha"] = "a" * 40
        with self.assertRaisesRegex(delta.DeltaError, "BASELINE_DELTA_REPORT_SHA_MISMATCH"):
            delta.build_delta(report, self.repo, self.head)

    def test_truncated_tree_fails_closed(self) -> None:
        report = self.report()
        report["repository"]["tree_truncated"] = True
        with self.assertRaisesRegex(delta.DeltaError, "BASELINE_DELTA_TREE_TRUNCATED"):
            delta.build_delta(report, self.repo, self.head)

    def test_duplicate_repo_path_fails_closed(self) -> None:
        report = self.report()
        report["repository"]["records"].append(dict(report["repository"]["records"][0]))
        report["repository"]["counts"]["CURRENT"] += 1
        with self.assertRaisesRegex(delta.DeltaError, "BASELINE_DELTA_REPOSITORY_DUPLICATE"):
            delta.build_delta(report, self.repo, self.head)

    def test_null_repo_blob_fails_closed(self) -> None:
        report = self.report()
        next(x for x in report["repository"]["records"] if x["path"] == "new.py")["observed_git_blob"] = None
        with self.assertRaisesRegex(delta.DeltaError, "BASELINE_DELTA_REPO_BLOB_MISSING"):
            delta.build_delta(report, self.repo, self.head)

    def test_null_edge_hash_fails_closed(self) -> None:
        report = self.report()
        next(x for x in report["edge"]["records"] if x["slug"] == "edge-new")["runtime_sha256"] = None
        with self.assertRaisesRegex(delta.DeltaError, "BASELINE_DELTA_EDGE_HASH_MISSING"):
            delta.build_delta(report, self.repo, self.head)


if __name__ == "__main__":
    unittest.main()
