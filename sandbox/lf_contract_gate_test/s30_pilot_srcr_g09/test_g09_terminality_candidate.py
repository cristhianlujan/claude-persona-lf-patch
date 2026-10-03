#!/usr/bin/env python3
from __future__ import annotations

import unittest
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261002064500_lf_pilot_srcr_unified_execution_g09_terminality_v1.sql"


@dataclass(frozen=True)
class TerminalCase:
    status: str = "IN_PROGRESS"
    lease_current: bool = True
    current_task_present: bool = False
    disposition: str = "NO_NEXT_TASK"
    source_outcome: str = "SUCCEEDED"
    pending_tasks: int = 0
    judge_required: int = 3
    judge_pass: int = 3
    judge_fail: int = 0
    judge_blocked: int = 0
    judge_result: str = "PASS"
    spec_current: bool = True


def terminalizable(case: TerminalCase) -> bool:
    return (
        case.status == "IN_PROGRESS"
        and case.lease_current
        and not case.current_task_present
        and case.disposition == "NO_NEXT_TASK"
        and case.source_outcome == "SUCCEEDED"
        and case.pending_tasks == 0
        and case.judge_required == case.judge_pass
        and case.judge_fail == 0
        and case.judge_blocked == 0
        and case.judge_result == "PASS"
        and case.spec_current
    )


class G09TerminalityCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_canonical_checklist_is_extended_not_replaced_by_parallel_judge(self) -> None:
        self.assertIn("create or replace view public.v_lf_operation_execution_checklist", self.lower)
        self.assertIn("public.lf_operation_task_result", self.lower)
        self.assertNotIn("create or replace view public.v_lf_operation_execution_judge", self.lower)
        self.assertIn("from public.v_lf_operation_execution_judge", self.lower)

    def test_legacy_step_evidence_keeps_priority_over_unified_fallback(self) -> None:
        self.assertIn("when es.execution_id is not null then coalesce(es.status,'missing')", self.lower)
        self.assertIn("left join lateral", self.lower)
        self.assertIn("ur on es.execution_id is null", self.lower)
        self.assertIn("when ur.outcome='succeeded' then coalesce(b.clean_result_value,'pass')", self.lower)
        self.assertIn("when ur.outcome='blocked' then coalesce(b.blocked_result_value,'blocked')", self.lower)
        self.assertIn("when ur.outcome in ('failed','retryable_failure') then 'fail'", self.lower)
        self.assertIn("order by r.attempt_no desc", self.lower)

    def test_finalizer_requires_fenced_no_next_task_success_and_current_spec(self) -> None:
        for token in (
            "stale_or_missing_lease_fence",
            "executable_current_task_remains",
            "terminality_requires_no_next_task",
            "terminality_requires_successful_final_result",
            "terminality_source_fence_mismatch",
            "frozen_operation_spec_digest_mismatch",
        ):
            self.assertIn(token, self.lower)

    def test_inv03_zero_pending_task_is_fail_closed(self) -> None:
        self.assertIn("left join public.lf_operation_task_result", self.lower)
        self.assertIn("r.execution_id is null", self.lower)
        self.assertIn("executable_pending_task_remains", self.lower)

    def test_canonical_judge_exact_clean_contract_is_required(self) -> None:
        self.assertIn("required_steps_pass is distinct from v_judge.required_steps", self.lower)
        self.assertIn("v_judge.fail_count<>0", self.lower)
        self.assertIn("v_judge.blocked_count<>0", self.lower)
        self.assertIn("v_judge.judge_result is distinct from 'pass'", self.lower)
        self.assertIn("canonical_operation_judge_not_clean", self.lower)

    def test_only_normal_completed_state_is_derived_by_g09(self) -> None:
        start = self.lower.index("create or replace function public.fn_lf_operation_finalize_execution_v1")
        body = self.lower[start:]
        self.assertIn("set status='completed'", body)
        self.assertNotIn("set status='blocked'", body)
        self.assertNotIn("set status='failed'", body)
        self.assertNotIn("set checkpoint_", body)
        self.assertNotIn("update public.lf_operation_execution_task", body)
        self.assertNotIn("update public.lf_operation_advance_receipt", body)

    def test_terminal_receipt_is_immutable_and_required_for_unified_completion(self) -> None:
        self.assertIn("operation_terminal_receipt_immutable", self.lower)
        self.assertIn("unified_execution_terminal_receipt_required", self.lower)
        self.assertIn("before update of status on public.lf_operation_execution", self.lower)
        self.assertIn("replay_accepted_terminality", self.lower)
        self.assertIn("terminal_state_without_g09_receipt", self.lower)

    def test_generic_boundary_contains_no_profile_or_runtime_specific_routing(self) -> None:
        start = self.lower.index("create or replace function public.fn_lf_operation_finalize_execution_v1")
        body = self.lower[start:]
        for forbidden in (
            "systemic_root_cause_repair",
            "perfil-systemic",
            "runtime deploy",
            "queue dispatch",
            "next_if_pass",
            "next_if_blocked",
        ):
            self.assertNotIn(forbidden, body)

    def test_behavior_model_positive(self) -> None:
        self.assertTrue(terminalizable(TerminalCase()))

    def test_behavior_model_blocks_remaining_task(self) -> None:
        self.assertFalse(terminalizable(TerminalCase(current_task_present=True)))
        self.assertFalse(terminalizable(TerminalCase(pending_tasks=1)))

    def test_behavior_model_blocks_nonterminal_disposition_or_retry_owned_outcome(self) -> None:
        self.assertFalse(terminalizable(TerminalCase(disposition="NEXT_TASK")))
        self.assertFalse(terminalizable(TerminalCase(disposition="EXTERNAL_HANDOFF")))
        self.assertFalse(terminalizable(TerminalCase(source_outcome="BLOCKED")))
        self.assertFalse(terminalizable(TerminalCase(source_outcome="RETRYABLE_FAILURE")))

    def test_behavior_model_blocks_stale_fence_spec_or_dirty_judge(self) -> None:
        self.assertFalse(terminalizable(TerminalCase(lease_current=False)))
        self.assertFalse(terminalizable(TerminalCase(spec_current=False)))
        self.assertFalse(terminalizable(TerminalCase(judge_pass=2)))
        self.assertFalse(terminalizable(TerminalCase(judge_fail=1, judge_result="FAIL")))
        self.assertFalse(terminalizable(TerminalCase(judge_blocked=1, judge_result="BLOCKED")))


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G09_TERMINALITY_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
