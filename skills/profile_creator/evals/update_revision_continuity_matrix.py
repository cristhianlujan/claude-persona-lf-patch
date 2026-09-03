#!/usr/bin/env python3
import json

A = "a" * 40
B = "b" * 40


def decide(case):
    baseline = case.get("baseline")
    current = case.get("current")
    bound = case.get("bound")
    if not isinstance(baseline, str) or len(baseline) != 40:
        return "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED"
    if not isinstance(current, str) or len(current) != 40:
        return "PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED"
    if not isinstance(bound, str) or len(bound) != 40:
        return "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED"
    if case.get("execution_bound") is not True:
        return "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED"
    stale = baseline != current
    if stale:
        if case.get("reread") is not True:
            return "PROFILE_UPDATE_STALE_REREAD_REQUIRED"
        if case.get("rebind") is not True:
            return "PROFILE_UPDATE_STALE_REBIND_REQUIRED"
        if case.get("rebound_from") != baseline:
            return "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH"
    if bound != current:
        return "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"
    return "STALE_REBOUND_CURRENT" if stale else "CURRENT_BOUND"


cases = [
    ("POS_MATCH", dict(baseline=A,current=A,bound=A,execution_bound=True), "CURRENT_BOUND"),
    ("POS_STALE_REREAD_REBIND", dict(baseline=A,current=B,bound=B,execution_bound=True,reread=True,rebind=True,rebound_from=A), "STALE_REBOUND_CURRENT"),
    ("NEG_MISSING_BASELINE", dict(current=A,bound=A,execution_bound=True), "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED"),
    ("NEG_EXECUTION_NOT_BOUND", dict(baseline=A,current=A,bound=A,execution_bound=False), "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED"),
    ("NEG_STALE_NO_REREAD", dict(baseline=A,current=B,bound=B,execution_bound=True,rebind=True,rebound_from=A), "PROFILE_UPDATE_STALE_REREAD_REQUIRED"),
    ("NEG_STALE_NO_REBIND", dict(baseline=A,current=B,bound=B,execution_bound=True,reread=True,rebound_from=A), "PROFILE_UPDATE_STALE_REBIND_REQUIRED"),
    ("NEG_REBOUND_FROM_WRONG_REV", dict(baseline=A,current=B,bound=B,execution_bound=True,reread=True,rebind=True,rebound_from=B), "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH"),
    ("NEG_BOUND_STALE", dict(baseline=A,current=B,bound=A,execution_bound=True,reread=True,rebind=True,rebound_from=A), "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
    ("NEG_CALLER_CURRENT_TRUE_CANNOT_OVERRIDE", dict(baseline=A,current=B,bound=A,execution_bound=True,reread=True,rebind=True,rebound_from=A,current_claim=True), "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
]
results=[]
for case_id,payload,expected in cases:
    observed=decide(payload)
    results.append({"id":case_id,"expected":expected,"observed":observed,"passed":observed==expected})
failed=[r["id"] for r in results if not r["passed"]]
print(json.dumps({"status":"PASS" if not failed else "FAIL","case_count":len(results),"passed":len(results)-len(failed),"failed":failed,"update_write_enabled":False,"results":results},indent=2))
raise SystemExit(1 if failed else 0)
