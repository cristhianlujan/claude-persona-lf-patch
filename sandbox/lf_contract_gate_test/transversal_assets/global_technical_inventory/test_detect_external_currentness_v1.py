#!/usr/bin/env python3
import unittest

from detect_external_currentness_v1 import build_report


class ExternalCurrentnessDetectorTest(unittest.TestCase):
    def test_all_states_and_unknown_pass(self):
        git_tree = {
            "sha": "main-sha",
            "truncated": False,
            "tree": [
                {"path": "sandbox/current.py", "type": "blob", "sha": "a"},
                {"path": "supabase/migrations/stale.sql", "type": "blob", "sha": "b2"},
                {"path": ".github/workflows/new.yml", "type": "blob", "sha": "n"},
            ],
        }
        repo_inventory = [
            {
                "object_ref": "repo://sandbox/current.py",
                "metadata": {"git_blob": "a"},
                "active": True,
            },
            {
                "object_ref": "repo://supabase/migrations/stale.sql",
                "metadata": {"git_blob": "b1"},
                "active": True,
            },
            {
                "object_ref": "repo://supabase/functions/missing/index.ts",
                "metadata": {"git_blob": "c"},
                "active": True,
            },
        ]
        edge_runtime = {
            "functions": [
                {"slug": "current-fn", "version": 2, "ezbr_sha256": "h2"},
                {"slug": "stale-fn", "version": 3, "ezbr_sha256": "h3"},
                {"slug": "new-fn", "version": 1, "ezbr_sha256": "hn"},
            ]
        }
        edge_inventory = [
            {
                "object_ref": "edge://current-fn",
                "source_version": "2",
                "definition_sha256": "h2",
                "active": True,
            },
            {
                "object_ref": "edge://stale-fn",
                "source_version": "2",
                "definition_sha256": "old",
                "active": True,
            },
            {
                "object_ref": "edge://missing-fn",
                "source_version": "1",
                "definition_sha256": "hm",
                "active": True,
            },
        ]
        policy = {
            "schema_version": "LF_EXTERNAL_CURRENTNESS_SCOPE_V1",
            "repository": {
                "mode": "ALL_GIT_BLOBS",
                "include_prefixes": [],
                "exclude_prefixes": [],
            },
        }

        report = build_report(
            git_tree, repo_inventory, edge_runtime, edge_inventory, policy
        )

        self.assertEqual(
            report["repository"]["counts"],
            {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 1, "UNKNOWN": 0},
        )
        self.assertEqual(
            report["edge"]["counts"],
            {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 1, "UNKNOWN": 0},
        )
        self.assertTrue(report["pass_unknown_currentness"])


if __name__ == "__main__":
    unittest.main()
