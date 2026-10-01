#!/usr/bin/env python3
import unittest

from detect_external_currentness_v1 import build_report


def policy():
    return {
        "schema_version": "LF_EXTERNAL_CURRENTNESS_SCOPE_V1",
        "repository": {
            "mode": "ALL_GIT_BLOBS",
            "include_prefixes": [],
            "exclude_prefixes": [],
        },
        "edge_runtime": {
            "source_root": "supabase/functions/",
        },
    }


class ExternalCurrentnessDetectorTest(unittest.TestCase):
    def test_all_states_and_input_hashes(self):
        git_tree = {
            "sha": "main-sha",
            "truncated": False,
            "tree": [
                {"path": "sandbox/current.py", "type": "blob", "sha": "a"},
                {"path": "supabase/migrations/stale.sql", "type": "blob", "sha": "b2"},
                {"path": ".github/workflows/new.yml", "type": "blob", "sha": "n"},
                {
                    "path": "supabase/functions/current-fn/index.ts",
                    "type": "blob",
                    "sha": "fc",
                },
                {
                    "path": "supabase/functions/stale-fn/index.ts",
                    "type": "blob",
                    "sha": "fs",
                },
                {
                    "path": "supabase/functions/new-fn/index.ts",
                    "type": "blob",
                    "sha": "fn",
                },
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
                {
                    "slug": "current-fn",
                    "version": 2,
                    "ezbr_sha256": "h2",
                    "verify_jwt": True,
                },
                {
                    "slug": "stale-fn",
                    "version": 3,
                    "ezbr_sha256": "h3",
                    "verify_jwt": True,
                },
                {
                    "slug": "new-fn",
                    "version": 1,
                    "ezbr_sha256": "hn",
                    "verify_jwt": False,
                },
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

        report = build_report(
            git_tree, repo_inventory, edge_runtime, edge_inventory, policy()
        )

        self.assertEqual(
            report["repository"]["counts"],
            {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 4, "UNKNOWN": 0},
        )
        self.assertEqual(
            report["edge"]["counts"],
            {"CURRENT": 1, "STALE": 1, "MISSING": 1, "NEW": 1, "UNKNOWN": 0},
        )
        self.assertEqual(report["edge"]["runtime_without_source_count"], 0)
        self.assertEqual(report["input_digest_contract"], "SHA256_CANONICAL_JSON_V1")
        self.assertEqual(
            set(report["input_sha256"]),
            {
                "git_tree",
                "repo_inventory",
                "edge_runtime",
                "edge_inventory",
                "scope_policy",
            },
        )
        self.assertTrue(all(len(value) == 64 for value in report["input_sha256"].values()))
        self.assertTrue(report["pass_unknown_currentness"])

    def test_unknown_currentness_fails_closed(self):
        git_tree = {
            "sha": "main-sha",
            "truncated": False,
            "tree": [
                {"path": "repo-file.py", "type": "blob", "sha": "a"},
                {
                    "path": "supabase/functions/unknown-fn/index.ts",
                    "type": "blob",
                    "sha": "b",
                },
            ],
        }
        repo_inventory = [
            {"object_ref": "repo://repo-file.py", "metadata": {}, "active": True}
        ]
        edge_runtime = {
            "functions": [
                {
                    "slug": "unknown-fn",
                    "version": 1,
                    "ezbr_sha256": "h1",
                    "verify_jwt": True,
                }
            ]
        }
        edge_inventory = [
            {
                "object_ref": "edge://unknown-fn",
                "source_version": None,
                "definition_sha256": None,
                "active": True,
            }
        ]

        report = build_report(
            git_tree, repo_inventory, edge_runtime, edge_inventory, policy()
        )

        self.assertEqual(report["repository"]["counts"]["UNKNOWN"], 1)
        self.assertEqual(report["edge"]["counts"]["UNKNOWN"], 1)
        self.assertFalse(report["pass_unknown_currentness"])

    def test_truncated_git_tree_fails_closed(self):
        git_tree = {
            "sha": "main-sha",
            "truncated": True,
            "tree": [{"path": "a.py", "type": "blob", "sha": "a"}],
        }
        report = build_report(
            git_tree,
            [{"object_ref": "repo://a.py", "metadata": {"git_blob": "a"}}],
            {"functions": []},
            [],
            policy(),
        )

        self.assertTrue(report["repository"]["tree_truncated"])
        self.assertEqual(report["repository"]["counts"]["UNKNOWN"], 0)
        self.assertFalse(report["repository"]["pass_unknown_currentness"])
        self.assertFalse(report["pass_unknown_currentness"])

    def test_runtime_without_source_is_reported_as_debt(self):
        git_tree = {
            "sha": "main-sha",
            "truncated": False,
            "tree": [{"path": "README.md", "type": "blob", "sha": "r"}],
        }
        edge_runtime = {
            "functions": [
                {
                    "slug": "orphan-runtime",
                    "version": 7,
                    "ezbr_sha256": "runtime-hash",
                    "verify_jwt": False,
                }
            ]
        }
        edge_inventory = [
            {
                "object_ref": "edge://orphan-runtime",
                "source_version": "7",
                "definition_sha256": "runtime-hash",
                "active": True,
            }
        ]

        report = build_report(
            git_tree, [], edge_runtime, edge_inventory, policy()
        )

        self.assertEqual(report["edge"]["counts"]["CURRENT"], 1)
        self.assertEqual(report["edge"]["runtime_without_source_count"], 1)
        self.assertEqual(
            report["edge"]["runtime_without_source_verify_jwt_false_count"], 1
        )
        self.assertEqual(
            report["edge"]["runtime_without_source"], ["orphan-runtime"]
        )
        self.assertEqual(
            report["edge"]["records"][0]["source_state"],
            "RUNTIME_WITHOUT_SOURCE",
        )
        self.assertTrue(report["pass_unknown_currentness"])


if __name__ == "__main__":
    unittest.main()
