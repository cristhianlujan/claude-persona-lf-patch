#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
C05_DIR = ROOT / "sandbox/lf_contract_gate_test/s30_d_final_r09"
sys.path.insert(0, str(C05_DIR))

from c05_reliability_oracle_v2 import Blocked, Store

MIGRATION_PATH = ROOT / "supabase/migrations/20260911025454_s30_c05_generic_execution_reliability_v1.sql"
SQL = MIGRATION_PATH.read_text(encoding="utf-8")


class G05ClaimLeaseFenceExistingAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = Store()
        self.operation = "PILOT_SRCR_UNIFIED_EXECUTION_V1"
        self.key = "g05-test"
        self.request_sha = "a" * 64
        self.target = ("PILOT", "SRCR", None, None)
        self.store.reserve(self.operation, self.key, self.request_sha, "EXEC-G05-001", self.target)

    def test_existing_canonical_owner_is_reused(self):
        required = (
            "create or replace function public.fn_lf_operation_acquire_lease_v1(",
            "create or replace function public.fn_lf_operation_checkpoint_v1(",
            "create or replace function public.fn_lf_operation_release_lease_v1(",
            "update public.lf_operation_execution",
            "LEASE_HELD",
            "STALE_OR_MISSING_LEASE_FENCE",
        )
        for token in required:
            self.assertIn(token, SQL)

    def test_current_lease_blocks_competing_owner(self):
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 30)
        second = self.store.acquire(self.operation, self.key, "worker-B", 1, 30)
        self.assertEqual(first["result"], "LEASE_ACQUIRED")
        self.assertEqual(second["result"], "BLOCKED")
        self.assertEqual(second["code"], "LEASE_HELD")
        self.assertEqual(second["lease_fence"], first["lease_fence"])

    def test_same_owner_renewal_preserves_current_fence(self):
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 30)
        renewed = self.store.acquire(self.operation, self.key, "worker-A", 10, 30)
        self.assertEqual(renewed["lease_fence"], first["lease_fence"])

    def test_expired_takeover_increments_fence(self):
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 5)
        takeover = self.store.acquire(self.operation, self.key, "worker-B", 6, 30)
        self.assertGreater(takeover["lease_fence"], first["lease_fence"])

    def test_stale_worker_cannot_checkpoint_after_takeover(self):
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 5)
        self.store.acquire(self.operation, self.key, "worker-B", 6, 30)
        with self.assertRaisesRegex(Blocked, "STALE_OR_MISSING_LEASE_FENCE"):
            self.store.checkpoint(
                self.operation,
                self.key,
                "worker-A",
                first["lease_fence"],
                1,
                {"checkpoint": "stale"},
                6,
            )

    def test_stale_worker_cannot_reserve_effect_after_takeover(self):
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 5)
        self.store.acquire(self.operation, self.key, "worker-B", 6, 30)
        with self.assertRaisesRegex(Blocked, "STALE_OR_MISSING_LEASE_FENCE"):
            self.store.reserve_effect(
                self.operation,
                self.key,
                "worker-A",
                first["lease_fence"],
                "G05_STALE_EFFECT",
                "b" * 64,
                "dispatch-g05-stale",
                6,
            )

    def test_release_requires_exact_owner_and_fence_in_canonical_sql(self):
        self.assertIn(
            "where execution_id=p_execution_id and lease_owner=p_lease_owner and lease_fence=p_lease_fence",
            SQL,
        )
        self.assertIn("raise exception 'STALE_OR_MISSING_LEASE_FENCE'", SQL)


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(
        "G05_CLAIM_LEASE_FENCE_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={result.testsRun} "
        f"RESULT={'PASS' if result.wasSuccessful() else 'FAIL'} "
        "REUSED_OWNER=public.lf_operation_execution "
        "MODEL_CALLS=0 PROD_MUTATIONS=0"
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
