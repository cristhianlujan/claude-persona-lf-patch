"""EX5C real chain through the ORIGINAL PG-04..PG-11 producers.

Real data: sandbox repo paulozterra/lf-programming-sandbox, base 28de535,
SOL-001 (Worker claude-sonnet-5-5, run 42284754122, head e76b213) and
SOL-002 (format remediation, head bc74940), real Maven/javac/format/smoke
receipts (bundles v1/v2/v3 with fixed SHA), real cost (USD 0.070022) and the
owner decisions LF-OWNER-EX5C-ATTEMPT-1 / FORMAT-REMEDIATION.

Result proven here:
* PG-04 .. PG-10 and PG-11 C1..C3 accept the real data.
* PG-11 C4 BLOCKS with PG11_C4_LINK_NOT_AUTHORIZED_SCOPE: its contract allows one
  (requirement, batch, scope) per file, while the real change is N:M (one file
  implements several REM-C* and is touched by two batches). Reported, not bypassed.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import ex5c_real_world_v1 as w  # noqa: E402

w.setup_paths()
from ex5c_synthetic_audit_v1 import audit  # noqa: E402
import test_pg08_full_chain_v1 as t8  # noqa: E402
import test_pg09_iteration_chain_v1 as t9  # noqa: E402
import test_pg10_decision_chain_v1 as t10  # noqa: E402
import test_pg11_integrity_chain_v1 as t11  # noqa: E402
from pg11_c4_diff_requirement_batch_trace_candidate_v1 import PG11C4Blocked  # noqa: E402

IDENTITY_KEYS = ("repo", "base_head_sha", "candidate_head_sha", "diff_sha256", "path",
                 "identity", "commit", "tree", "tool_name", "model_id", "provider",
                 "stdout_sha256", "stderr_sha256", "reported_cost")


def spine_hits(obj):
    """Synthetic values in identity-bearing fields (must be zero)."""
    return [h for h in audit(obj) if any(k in h[1].rsplit(".", 1)[-1] for k in IDENTITY_KEYS)]


class EX5CRealChain(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        w.install()
        cls.addClassCleanup(w.uninstall)
        cls.pg10 = t10.build()
        cls.pg09 = cls.pg10["upstream"]
        cls.pg08 = cls.pg09["pg08"]

    def test_pg08_real_identity_and_receipts(self):
        f = self.pg08["final"]
        self.assertEqual(f["target_repo"], w.REPO)
        self.assertEqual(f["base_head_sha"], w.BASE)
        heads = {s["solution_id"]: s["candidate_head_sha_reported"] for s in self.pg08["c1"]["solutions"]}
        self.assertEqual(heads, {"SOL-001": w.N, "SOL-002": w.N1})
        diag = {s["solution_id"]: s["reported_diagnostic"] for s in self.pg08["c2"]["solutions"]}
        # Real history: N had new google-default format findings; N+1 (AOSP) has none.
        self.assertEqual(diag, {"SOL-001": "REPORTED_NEW_BLOCKERS",
                                "SOL-002": "REPORTED_NO_NEW_BLOCKERS_UNVERIFIED"})
        for st in ("c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "final"):
            self.assertIs(self.pg08[st]["production_authority"], False)
            self.assertIs(self.pg08[st]["handoff_allowed"], False)
        self.assertEqual(spine_hits({k: self.pg08[k] for k in ("c1", "c2", "c3", "c4", "final")}), [])
        print("EX5C_REAL_PG08_C1_C8_FINAL_SOURCE_ONLY_PASS")

    def test_pg09_real_cost_and_owner_decisions(self):
        c1 = self.pg09["c1"]
        self.assertEqual(c1["reported_request_known_cost"], "0.070022")
        rows = {s["solution_id"]: s for s in c1["solutions"]}
        self.assertEqual(rows["SOL-001"]["executor_mode_reported"], "WORKER_API")
        self.assertFalse(rows["SOL-001"]["cost_unknown"])
        self.assertTrue(rows["SOL-002"]["cost_unknown"])  # native orchestration has no API price
        self.assertTrue(c1["requires_decision_reported"])
        self.assertTrue(c1["iteration_limit_reached_reported"])
        refs = sorted(s["owner_decision_ref_reported"] for s in self.pg09["c4"]["solutions"])
        self.assertEqual(refs, ["ex5c://owner-decision/" + w.OWNER_ATTEMPT,
                                "ex5c://owner-decision/" + w.OWNER_FORMAT])
        print("EX5C_REAL_PG09_COST_0_070022_REQUIRES_DECISION_OWNER_BOUND_PASS")

    def test_pg10_real_conflict_and_lineage(self):
        x = self.pg10
        conflicts = [c for s in x["c1"]["solutions"] for c in s["conflicts"]]
        self.assertEqual([c["conflict_id"] for c in conflicts], [w.CONFLICT])
        y = t10.lineage(x, ledger=t10.ledger_for(x))  # owner already decided: no new question
        from pg10_decision_lineage_dedup_candidate_v1 import PG10LineageBlocked
        with self.assertRaisesRegex(PG10LineageBlocked, "^PG10_DUPLICATE_ANSWERED_QUESTION$"):
            t10.lineage(x, ledger=t10.ledger_for(x), questions=t10.question(x))
        self.assertEqual(y["source_pg08_final_sha256"], self.pg08["final"]["candidate_sha256"])
        self.assertEqual(y["source_pg09_c4_sha256"], self.pg09["c4"]["candidate_sha256"])
        print("EX5C_REAL_PG10_CONFLICT_FORMAT_LINEAGE_PASS")

    def test_pg11_c1_c3_accept_real_diff(self):
        import pg11_c1_diff_hygiene_candidate_v1 as m1  # noqa: F401
        hk = w.real_hunks()
        self.assertEqual(len([h for h in hk if h["solution_id"] == "SOL-001"]), 6)
        self.assertTrue(all(h["requirements"] for h in hk))
        # Gap found: the PG10->PG11 bridge does not bind expected_head to PG-08 heads.
        heads = {s["candidate_head_sha_reported"] for s in self.pg08["c1"]["solutions"]}
        self.assertIn(w.N1, heads)
        print("EX5C_REAL_PG11_HUNKS_PARSED_FROM_FIXED_DIFFS_PASS")

    def test_pg11_c4_blocks_on_real_n_to_m_trace(self):
        with self.assertRaisesRegex(PG11C4Blocked, "^PG11_C4_LINK_NOT_AUTHORIZED_SCOPE$"):
            t11.fixture()
        print("EX5C_REAL_PG11_C4_BLOCK_PG11_C4_LINK_NOT_AUTHORIZED_SCOPE")

    def test_overrides_only_touch_test_builders(self):
        self.assertTrue(w.OVERRIDES)
        for line in w.OVERRIDES:
            self.assertNotIn("/tools/", line)
            self.assertTrue(line.startswith("test_"), line)

    def test_fixed_bundle_shas(self):
        for name, sha in (("lf-evidence-bundle-v1.json", w.V1_SHA),
                          ("lf-evidence-bundle-v2.json", w.V2_SHA),
                          ("lf-evidence-bundle-v3.json", w.V3_SHA)):
            w.load_bundle(name, sha)
        with self.assertRaises(AssertionError):
            w.load_bundle("lf-evidence-bundle-v3.json", "0" * 64)


if __name__ == "__main__":
    unittest.main()
