#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261001214000_lf_pilot_srcr_unified_execution_g07_advance_execution_v1.sql"


def canonical_digest(registry: dict[str, Any], steps: list[dict[str, Any]]) -> str:
    payload = {"registry": registry, "steps": steps}
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Result:
    task_id: str
    step_id: str
    attempt_no: int
    lease_owner: str
    lease_fence: int
    outcome: str
    result_digest: str


class AdvanceModel:
    def __init__(self) -> None:
        self.registry = {"operation_code": "OP-1", "version": "v1"}
        self.steps = [
            {"step_id": "s1", "order": 10, "next_if_pass": "s2", "next_if_blocked": "RETURN_TO_ROUTER"},
            {"step_id": "s2", "order": 20, "next_if_pass": None, "next_if_blocked": "RETURN_TO_ROUTER"},
        ]
        self.frozen_digest = canonical_digest(self.registry, self.steps)
        self.current_digest = self.frozen_digest
        self.lease_owner = "worker-a"
        self.lease_fence = 7
        self.lease_valid = True
        self.current: tuple[str, str, int] | None = None
        self.advance_seq = 0
        self.tasks: set[tuple[str, str, int]] = set()
        self.results: dict[tuple[str, str, int], Result] = {}
        self.receipts: dict[tuple[Any, ...], dict[str, Any]] = {}

    def _guard_spec(self) -> None:
        if self.current_digest != self.frozen_digest:
            raise ValueError("FROZEN_OPERATION_SPEC_DIGEST_MISMATCH")

    def advance(self, source: tuple[str, str, int] | None = None) -> dict[str, Any]:
        self._guard_spec()
        key = ("INIT",) if source is None else ("RESULT",) + source
        if key in self.receipts:
            return {**self.receipts[key], "result": "REPLAY_ACCEPTED_ADVANCE"}

        if source is None:
            if self.advance_seq != 0 or self.current is not None:
                raise ValueError("EXECUTION_ALREADY_INITIALIZED")
            next_step = self.steps[0]["step_id"]
            disposition = "NEXT_TASK"
            next_identity = (next_step, next_step, 1)
        else:
            if self.current != source:
                raise ValueError("ADVANCE_SOURCE_IS_NOT_CURRENT_TASK")
            result = self.results.get(source)
            if result is None:
                raise ValueError("ACCEPTED_RESULT_NOT_FOUND")
            if (
                result.lease_owner != self.lease_owner
                or result.lease_fence != self.lease_fence
                or not self.lease_valid
            ):
                raise ValueError("STALE_OR_MISSING_LEASE_FENCE")
            if result.outcome not in {"SUCCEEDED", "BLOCKED"}:
                raise ValueError("ADVANCE_OUTCOME_REQUIRES_RETRY_POLICY")

            current_step = next(s for s in self.steps if s["step_id"] == source[1])
            next_ref = (
                current_step["next_if_pass"]
                if result.outcome == "SUCCEEDED"
                else current_step["next_if_blocked"]
            )
            known = {s["step_id"] for s in self.steps}
            if next_ref is None:
                disposition = "NO_NEXT_TASK"
                next_identity = None
            elif next_ref in known:
                disposition = "NEXT_TASK"
                next_identity = (next_ref, next_ref, 1)
            else:
                disposition = "EXTERNAL_HANDOFF"
                next_identity = None

        self.advance_seq += 1
        if next_identity is not None:
            self.tasks.add(next_identity)
            self.current = next_identity
        else:
            self.current = None
        receipt = {
            "advance_seq": self.advance_seq,
            "disposition": disposition,
            "current": self.current,
            "result": "ADVANCE_ACCEPTED",
        }
        self.receipts[key] = receipt
        return receipt


