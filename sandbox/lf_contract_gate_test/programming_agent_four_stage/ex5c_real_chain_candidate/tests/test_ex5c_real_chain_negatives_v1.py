"""Independent fail-closed EX5C negatives for PR #3733.

Uses original stage producers, never patches a tools/ module. The C5 alias
negative uses an isolated pre-existing C5 source-only fixture: the real EX5C
chain is blocked at PG11 C4 and must NOT be represented as reaching C5.
Tests are intentionally separate from the positive source-only assertions.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import ex5c_real_world_v1 as w  # noqa: E402

w.setup_paths()
import test_pg08_full_chain_v1 as t8  # noqa: E402
import test_pg09_iteration_chain_v1 as t9  # noqa: E402
import test_pg11_integrity_chain_v1 as t11  # noqa: E402
from pg08_c1_build_compilation_candidate_v1 import PG08C1Blocked  # noqa: E402
from pg08_c2_format_lint_delta_candidate_v1 import PG08C2Blocked, prepare_pg08_c2  # noqa: E402
from pg09_c1_iteration_cost_governor_candidate_v1 import prepare_pg09_c1  # noqa: E402
from pg09_c2_convergence_guard_candidate_v1 import PG09C2Blocked, prepare_pg09_c2  # noqa: E402
from pg11_c1_diff_hygiene_candidate_v1 import prepare_pg11_c1  # noqa: E402
from pg11_integrity_extension_candidate_v1 import (  # noqa: E402
    PG11IntegrityBlocked, guard_pg11_reviewer_aliases,
)


def rehash(obj):
    obj["candidate_sha256"] = hashlib.sha256(
        json.dumps({k: v for k, v in obj.items() if k != "candidate_sha256"},
                   sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    ).hexdigest()
    return obj


class EX5CRealChainNegatives(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Capture a distinct, already-existing C5 fixture before installation.
        # It is never passed off as evidence from real EX5C PG11 C4.
        cls.original_pg11_fixture = t11.fixture
        w.install()
        cls.addClassCleanup(w.uninstall)

    def test_uninstall_restores_test_builders_and_synthetic_chain(self):
        # Save the exact caller-side builders installed by w.install().
        originals = {
            (mod, attr): old
            for mod, attr, old in w._UNDO
            if attr != "__constants__"
        }
        self.assertTrue(originals)
        w.uninstall()
        try:
            self.assertEqual(w.OVERRIDES, [])
            self.assertEqual(w._UNDO, [])
            for (mod, attr), old in originals.items():
                self.assertIs(getattr(mod, attr), old)
            self.assertIs(t11.fixture, self.original_pg11_fixture)
            # Original synthetic builder must still construct its old chain.
            synthetic = t8.make_chain()
            self.assertNotEqual(synthetic["c1"]["target_repo"], w.REPO)
        finally:
            w.install()
        print("EX5C_REAL_UNINSTALL_SYNTHETIC_BUILDER_RESTORATION_PASS")

    def test_bundle_single_byte_mutation_blocks_v1_v2_v3(self):
        fixed = [
            ("lf-evidence-bundle-v1.json", w.V1_SHA),
            ("lf-evidence-bundle-v2.json", w.V2_SHA),
            ("lf-evidence-bundle-v3.json", w.V3_SHA),
        ]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for filename, expected in fixed:
                with self.subTest(bundle=filename):
                    raw = bytearray((w.FIXTURES / filename).read_bytes())
                    self.assertTrue(raw)
                    raw[-1] ^= 1
                    (root / filename).write_bytes(raw)
                    with patch.object(w, "FIXTURES", root):
                        with self.assertRaisesRegex(
                            AssertionError, r"^EX5C_REAL_BUNDLE_SHA_MISMATCH:"
                        ):
                            w.load_bundle(filename, expected)
        print("EX5C_REAL_V1_V2_V3_BYTE_TAMPER_BLOCK_PASS")

    def test_pg08_sol001_head_drift_in_pg07_evidence_blocks(self):
        # Original PG07 candidate envelope, modified and correctly rehashed.
        # Retain build observations for the pre-tamper HEAD.
        original = t8.pg07_chain()["c6"]
        source = copy.deepcopy(original)
        target = next(x for x in source["batches"] if x["solution_id"] == "SOL-001")
        target["candidate_head_sha_reported"] = "f" * 40
        rehash(source)
        receipts = w._receipts()
        observations = [
            {**t8.reported_base(original, item),
             "executor_result_ref": receipts[item["solution_id"]]["run"],
             "commands": [w._cmd(
                 "BUILD", receipts[item["solution_id"]]["run"] + "#maven",
                 "mvn", "JDK21", receipts[item["solution_id"]]["build"]
             )]}
            for item in original["batches"]
        ]
        with self.assertRaisesRegex(
            PG08C1Blocked, r"^PG08_C1_PG07_TARGET_OR_DIFF_DRIFT$"
        ):
            t8.prepare_pg08_c1(pg07_c6=source, build_observations=observations)
        print("EX5C_REAL_PG08_HEAD_DRIFT_BLOCK_PASS")

    def test_pg09_over_budget_requires_decision(self):
        real = t8.make_chain()
        pg07 = real["upstream"]
        observations = t9.cost_observations(pg07)
        sol1 = next(r for r in observations if r["solution_id"] == "SOL-001")
        # This is a tamper probe, NOT real spending.
        sol1["calls"][0]["reported_cost"] = "0.350001"
        out = prepare_pg09_c1(
            pg07_c1=pg07["c1"], pg07_c5=pg07["c5"],
            budget_policy=t9.policy(), usage_observations=observations,
        )
        self.assertEqual(out["request_diagnostic"], "REQUIRES_DECISION")
        self.assertTrue(out["requires_decision_reported"])
        self.assertEqual(out["reported_request_known_cost"], "0.350001")
        self.assertEqual(
            next(r for r in out["solutions"] if r["solution_id"] == "SOL-001")
            ["calls_reported"][0]["reported_cost"], "0.350001",
        )
        self.assertFalse(out["iteration_authorized"])
        print("EX5C_REAL_PG09_COST_ABOVE_0_35_REQUIRES_DECISION_PASS")

    def test_pg08_rehashed_authority_injection_blocks_at_c2(self):
        real = t8.make_chain()
        bad = copy.deepcopy(real["c1"])
        bad["production_authority"] = True
        rehash(bad)
        with self.assertRaisesRegex(PG08C2Blocked, r"^PG08_C2_PREMATURE_AUTHORITY$"):
            prepare_pg08_c2(
                pg06_c4=real["upstream"]["upstream"]["c4"],
                pg08_c1=bad, lint_observations=[],
            )
        print("EX5C_REAL_PG08_REHASHED_AUTHORITY_BLOCK_PASS")

    def test_pg09_rehashed_authority_injection_blocks_at_c2(self):
        real = t9.make_chain()
        bad = copy.deepcopy(real["c1"])
        bad["production_authority"] = True
        rehash(bad)
        with self.assertRaisesRegex(
            PG09C2Blocked, r"^PG09_C2_PREMATURE_SOURCE_AUTHORITY$"
        ):
            prepare_pg09_c2(
                pg07_c5=real["pg07"]["c5"],
                pg09_c1=bad,
                iteration_observations=t9.snapshots(real["pg07"]["c5"]),
            )
        print("EX5C_REAL_PG09_REHASHED_AUTHORITY_BLOCK_PASS")

    def test_pg11_c5_canonical_self_review_blocks_using_people_same(self):
        # Isolated C5 guard probe only. Do NOT claim real EX5C reached C5:
        # original EX5C C4 remains blocked by N:M authorized-scope contract.
        isolated = self.original_pg11_fixture()
        candidate = copy.deepcopy(isolated["c5"])
        reviews = candidate["reviews"]
        self.assertTrue(reviews)
        # Align the isolated source-only identities with w.people(same=True).
        for row in reviews:
            row["builder_principal_ref_reported"] = w.BUILDER["SOL-001"]
            row["reviewer_principal_ref_reported"] = w.REVIEWER
        rehash(candidate)
        with self.assertRaisesRegex(
            PG11IntegrityBlocked, r"^PG11_SELF_REVIEW_CANONICAL_ALIAS$"
        ):
            guard_pg11_reviewer_aliases(
                pg11_c5=candidate,
                principal_alias_records=t11.people(same=True),
            )
        print("EX5C_REAL_PG11_C5_CANONICAL_SELF_REVIEW_BLOCK_PASS_ISOLATED")

    def test_pg11_c1_undeclared_file_reports_scope_mismatch(self):
        # PG11 C1 returns findings (rather than raising) for this case.
        actual = t8.make_chain()
        self.assertEqual(actual["c1"]["target_repo"], w.REPO)
        changes = sorted(set(w.SOL1_FILES) | set(w.SOL2_FILES))
        declared_diff = [
            {"path": p, "change_type": "MODIFIED", "old_path": None}
            for p in changes
        ]
        authorized_scope = [
            {**row, "scope_ref": "ex5c://scope/declared",
             "requirement_ref": w.SPEC + "#FMT-AOSP-1",
             "batch_ref": "ex5c://batch/SOL-002"}
            for row in declared_diff
        ]
        unlisted = w.J + "/UnauthorizedExtra.java"
        declared_diff.append(
            {"path": unlisted, "change_type": "ADDED", "old_path": None}
        )
        out = prepare_pg11_c1(
            expected_base_sha=w.BASE, expected_head_sha=w.N1,
            declared_diff=declared_diff, authorized_scope=authorized_scope,
            residue_observations=[], dependency_observations=[],
            compatibility_observations=[],
        )
        self.assertEqual(
            out["findings"]["out_of_scope_paths_reported"], [unlisted]
        )
        self.assertIn("SCOPE_INVENTORY_MISMATCH", out["blocker_hints"])
        self.assertFalse(out["handoff_allowed"])
        print("EX5C_REAL_PG11_C1_OUT_OF_SCOPE_REPORTED_BLOCK_PASS")


if __name__ == "__main__":
    unittest.main()
