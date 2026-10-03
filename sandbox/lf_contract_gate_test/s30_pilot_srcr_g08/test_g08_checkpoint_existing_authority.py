#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
C05_DIR = ROOT / "sandbox/lf_contract_gate_test/s30_d_final_r09"
sys.path.insert(0, str(C05_DIR))

from c05_reliability_oracle_v2 import Blocked, Store

RELIABILITY_MIGRATION = ROOT / "supabase/migrations/20260911025454_s30_c05_generic_execution_reliability_v1.sql"
G07_MIGRATION = ROOT / "supabase/migrations/20261001214000_lf_pilot_srcr_unified_execution_g07_advance_execution_v1.sql"
SQL = RELIABILITY_MIGRATION.read_text(encoding="utf-8")
G07_SQL = G07_MIGRATION.read_text(encoding="utf-8")


class G08CheckpointExistingAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = Store()
        self.operation = "PILOT_SRCR_UNIFIED_EXECUTION_V1"
        self.key = "g08-test"
        self.request_sha = "a" * 64
        self.target = ("PILOT", "SRCR", None, None)
        self.store.reserve(self.operation, self.key, self.request_sha, "EXEC-G08-001", self.target)

    def _acquire(self) -> int:
        lease = self.store.acquire(self.operation, self.key, "worker-A", 0, 30)
        self.assertEqual(lease["result"], "LEASE_ACQUIRED")
        return lease["lease_fence"]

    def test_reuses_existing_canonical_checkpoint_owner(self) -> None:
        required = (
            "create or replace function public.fn_lf_operation_checkpoint_v1(",
            "update public.lf_operation_execution",
            "checkpoint_seq=p_checkpoint_seq",
            "checkpoint_payload=p_checkpoint_payload",
            "STALE_OR_MISSING_LEASE_FENCE",
            "CHECKPOINT_NON_MONOTONIC",
            "CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD",
            "REPLAY_CHECKPOINT",
            "CHECKPOINT_PERSISTED",
        )
        for token in required:
            self.assertIn(token, SQL)

    def test_checkpoint_does_not_own_g07_task_selection_or_terminality(self) -> None:
        start = SQL.index("create or replace function public.fn_lf_operation_checkpoint_v1")
        end = SQL.index("create or replace function public.fn_lf_operation_release_lease_v1", start)
        body = SQL[start:end].lower()
        for forbidden in (
            "current_task_id",
            "current_step_id",
            "current_attempt_no",
            "advance_seq",
            "lf_operation_advance_receipt",
            "lf_operation_steps",
            "next_if_pass",
            "next_if_blocked",
            "set status=",
            "completed_at",
        ):
            self.assertNotIn(forbidden, body)
        self.assertIn("G07 is the sole owner of first-task selection", G07_SQL)
        self.assertIn("It does not own checkpointing", G07_SQL)

    def test_checkpoint_persist_and_exact_replay(self) -> None:
        fence = self._acquire()
        first = self.store.checkpoint(
            self.operation, self.key, "worker-A", fence, 1, {"resume_ref": "A"}, 1
        )
        replay = self.store.checkpoint(
            self.operation, self.key, "worker-A", fence, 1, {"resume_ref": "A"}, 2
        )
        self.assertEqual(first["result"], "CHECKPOINT_PERSISTED")
        self.assertEqual(replay["result"], "REPLAY_CHECKPOINT")

    def test_same_seq_different_payload_is_rejected(self) -> None:
        fence = self._acquire()
        self.store.checkpoint(
            self.operation, self.key, "worker-A", fence, 1, {"resume_ref": "A"}, 1
        )
        with self.assertRaisesRegex(Blocked, "CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD"):
            self.store.checkpoint(
                self.operation, self.key, "worker-A", fence, 1, {"resume_ref": "B"}, 2
            )

    def test_non_monotonic_checkpoint_is_rejected(self) -> None:
        fence = self._acquire()
        self.store.checkpoint(
            self.operation, self.key, "worker-A", fence, 2, {"resume_ref": "B"}, 1
        )
        with self.assertRaisesRegex(Blocked, "CHECKPOINT_NON_MONOTONIC"):
            self.store.checkpoint(
                self.operation, self.key, "worker-A", fence, 1, {"resume_ref": "A"}, 2
            )

    def test_stale_fence_is_rejected_after_takeover(self) -> None:
        first = self.store.acquire(self.operation, self.key, "worker-A", 0, 5)
        self.store.acquire(self.operation, self.key, "worker-B", 6, 30)
        with self.assertRaisesRegex(Blocked, "STALE_OR_MISSING_LEASE_FENCE"):
            self.store.checkpoint(
                self.operation,
                self.key,
                "worker-A",
                first["lease_fence"],
                1,
                {"resume_ref": "stale"},
                6,
            )

    def test_checkpoint_payload_is_supplemental_to_canonical_execution_state(self) -> None:
        start = SQL.index("update public.lf_operation_execution", SQL.index("fn_lf_operation_checkpoint_v1"))
        end = SQL.index("where execution_id=p_execution_id;", start)
        update_stmt = SQL[start:end].lower()
        self.assertIn("checkpoint_seq=p_checkpoint_seq", update_stmt)
        self.assertIn("checkpoint_payload=p_checkpoint_payload", update_stmt)
        self.assertIn("updated_by_execution_id=p_actor_execution_id", update_stmt)
        for forbidden in ("current_task_id", "current_step_id", "current_attempt_no", "advance_seq", "status"):
            self.assertNotIn(forbidden, update_stmt)


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G08_CHECKPOINT_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "REUSED_OWNER=public.fn_lf_operation_checkpoint_v1 "
        "MODEL_CALLS=0 PROD_MUTATIONS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
