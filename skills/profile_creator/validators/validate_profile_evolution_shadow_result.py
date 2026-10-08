#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def evaluate(result: dict[str, Any], targets: dict[str, Any]) -> dict[str, Any]:
    blockers: list[str] = []
    expected = [x.get("profile_slug") for x in targets.get("targets", []) if isinstance(x, dict)]
    rows = result.get("rows") if isinstance(result, dict) else None

    if result.get("schema") != "PROFILE_EVOLUTION_SHADOW_RESULT_V1":
        blockers.append("SHADOW_SCHEMA_INVALID")
    if not isinstance(rows, list):
        blockers.append("SHADOW_ROWS_INVALID")
        rows = []
    if result.get("writes") != 0:
        blockers.append("SHADOW_WRITE_DETECTED")
    if result.get("target_count") != len(expected) or len(rows) != len(expected):
        blockers.append("SHADOW_TARGET_COUNT_MISMATCH")

    actual = [x.get("profile_slug") for x in rows if isinstance(x, dict)]
    if sorted(actual) != sorted(expected) or len(set(actual)) != len(actual):
        blockers.append("SHADOW_TARGET_SET_MISMATCH")

    for row in rows:
        if not isinstance(row, dict):
            blockers.append("SHADOW_ROW_INVALID")
            continue
        if row.get("capability_evidence_state") != "UNPROVEN_UNTIL_DOMAIN_TASK_BENCHMARK":
            blockers.append("SHADOW_CAPABILITY_EVIDENCE_STATE_INVALID")
            continue
        if row.get("s26_decision") == "NO_UPDATE_REQUIRED":
            if row.get("assessment_status") != "NEEDS_MORE_EVIDENCE":
                blockers.append("SHADOW_UNKNOWN_EVIDENCE_NOT_FAIL_CLOSED")
            if row.get("maturity") != "UNDETERMINED":
                blockers.append("SHADOW_UNPROVEN_MATURITY_CLAIM")
            if row.get("evolution_mode") is not None:
                blockers.append("SHADOW_UNPROVEN_EVOLUTION_MODE_CLAIM")
        if row.get("maturity") == "GENERIC" and row.get("evolution_mode") == "SPECIALIZE":
            blockers.append("SHADOW_GENERIC_INFERRED_FROM_UNKNOWN")

    return {
        "schema": "PROFILE_EVOLUTION_SHADOW_VALIDATION_V1",
        "status": "PASS" if not blockers else "FAIL",
        "blocking_codes": sorted(set(blockers)),
        "target_count": len(rows),
        "writes": result.get("writes"),
    }


def self_test() -> None:
    targets = {"targets": [{"profile_slug": "a"}, {"profile_slug": "b"}]}
    good = {
        "schema": "PROFILE_EVOLUTION_SHADOW_RESULT_V1",
        "target_count": 2,
        "writes": 0,
        "rows": [
            {
                "profile_slug": "a",
                "s26_decision": "NO_UPDATE_REQUIRED",
                "assessment_status": "NEEDS_MORE_EVIDENCE",
                "maturity": "UNDETERMINED",
                "evolution_mode": None,
                "capability_evidence_state": "UNPROVEN_UNTIL_DOMAIN_TASK_BENCHMARK",
            },
            {
                "profile_slug": "b",
                "s26_decision": "UPDATE_REQUIRED",
                "assessment_status": "EVIDENCE_SUFFICIENT",
                "maturity": "UNDETERMINED",
                "evolution_mode": "PATCH",
                "capability_evidence_state": "UNPROVEN_UNTIL_DOMAIN_TASK_BENCHMARK",
            },
        ],
    }
    assert evaluate(good, targets)["status"] == "PASS"
    bad = json.loads(json.dumps(good))
    bad["rows"][0]["maturity"] = "GENERIC"
    bad["rows"][0]["evolution_mode"] = "SPECIALIZE"
    assert evaluate(bad, targets)["status"] == "FAIL"
    bad = json.loads(json.dumps(good))
    bad["writes"] = 1
    assert evaluate(bad, targets)["status"] == "FAIL"
    print("PASS_PROFILE_EVOLUTION_SHADOW_VALIDATOR positive=1 negative=2")


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return 0
    if len(sys.argv) != 3:
        print("usage: validate_profile_evolution_shadow_result.py <result.json> <targets.json>", file=sys.stderr)
        return 2
    result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    targets = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    verdict = evaluate(result, targets)
    print(json.dumps(verdict, indent=2, sort_keys=True))
    return 0 if verdict["status"] == "PASS" else 3


if __name__ == "__main__":
    raise SystemExit(main())
