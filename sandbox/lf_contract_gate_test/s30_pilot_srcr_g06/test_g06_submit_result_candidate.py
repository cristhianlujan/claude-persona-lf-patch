#!/usr/bin/env python3
from __future__ import annotations

import unittest
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260923213500_lf_pilot_srcr_unified_execution_g06_submit_result_v1.sql"


@dataclass(frozen=True)
class Claim:
    execution_id: str
    task_id: str
    step_id: str
    attempt_no: int


@dataclass(frozen=True)
class Result:
    claim: Claim
    lease_owner: str
    lease_fence: int
    outcome: str
    result_digest: str
    evidence_refs: tuple[str, ...]


class SubmitResultModel:
    def __init__(self) -> None:
        self.current_lease = {"execution_id": "EXEC-1", "owner": "worker-a", "fence": 7, "valid": True}
        self.claims: set[Claim] = set()
        self.results: dict[Claim, Result] = {}
        self.execution_status = "IN_PROGRESS"

    def bind(self, claim: Claim) -> None:
        self.claims.add(claim)

    def submit(self, result: Result) -> str:
        lease = self.current_lease
        if (
            result.claim.execution_id != lease["execution_id"]
            or result.lease_owner != lease["owner"]
            or result.lease_fence != lease["fence"]
            or not lease["valid"]
        ):
            raise ValueError("STALE_OR_MISSING_LEASE_FENCE")
        if result.claim not in self.claims:
            raise ValueError("RESULT_TASK_IDENTITY_MISMATCH")
        existing = self.results.get(result.claim)
        if existing is None:
            self.results[result.claim] = result
            return "RESULT_ACCEPTED"
        if existing != result:
            raise ValueError("RESULT_IDENTITY_REUSED_WITH_DIFFERENT_PAYLOAD")
        return "REPLAY_ACCEPTED_RESULT"


def valid_result() -> Result:
    return Result(
        claim=Claim("EXEC-1", "TASK-1", "STEP-1", 1),
        lease_owner="worker-a",
        lease_fence=7,
        outcome="SUCCEEDED",
        result_digest="digest-result-1",
        evidence_refs=("evidence://1",),
    )


class G06SubmitResultCandidateTests(unittest.TestCase):
    def test_sql_binds_result_to_exact_claim_identity(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("foreign key (execution_id, task_id, step_id, attempt_no)", sql)
        self.assertIn("RESULT_TASK_IDENTITY_MISMATCH", sql)
        self.assertIn("primary key (execution_id, task_id, step_id, attempt_no)", sql)

    def test_sql_enforces_current_nonexpired_fence(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("v_exec.lease_owner is distinct from p_lease_owner", sql)
        self.assertIn("v_exec.lease_fence is distinct from p_lease_fence", sql)
        self.assertIn("v_exec.lease_expires_at <= v_now", sql)
        self.assertIn("STALE_OR_MISSING_LEASE_FENCE", sql)

    def test_sql_is_idempotent_but_rejects_conflicting_reuse(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("on conflict (execution_id, task_id, step_id, attempt_no) do nothing", sql)
        self.assertIn("REPLAY_ACCEPTED_RESULT", sql)
        self.assertIn("RESULT_IDENTITY_REUSED_WITH_DIFFERENT_PAYLOAD", sql)

    def test_submit_function_does_not_advance_execution_state(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8")
        start = sql.index("create or replace function public.fn_lf_operation_submit_result_v1")
        end = sql.index("revoke all on function public.fn_lf_operation_submit_result_v1", start)
        body = sql[start:end].lower()
        self.assertNotIn("update public.lf_operation_execution", body)
        self.assertNotIn("set status=", body)
        self.assertIn("'execution_state_advanced', false", body)

    def test_current_claim_is_accepted_and_exact_replay_is_idempotent(self) -> None:
        model = SubmitResultModel()
        result = valid_result()
        model.bind(result.claim)
        self.assertEqual(model.submit(result), "RESULT_ACCEPTED")
        self.assertEqual(model.submit(result), "REPLAY_ACCEPTED_RESULT")
        self.assertEqual(model.execution_status, "IN_PROGRESS")

    def test_stale_fence_is_rejected(self) -> None:
        model = SubmitResultModel()
        result = valid_result()
        model.bind(result.claim)
        stale = Result(result.claim, result.lease_owner, 6, result.outcome, result.result_digest, result.evidence_refs)
        with self.assertRaisesRegex(ValueError, "STALE_OR_MISSING_LEASE_FENCE"):
            model.submit(stale)

    def test_unclaimed_or_mismatched_task_identity_is_rejected(self) -> None:
        model = SubmitResultModel()
        result = valid_result()
        with self.assertRaisesRegex(ValueError, "RESULT_TASK_IDENTITY_MISMATCH"):
            model.submit(result)
        model.bind(result.claim)
        wrong_attempt = Result(
            Claim("EXEC-1", "TASK-1", "STEP-1", 2),
            result.lease_owner,
            result.lease_fence,
            result.outcome,
            result.result_digest,
            result.evidence_refs,
        )
        with self.assertRaisesRegex(ValueError, "RESULT_TASK_IDENTITY_MISMATCH"):
            model.submit(wrong_attempt)

    def test_same_identity_with_changed_payload_is_rejected(self) -> None:
        model = SubmitResultModel()
        result = valid_result()
        model.bind(result.claim)
        self.assertEqual(model.submit(result), "RESULT_ACCEPTED")
        changed = Result(
            result.claim,
            result.lease_owner,
            result.lease_fence,
            "FAILED",
            "different-digest",
            result.evidence_refs,
        )
        with self.assertRaisesRegex(ValueError, "RESULT_IDENTITY_REUSED_WITH_DIFFERENT_PAYLOAD"):
            model.submit(changed)


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G06_SUBMIT_RESULT_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
