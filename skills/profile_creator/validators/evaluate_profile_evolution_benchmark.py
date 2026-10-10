#!/usr/bin/env python3
from __future__ import annotations
from typing import Any

def _benchmark_blockers(summary: dict[str,Any]) -> list[str]:
    blockers=[]
    n=summary.get("case_count")
    if not isinstance(n,int) or n<20: blockers.append("BENCHMARK_CORPUS_TOO_SMALL")
    if summary.get("primary_capability_score_direction")!="UP": blockers.append("PRIMARY_CAPABILITY_SCORE_NOT_UP")
    if summary.get("holdout_direction")!="UP": blockers.append("HOLDOUT_NOT_UP")
    if summary.get("critical_regressions")!=0: blockers.append("CRITICAL_REGRESSION")
    if summary.get("false_pass_not_worse") is not True: blockers.append("FALSE_PASS_NOT_PROTECTED")
    if summary.get("valid_behavior_preserved") is not True: blockers.append("VALID_BEHAVIOR_NOT_PRESERVED")
    if summary.get("cost_latency_within_budget") is not True: blockers.append("COST_LATENCY_BUDGET_FAIL")
    if summary.get("paired_interval_predefined") is not True: blockers.append("PAIRED_UNCERTAINTY_NOT_PREDEFINED")
    return blockers

def evaluate_benchmark(summary: dict[str,Any]) -> dict[str,Any]:
    blockers=_benchmark_blockers(summary)
    return {"schema":"PROFILE_EVOLUTION_BENCHMARK_RESULT_V2","benchmark_status":"BENCHMARK_PASS" if not blockers else "BLOCK_BENCHMARK",
            "blocking_codes":blockers,"benchmark_scope":summary.get("benchmark_scope"),"cutover_eligible":False}

def evaluate_cutover(summary: dict[str,Any]) -> dict[str,Any]:
    blockers=_benchmark_blockers(summary)
    if summary.get("benchmark_scope")!="FULL_PROFILE_EVOLUTION_BEHAVIOR": blockers.append("FULL_BEHAVIOR_BENCHMARK_REQUIRED")
    if summary.get("independent_assurance")!="PASS": blockers.append("INDEPENDENT_ASSURANCE_NOT_PASS")
    return {"schema":"PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V2","status":"ADMIT_CUTOVER" if not blockers else "BLOCK_CUTOVER",
            "blocking_codes":blockers,"optimizer_auto_admission":False}

def evaluate(summary: dict[str,Any]) -> dict[str,Any]:
    return evaluate_cutover(summary)

if __name__=="__main__":
    import json,sys
    data=json.load(open(sys.argv[1],encoding="utf-8"))
    mode=sys.argv[2] if len(sys.argv)>2 else "cutover"
    print(json.dumps(evaluate_benchmark(data) if mode=="benchmark" else evaluate_cutover(data),sort_keys=True))
