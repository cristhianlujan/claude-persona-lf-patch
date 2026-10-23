#!/usr/bin/env python3
"""M10.13 negative closure adversary over a declared read-only plan readback.

It finds a counterexample to a closure claim. A negative is not a valid signed
Super Admin closure receipt, and this script cannot transition checkpoints.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

TEST_CODE = "ENG_M10_13_NEG_FALSE_CLOSURE"
EXPECTED_M10 = frozenset(f"M10.{n}" for n in range(14))


def assess(snapshot: object) -> dict:
    if not isinstance(snapshot, dict):
        raise ValueError("SNAPSHOT_NOT_OBJECT")
    rows = snapshot.get("units")
    if not isinstance(rows, list):
        raise ValueError("PLAN_UNIT_READBACK_REQUIRED")
    if any(not isinstance(row, dict) for row in rows):
        raise ValueError("PLAN_UNIT_ROW_INVALID")
    units = [row.get("unit_code") for row in rows]
    if any(not isinstance(unit, str) for unit in units):
        raise ValueError("UNIT_CODE_INVALID")
    if len(units) != len(set(units)):
        raise ValueError("DUPLICATE_UNIT")
    unit_map = {row["unit_code"]: row for row in rows}
    missing = sorted(EXPECTED_M10.difference(unit_map))
    not_done = sorted(unit for unit in EXPECTED_M10.intersection(unit_map)
                      if unit_map[unit].get("status") != "DONE")
    malformed = sorted(unit for unit in EXPECTED_M10.intersection(unit_map)
                       if not isinstance(unit_map[unit].get("work_code"), str)
                       or not unit_map[unit]["work_code"].strip()
                       or type(unit_map[unit].get("cps")) is not int
                       or unit_map[unit]["cps"] < 1)
    receipt = snapshot.get("closure_receipt")
    stale_receipt = not isinstance(receipt, dict) or (
        receipt.get("source_sha256") != receipt.get("current_source_sha256")
        or not isinstance(receipt.get("source_sha256"), str)
        or len(receipt.get("source_sha256")) != 64
        or receipt.get("verification_status") != "VERIFIED"
    )
    reasons = []
    if missing: reasons.append("MISSING_M10_UNIT")
    if not_done: reasons.append("UNIT_NOT_DONE")
    if malformed: reasons.append("CHECKPOINT_COUNT_UNTRUSTED")
    if stale_receipt: reasons.append("CLOSURE_RECEIPT_UNVERIFIED_OR_STALE")
    return {
        "test_code": TEST_CODE,
        "verdict": "REJECT_FALSE_CLOSURE" if reasons else "NO_NEGATIVE_COUNTEREXAMPLE",
        "reasons": reasons, "missing": missing, "not_done": not_done,
        "malformed": malformed,
        "claimed_receipt_is_provider_attested": False,
        "independent_judge_pass": False,
        "checkpoint_done": False,
        "machine_assertion_recorded": False,
    }


def selftest() -> dict:
    canonical = {"units": [{"unit_code": unit, "work_code": f"PAULO-{i+100}",
                              "status": "DONE", "cps": 4}
                             for i, unit in enumerate(sorted(EXPECTED_M10))],
                 "closure_receipt": {"source_sha256": "a"*64,
                     "current_source_sha256": "a"*64,
                     "verification_status": "VERIFIED"}}
    assert assess(canonical)["verdict"] == "NO_NEGATIVE_COUNTEREXAMPLE"
    cases = (
        ("unit_not_done", lambda s: s["units"][0].update(status="IN_PROGRESS"), "UNIT_NOT_DONE"),
        ("unit_missing", lambda s: s["units"].pop(), "MISSING_M10_UNIT"),
        ("count_unknown", lambda s: s["units"][0].update(cps=None), "CHECKPOINT_COUNT_UNTRUSTED"),
        ("receipt_stale", lambda s: s["closure_receipt"].update(current_source_sha256="b"*64), "CLOSURE_RECEIPT_UNVERIFIED_OR_STALE"),
        ("receipt_missing", lambda s: s.pop("closure_receipt"), "CLOSURE_RECEIPT_UNVERIFIED_OR_STALE"),
    )
    for name, mutate, expected in cases:
        probe = json.loads(json.dumps(canonical))
        mutate(probe)
        result = assess(probe)
        assert result["verdict"] == "REJECT_FALSE_CLOSURE", name
        assert expected in result["reasons"], name
    duplicate = json.loads(json.dumps(canonical))
    duplicate["units"].append(duplicate["units"][0])
    try:
        assess(duplicate)
    except ValueError as exc:
        assert str(exc) == "DUPLICATE_UNIT"
    else:
        raise AssertionError("DUPLICATE_UNIT_FAIL_OPEN")
    return {"test_code": TEST_CODE, "status": "NEGATIVE_SELF_TEST_PASS",
            "cases_passed": 7, "checkpoint_done": False}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--snapshot", type=Path)
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(selftest(), sort_keys=True))
        return 0
    if not args.snapshot:
        print(json.dumps({"test_code": TEST_CODE, "verdict": "BLOCKED",
                          "reason": "READ_ONLY_SNAPSHOT_REQUIRED", "checkpoint_done": False}))
        return 2
    try:
        result = assess(json.loads(args.snapshot.read_text(encoding="utf-8")))
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "verdict": "FAIL_CLOSED",
                          "reason": str(exc), "checkpoint_done": False}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["verdict"] == "REJECT_FALSE_CLOSURE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
