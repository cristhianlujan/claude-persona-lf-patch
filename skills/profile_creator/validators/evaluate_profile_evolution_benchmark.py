#!/usr/bin/env python3
from __future__ import annotations

from typing import Any


def evaluate(summary: dict[str, Any]) -> dict[str, Any]:
    blockers: list[str] = []
    n = summary.get("case_count")
    if not isinstance(n, int) or n < 20:
        blockers.append("BENCHMARK_CORPUS_TOO_SMALL")
    if summary.get("primary_capability_score_direction") != "UP":
        blockers.append("PRIMARY_CAPABILITY_SCORE_NOT_UP")
    if summary.get("holdout_direction") != "UP":
        blockers.append("HOLDOUT_NOT_UP")
    if summary.get("critical_regressions") != 0:
        blockers.append("CRITICAL_REGRESSION")
    if summary.get("false_pass_not_worse") is not True:
        blockers.append("FALSE_PASS_NOT_PROTECTED")
    if summary.get("valid_behavior_preserved") is not True:
        blockers.append("VALID_BEHAVIOR_NOT_PRESERVED")
    if summary.get("cost_latency_within_budget") is not True:
        blockers.append("COST_LATENCY_BUDGET_FAIL")
    if summary.get("independent_assurance") != "PASS":
        blockers.append("INDEPENDENT_ASSURANCE_NOT_PASS")
    if summary.get("paired_interval_predefined") is not True:
        blockers.append("PAIRED_UNCERTAINTY_NOT_PREDEFINED")
    return {
        "schema": "PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1",
        "status": "ADMIT_CUTOVER" if not blockers else "BLOCK_CUTOVER",
        "blocking_codes": blockers,
        "optimizer_auto_admission": False,
    }


if __name__ == "__main__":
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print(json.dumps(evaluate(data), sort_keys=True))