class G07AdvanceExecutionCandidateTests(unittest.TestCase):
    def test_sql_declares_sole_owner_and_canonical_execution_pointer(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("G07 is the sole owner of first-task selection", sql)
        self.assertIn("add column if not exists current_task_id text", sql)
        self.assertIn("add column if not exists current_step_id text", sql)
        self.assertIn("add column if not exists current_attempt_no integer", sql)
        self.assertIn("add column if not exists advance_seq bigint", sql)
        self.assertIn("ADVANCE_STATE_RECEIPT_REQUIRED", sql)

    def test_sql_binds_frozen_spec_digest_to_canonical_spec_rows(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("fn_lf_operation_spec_digest_v1", sql)
        self.assertIn("extensions.digest", sql)
        self.assertIn("FROZEN_OPERATION_SPEC_DIGEST_MISMATCH", sql)
        self.assertIn("lf_operation_step_contracts", sql)
        self.assertIn("lf_operation_steps", sql)

    def test_sql_consumes_g06_result_and_lease_fence(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("public.lf_operation_task_result", sql)
        self.assertIn("v_exec.lease_fence is distinct from v_result.lease_fence", sql)
        self.assertIn("STALE_OR_MISSING_LEASE_FENCE", sql)

    def test_initial_selection_is_owned_by_advance_execution(self) -> None:
        m = AdvanceModel()
        out = m.advance()
        self.assertEqual(out["disposition"], "NEXT_TASK")
        self.assertEqual(m.current, ("s1", "s1", 1))
        self.assertEqual(m.advance_seq, 1)

    def test_success_advances_exactly_one_next_task(self) -> None:
        m = AdvanceModel()
        m.advance()
        source = m.current
        assert source is not None
        m.results[source] = Result(*source, "worker-a", 7, "SUCCEEDED", "digest-1")
        out = m.advance(source)
        self.assertEqual(out["disposition"], "NEXT_TASK")
        self.assertEqual(m.current, ("s2", "s2", 1))
        self.assertEqual(m.advance_seq, 2)
        self.assertEqual(len(m.tasks), 2)

    def test_exact_advance_replay_is_idempotent(self) -> None:
        m = AdvanceModel()
        m.advance()
        source = m.current
        assert source is not None
        m.results[source] = Result(*source, "worker-a", 7, "SUCCEEDED", "digest-1")
        first = m.advance(source)
        replay = m.advance(source)
        self.assertEqual(first["advance_seq"], replay["advance_seq"])
        self.assertEqual(replay["result"], "REPLAY_ACCEPTED_ADVANCE")
        self.assertEqual(m.advance_seq, 2)

    def test_stale_fence_cannot_advance_state(self) -> None:
        m = AdvanceModel()
        m.advance()
        source = m.current
        assert source is not None
        m.results[source] = Result(*source, "worker-a", 6, "SUCCEEDED", "digest-1")
        with self.assertRaisesRegex(ValueError, "STALE_OR_MISSING_LEASE_FENCE"):
            m.advance(source)
        self.assertEqual(m.advance_seq, 1)

    def test_spec_drift_fails_closed(self) -> None:
        m = AdvanceModel()
        m.current_digest = "0" * 64
        with self.assertRaisesRegex(ValueError, "FROZEN_OPERATION_SPEC_DIGEST_MISMATCH"):
            m.advance()
        self.assertEqual(m.advance_seq, 0)

    def test_retry_outcomes_are_reserved_for_g10(self) -> None:
        m = AdvanceModel()
        m.advance()
        source = m.current
        assert source is not None
        m.results[source] = Result(*source, "worker-a", 7, "RETRYABLE_FAILURE", "digest-1")
        with self.assertRaisesRegex(ValueError, "ADVANCE_OUTCOME_REQUIRES_RETRY_POLICY"):
            m.advance(source)

    def test_final_step_produces_no_next_task_without_terminalizing(self) -> None:
        m = AdvanceModel()
        m.advance()
        first = m.current
        assert first is not None
        m.results[first] = Result(*first, "worker-a", 7, "SUCCEEDED", "digest-1")
        m.advance(first)
        second = m.current
        assert second is not None
        m.results[second] = Result(*second, "worker-a", 7, "SUCCEEDED", "digest-2")
        out = m.advance(second)
        self.assertEqual(out["disposition"], "NO_NEXT_TASK")
        self.assertIsNone(m.current)
        self.assertEqual(m.advance_seq, 3)


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G07_ADVANCE_EXECUTION_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
