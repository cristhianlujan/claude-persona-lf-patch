"""Original EX6 source truth / true v1 producer attempts, no foreign fixtures."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import ex6_source_truth_v1 as source
import ex6_real_chain_v1 as chain


class EX6ChainV1Tests(unittest.TestCase):
    def test_real_public_source_and_three_hunks(self):
        truth = source.source_truth()
        self.assertEqual(truth["holdout_sha256"], source.EXPECTED_HOLDOUT)
        self.assertEqual(truth["holdout_result"], "PASS")
        self.assertEqual(truth["api_calls"], 0)
        self.assertEqual(truth["incremental_api_cost"], "0")
        self.assertEqual(sorted(x["path"] for x in truth["hunks"]), truth["write_paths"])
        self.assertEqual(len(truth["hunks"]), 3)
        self.assertFalse(truth["production_authority"])

    def test_authorization_is_exact_single_batch_and_scope_per_file(self):
        truth = source.source_truth()
        changed, authorization, traces = chain.authorize_from_real_hunks(truth)
        self.assertEqual(len(changed), len(authorization))
        self.assertEqual(len(traces), 3)
        for row in authorization:
            self.assertEqual(row["change_type"], "ADDED")
            self.assertEqual(len({a["batch_ref"] for a in row["authorized_links"]}), 1)
            self.assertEqual(len({a["scope_ref"] for a in row["authorized_links"]}), 1)
        self.assertEqual(sum(len(r["authorized_links"]) for r in authorization), 4)

    def test_no_foreign_exercise_data_or_references(self):
        data = json.dumps(source.source_truth(), sort_keys=True).lower()
        self.assertNotIn("ex5c", data)
        self.assertNotIn("lote-c", data)
        self.assertFalse(source.source_truth()["production_authority"])

    def test_install_uninstall_has_no_synthetic_pollution(self):
        before = sys.path[:]
        chain.install()
        self.assertNotEqual(before, sys.path)
        chain.uninstall()
        self.assertEqual(before, sys.path)

    def test_pg04_to_pg14_does_not_claim_unrun_stages(self):
        result = chain.run_v1()
        self.assertEqual(len(result), 11)
        self.assertEqual([r["stage"] for r in result], list(chain.STAGE_ORDER))
        self.assertTrue(all(r["before_v2"] in ("PASS_SOURCE_ONLY", "BLOCK", "NOT_RUN_UPSTREAM_BLOCKED") for r in result))
        self.assertTrue(all(not r["producer_invoked"] for r in result
                            if r["code"] and r["code"].startswith("UPSTREAM_BLOCKED:")))
        self.assertFalse(any(r.get("production_authority", False) for r in result))


if __name__ == "__main__":
    unittest.main()
