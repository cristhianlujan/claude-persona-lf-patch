#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261002071500_lf_pilot_srcr_unified_execution_g10_retry_policy_v1.sql"
POLICY = ROOT / "gobernanza/contratos/pilot_srcr_unified_execution_retry_policy_v1.json"


@dataclass(frozen=True)
class RetryCase:
    outcome: str = "RETRYABLE_FAILURE"
    attempt_no: int = 1
    max_attempts: int = 3
    source_fence: int = 7
    current_fence: int = 8
    current_lease: bool = True
    backoff_elapsed: bool = True
    exact_policy_count: int = 1


def materializable(case: RetryCase) -> bool:
    return (
        case.outcome == "RETRYABLE_FAILURE"
        and case.attempt_no < case.max_attempts
        and case.current_lease
        and case.current_fence > case.source_fence
        and case.backoff_elapsed
        and case.exact_policy_count == 1
    )


class G10RetryAttemptPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.policy = json.loads(POLICY.read_text(encoding="utf-8"))

    def test_policy_is_explicit_candidate_not_hardcoded_in_rpc(self) -> None:
        self.assertEqual(self.policy["schema"], "LF_UNIFIED_EXECUTION_RETRY_POLICY_V1")
        self.assertEqual(self.policy["policy_role"], "RETRY_POLICY")
        self.assertEqual(self.policy["retryable_outcomes"], ["RETRYABLE_FAILURE"])
        self.assertEqual(self.policy["max_attempts"], 3)
        self.assertEqual(self.policy["backoff_seconds_by_retry"], [30, 120])
        self.assertTrue(self.policy["new_attempt_identity_required"])
        self.assertTrue(self.policy["new_fence_required"])
        authorize = self.sql[self.sql.index("create or replace function public.fn_lf_operation_authorize_retry_v1"):self.sql.index("create or replace function public.fn_lf_operation_advance_execution_v1")]
        self.assertIn("public.v_lf_operation_policy_snapshot", authorize)
        self.assertNotIn("v_max_attempts:=3", authorize)
        self.assertNotIn("30,120", authorize)

    def test_authorizer_accepts_only_exact_current_retryable_result(self) -> None:
        for token in (
            "retry_source_is_not_current_task",
            "stale_or_missing_lease_fence",
            "retry_result_fence_mismatch",
            "result_outcome_not_retryable",
            "retry_policy_resolution_not_exact",
            "retry_policy_schema_invalid",
            "retry_policy_outcome_not_allowed",
            "retry_attempts_exhausted",
        ):
            self.assertIn(token, self.sql)

    def test_retry_receipt_is_immutable_and_policy_bound(self) -> None:
        for token in (
            "create table if not exists public.lf_operation_retry_receipt",
            "operation_retry_receipt_immutable",
            "policy_code text not null",
            "policy_version text not null",
            "policy_sha text not null",
            "next_attempt_no=source_attempt_no+1",
        ):
            self.assertIn(token, self.sql)

    def test_g10_does_not_mutate_execution_task_or_fence(self) -> None:
        authorize = self.sql[self.sql.index("create or replace function public.fn_lf_operation_authorize_retry_v1"):self.sql.index("create or replace function public.fn_lf_operation_advance_execution_v1")]
        self.assertNotIn("update public.lf_operation_execution", authorize)
        self.assertNotIn("insert into public.lf_operation_execution_task", authorize)
        self.assertNotIn("set lease_fence", authorize)
        self.assertIn("next_task_materialization_owner", authorize)

    def test_g07_remains_sole_attempt_materializer(self) -> None:
        advance = self.sql[self.sql.index("create or replace function public.fn_lf_operation_advance_execution_v1"):]
        self.assertIn("insert into public.lf_operation_execution_task", advance)
        self.assertIn("v_next_attempt_no:=v_retry.next_attempt_no", advance)
        self.assertIn("v_next_task_id:=p_source_task_id", advance)
        self.assertIn("v_next_step_id:=p_source_step_id", advance)
        self.assertIn("retry_policy_receipt_required", advance)

    def test_retry_requires_new_fence_and_backoff(self) -> None:
        advance = self.sql[self.sql.index("create or replace function public.fn_lf_operation_advance_execution_v1"):]
        self.assertIn("v_exec.lease_fence<=v_result.lease_fence", advance)
        self.assertIn("retry_requires_new_current_lease_fence", advance)
        self.assertIn("retry_backoff_not_elapsed", advance)
        self.assertIn("materialized_lease_fence", advance)

    def test_failed_is_not_blindly_retried(self) -> None:
        self.assertIn("advance_outcome_non_retryable_failure", self.sql)
        self.assertNotIn('source_outcome text not null check (source_outcome in', self.sql)

    def test_behavior_positive(self) -> None:
        self.assertTrue(materializable(RetryCase()))

    def test_behavior_rejects_stale_fence(self) -> None:
        self.assertFalse(materializable(RetryCase(current_fence=7)))
        self.assertFalse(materializable(RetryCase(current_fence=6)))

    def test_behavior_rejects_exhausted_or_nonretryable(self) -> None:
        self.assertFalse(materializable(RetryCase(attempt_no=3)))
        self.assertFalse(materializable(RetryCase(outcome="FAILED")))
        self.assertFalse(materializable(RetryCase(outcome="BLOCKED")))

    def test_behavior_rejects_early_or_ambiguous_policy(self) -> None:
        self.assertFalse(materializable(RetryCase(backoff_elapsed=False)))
        self.assertFalse(materializable(RetryCase(exact_policy_count=0)))
        self.assertFalse(materializable(RetryCase(exact_policy_count=2)))


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G10_RETRY_ATTEMPT_POLICY_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
