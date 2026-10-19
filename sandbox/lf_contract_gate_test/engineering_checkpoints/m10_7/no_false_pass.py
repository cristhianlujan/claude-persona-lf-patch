#!/usr/bin/env python3
"""M10.7 CP3 fail-closed evidence diagnostic, NOT a checkpoint closer.

Accepts a supplied read-only SQL readback. Never issues an assertion receipt,
declares production readiness, or treats a self-test fixture as live proof.
"""
import argparse
import copy
import json

TEST_CODE = "ENG_M10_7_NO_FALSE_PASS"
COHORT = {1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58}
LIMIT_MS = 150000
RECEIPT_SHA = "17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972"

def adjudicate(data):
    r, rows, window = data["receipt"], data["runs"], data.get("window", {})
    if not (r.get("id") == 38 and r.get("receipt_sha256") == RECEIPT_SHA
            and r.get("schema_version") == "SOAK_OBSERVATION_HISTORY_V2"
            and r.get("verification_status") == "VERIFIED"
            and r.get("pass") is True and r.get("screens_total") == 13
            and r.get("families_total") == 47
            and r.get("screens_below_2") == 0
            and r.get("families_below_2") == 0):
        raise ValueError("CANONICAL_RECEIPT_UNVERIFIED")
    if not isinstance(rows, list) or not rows:
        raise ValueError("NO_OBSERVATIONS")
    seen, over, unknown, timeouts, incomplete = set(), [], [], [], []
    for row in rows:
        run, screen, ms = row.get("id"), row.get("pantalla_id"), row.get("validator_duration_ms")
        if type(run) is not int or run in seen or screen not in COHORT:
            raise ValueError("DUPLICATE_ID_OR_INVALID_COHORT")
        seen.add(run)
        reason = str(row.get("blocked_reason") or "").lower()
        if (row.get("status") == "TIMED_OUT" or row.get("explicit_timeout") is True
                or "timeout" in reason or "57014" in reason):
            timeouts.append(run)
        if row.get("status") != "COMPLETED":
            incomplete.append(run)
        if type(ms) is not int or ms <= 0:
            unknown.append(run)
        elif ms > LIMIT_MS:
            over.append({"run_id": run, "duration_ms": ms})
    if type(r.get("known_false_pass_signals")) is not int or type(r.get("unresolved_d4")) is not int:
        raise ValueError("UNKNOWN_FALSE_PASS_OR_D4")
    frozen = (window.get("status") == "FROZEN_VERIFIED"
              and bool(window.get("start")) and bool(window.get("end"))
              and bool(window.get("source_ref")))
    reasons = []
    if over: reasons.append("OVER_150S_BUDGET")
    if unknown: reasons.append("UNKNOWN_DURATION")
    if timeouts: reasons.append("EXPLICIT_TIMEOUT")
    if incomplete: reasons.append("NOT_COMPLETED")
    if r["known_false_pass_signals"] != 0: reasons.append("KNOWN_FALSE_PASS")
    if r["unresolved_d4"] != 0: reasons.append("UNRESOLVED_D4")
    if not frozen: reasons.append("NO_FROZEN_WINDOW")
    return {"test_code": TEST_CODE, "verdict": "FAIL_CLOSED" if reasons else "ELIGIBLE_FOR_MATERIAL_REVIEW",
            "reasons": reasons, "over_budget": over, "unknown_duration_ids": unknown,
            "explicit_timeout_ids": timeouts, "incomplete_ids": incomplete,
            "observed_count": len(rows), "checkpoint_done": False,
            "machine_assertion_recorded": False}

def selftest():
    receipt = {"id": 38, "receipt_sha256": RECEIPT_SHA, "schema_version": "SOAK_OBSERVATION_HISTORY_V2",
               "verification_status": "VERIFIED", "pass": True, "screens_total": 13,
               "families_total": 47, "screens_below_2": 0, "families_below_2": 0,
               "known_false_pass_signals": 0, "unresolved_d4": 0}
    clean = {"receipt": receipt, "window": {"status": "FROZEN_VERIFIED", "start": "A",
             "end": "B", "source_ref": "SELFTEST_ONLY"}, "runs": [{"id": 931,
             "pantalla_id": 1, "status": "COMPLETED", "validator_duration_ms": 120015}]}
    assert adjudicate(clean)["verdict"] == "ELIGIBLE_FOR_MATERIAL_REVIEW"
    cases = [
        ("OVER_150S_BUDGET", "runs", "validator_duration_ms", 180105),
        ("UNKNOWN_DURATION", "runs", "validator_duration_ms", 0),
        ("EXPLICIT_TIMEOUT", "runs", "explicit_timeout", True),
        ("KNOWN_FALSE_PASS", "receipt", "known_false_pass_signals", 1),
        ("UNRESOLVED_D4", "receipt", "unresolved_d4", 1),
        ("NO_FROZEN_WINDOW", "window", "status", "NOT_FROZEN")]
    for fail, target, key, value in cases:
        mutated = copy.deepcopy(clean)
        slot = mutated[target][0] if target == "runs" else mutated[target]
        slot[key] = value
        assert fail in adjudicate(mutated)["reasons"], fail
    return {"test_code": TEST_CODE, "status": "PASS_LOGIC_SELF_TEST_ONLY",
            "cases_passed": 7, "checkpoint_done": False}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--snapshot")
    args = ap.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return 0
    if not args.snapshot:
        ap.error("--snapshot from RO SQL required; self-test is not material evidence")
    try:
        with open(args.snapshot, encoding="utf-8") as fh:
            result = adjudicate(json.load(fh))
    except (ValueError, TypeError, KeyError, OSError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "verdict": "FAIL_CLOSED",
                          "reason": str(exc), "checkpoint_done": False}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 2 if result["verdict"] == "FAIL_CLOSED" else 0

if __name__ == "__main__":
    raise SystemExit(main())
