#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261003003000_lf_pilot_srcr_g12_state_authority_v1.sql"


def reconciled(queue_status: str, canonical_status: str, error_code: str | None = None) -> bool:
    if queue_status in {"PENDING", "RUNNING"}:
        return False
    if queue_status == "BLOCKED" and error_code == "HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING":
        return False
    expected = {
        "SUCCEEDED": "COMPLETED",
        "FAILED": "BLOCKED",
        "BLOCKED": "BLOCKED",
        "CANCELLED": "CANCELLED",
    }.get(queue_status)
    return expected is not None and canonical_status == expected


class G12StateAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_preserves_public_function_abi(self) -> None:
        self.assertIn(
            "create or replace function public.lf_profile_execution_reconcile_queue_terminal_v1(",
            self.sql,
        )
        self.assertIn("p_request_id uuid", self.sql)
        self.assertIn("p_actor_execution_id text", self.sql)
        self.assertIn("security definer", self.sql)

    def test_queue_is_explicitly_non_authoritative(self) -> None:
        self.assertIn("'queue_authoritative',false", self.sql)
        self.assertIn("transport/projection only", self.sql)
        self.assertIn("queue terminal state is evidence only", self.sql)

    def test_reconciliation_is_read_only_against_canonical_execution(self) -> None:
        self.assertNotIn("update public.lf_operation_execution", self.sql)
        self.assertNotIn("insert into public.lf_operation_execution", self.sql)
        self.assertNotIn("delete from public.lf_operation_execution", self.sql)
        self.assertNotIn("for update", self.sql)
        self.assertNotIn("canonical_status_after", self.sql)

    def test_queue_terminal_mismatch_fails_closed_without_transition(self) -> None:
        self.assertIn("queue_terminal_canonical_not_reconciled", self.sql)
        self.assertIn("expected_canonical_status", self.sql)
        self.assertIn("profile_execution_terminality_reconciliation_failed", self.sql)

    def test_success_only_reconciles_with_canonical_completed(self) -> None:
        self.assertTrue(reconciled("SUCCEEDED", "COMPLETED"))
        self.assertFalse(reconciled("SUCCEEDED", "IN_PROGRESS"))
        self.assertFalse(reconciled("SUCCEEDED", "BLOCKED"))

    def test_failure_or_block_only_reconciles_with_canonical_blocked(self) -> None:
        self.assertTrue(reconciled("FAILED", "BLOCKED"))
        self.assertTrue(reconciled("BLOCKED", "BLOCKED"))
        self.assertFalse(reconciled("FAILED", "IN_PROGRESS"))
        self.assertFalse(reconciled("BLOCKED", "IN_PROGRESS"))

    def test_cancel_only_reconciles_with_canonical_cancelled(self) -> None:
        self.assertTrue(reconciled("CANCELLED", "CANCELLED"))
        self.assertFalse(reconciled("CANCELLED", "IN_PROGRESS"))

    def test_nonterminal_transport_state_never_closes_execution(self) -> None:
        self.assertFalse(reconciled("PENDING", "IN_PROGRESS"))
        self.assertFalse(reconciled("RUNNING", "IN_PROGRESS"))
        self.assertFalse(
            reconciled(
                "BLOCKED",
                "IN_PROGRESS",
                "HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING",
            )
        )

    def test_only_known_terminal_projection_states_are_supported(self) -> None:
        self.assertFalse(reconciled("UNKNOWN", "BLOCKED"))
        self.assertFalse(reconciled("RETRYING", "IN_PROGRESS"))


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G12_STATE_AUTHORITY_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "QUEUE_CANONICAL_MUTATIONS=0 MODEL_CALLS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
