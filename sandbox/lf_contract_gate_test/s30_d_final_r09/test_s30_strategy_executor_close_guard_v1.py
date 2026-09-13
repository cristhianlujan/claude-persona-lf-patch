from __future__ import annotations

from s30_strategy_executor_close_guard_v1 import (
    BLOCK_CLOSE_GUARD,
    CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE,
    FINAL_REPORT_ALLOWED,
    PASS_CLOSE_GUARD,
    REPAIR_CLOSE_EVIDENCE,
    evaluate_strategy_close_guard,
)


def base() -> dict:
    return {
        "global_remaining_work_scan": "PASS",
        "safe_work_remaining_count": 0,
        "next_safe_batch": "NONE",
        "safe_parallel_work": [],
        "blockers": [],
        "why_run_stopped": "NO_SAFE_WORK_REMAINING",
    }


def main() -> int:
    r = evaluate_strategy_close_guard(base())
    assert r.can_close and r.gate_result == PASS_CLOSE_GUARD, r
    assert r.required_action == FINAL_REPORT_ALLOWED, r

    x = base()
    x["safe_work_remaining_count"] = 1
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE, r
    assert "SAFE_WORK_REMAINING_NONZERO" in r.reasons, r

    x = base()
    x["next_safe_batch"] = "S31-C"
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE, r
    assert "NEXT_SAFE_BATCH_PRESENT" in r.reasons, r

    x = base()
    x["safe_parallel_work"] = ["S31-B", "S31-C"]
    x["blockers"] = [{"code": "BLOCK_S31_A", "independent_safe_work": ["S31-B"]}]
    x["why_run_stopped"] = "NONDELEGABLE_AUTHORITY_ONLY"
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE, r
    assert "SAFE_PARALLEL_WORK_PRESENT" in r.reasons, r

    x = base()
    x["blockers"] = [{"code": "BLOCK_S31_A", "independent_safe_work": ["S31-C"]}]
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE, r
    assert "BLOCKER_INDEPENDENT_SAFE_WORK_PRESENT" in r.reasons, r

    x = base()
    x["global_remaining_work_scan"] = "UNKNOWN"
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == REPAIR_CLOSE_EVIDENCE, r
    assert "GLOBAL_REMAINING_WORK_SCAN_NOT_PASS" in r.reasons, r

    x = base()
    x["safe_work_remaining_count"] = None
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == REPAIR_CLOSE_EVIDENCE, r
    assert "SAFE_WORK_REMAINING_INVALID" in r.reasons, r

    x = base()
    x["why_run_stopped"] = "WAITING"
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == REPAIR_CLOSE_EVIDENCE, r
    assert "STOP_REASON_NOT_ALLOWED" in r.reasons, r

    x = base()
    x["why_run_stopped"] = "EXECUTION_LIMIT_REACHED"
    r = evaluate_strategy_close_guard(x)
    assert not r.can_close and r.gate_result == BLOCK_CLOSE_GUARD, r
    assert r.required_action == REPAIR_CLOSE_EVIDENCE, r
    assert "EXECUTION_LIMIT_EVIDENCE_MISSING" in r.reasons, r

    x["execution_limit_evidence"] = "literal engine stop"
    r = evaluate_strategy_close_guard(x)
    assert r.can_close and r.gate_result == PASS_CLOSE_GUARD, r
    assert r.required_action == FINAL_REPORT_ALLOWED, r

    x = base()
    x["why_run_stopped"] = "NONDELEGABLE_AUTHORITY_ONLY"
    r = evaluate_strategy_close_guard(x)
    assert r.can_close and r.gate_result == PASS_CLOSE_GUARD, r
    assert r.required_action == FINAL_REPORT_ALLOWED, r

    print("S30_STRATEGY_EXECUTOR_CLOSE_GUARD_V1_TESTS_PASS 11/11")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
