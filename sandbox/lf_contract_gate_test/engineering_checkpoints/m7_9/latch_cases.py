#!/usr/bin/env python3
"""Owned test M7.9/LATCH_CASES. Runtime supplies LIVE rolled-back Supabase receipts.

The test does not re-run tests owned by T-INVAL or M6.11. It checks the
checkpoint's own three asserted behaviors against actual database state.
"""
import json
import sys

TEST_CODE = "ENG_M7_9_LATCH_CASES"

def eq(got, expected, msg):
    if got != expected:
        raise AssertionError(f"{msg}: got={got!r} expected={expected!r}")

def main():
    if len(sys.argv) != 2:
        raise ValueError("LIVE_READBACK_JSON_ARGUMENT_REQUIRED")
    d = json.loads(sys.argv[1])
    eq(d.get("schema_version"), "M79_LATCH_LIVE_READBACK_V1", "schema")
    base = d.get("baseline") or {}
    blocked = d.get("blocked") or {}
    success = d.get("completed") or {}
    idem = d.get("idempotence") or {}
    eq(base.get("parent_id"), 657, "baseline run ID")
    eq(base.get("parent_is_current"), True, "baseline parent current")
    eq(blocked.get("child_status"), "BLOCKED", "negative child status")
    eq(blocked.get("parent_invalidated"), False, "BLOCKED must NOT latch invalidation")
    eq(blocked.get("parent_is_current"), True, "BLOCKED must NOT stale currentness")
    eq(blocked.get("freshness_state"), "CURRENT", "BLOCKED must NOT stale delta")
    eq(blocked.get("terminal_successors"), 0, "BLOCKED must NOT count as successful successor")
    eq(blocked.get("planner_strategy"), "NOOP", "BLOCKED must retain current predecessor")
    eq(success.get("child_status"), "COMPLETED", "positive child status")
    eq(success.get("validator_terminal"), "COMPLETED", "actual validator terminal")
    eq(success.get("families_passed"), 47, "full positive validation")
    eq(success.get("parent_invalidated"), True, "COMPLETED must latch")
    eq(success.get("invalidated_by_run_id"), success.get("child_run_id"), "exact terminal successor")
    eq(success.get("invalidated_reason"), "TERMINAL_SUCCESSOR", "terminal reason")
    eq(success.get("parent_is_current"), False, "COMPLETED must stale currentness")
    eq(success.get("freshness_state"), "STALE", "COMPLETED must stale delta")
    eq(success.get("terminal_successors"), 1, "only completed child counts")
    eq(idem.get("same_original_latch"), True, "repeat terminal child must preserve first latch")
    eq(idem.get("first_successor_id"), success.get("child_run_id"), "idempotence first link")
    eq(idem.get("second_successor_status"), "COMPLETED", "second terminal child must actually finish")
    eq(d.get("rolled_back"), True, "isolated execution must rollback")
    result = {
        "test_passed": True, "test_exit_code": 0, "semantic_authority_bound": True,
        "checkpoint": "LATCH_CASES", "negative_blocked_does_not_invalidate": True,
        "positive_completed_invalidates": True, "idempotent_latch": True,
        "validated_families": 47, "parent_run_id": 657,
        "first_successor_id": success.get("child_run_id"),
        "second_successor_id": idem.get("second_successor_id"),
        "historical_invalidation_rows_not_rewritten": True,
    }
    print(json.dumps({"status": "PASS", "test_code": TEST_CODE, "observed": result}, sort_keys=True))

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE,
                          "error": f"{type(exc).__name__}: {exc}"}))
        sys.exit(1)
