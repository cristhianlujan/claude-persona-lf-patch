#!/usr/bin/env python3
from __future__ import annotations
import json,random,sys
from pathlib import Path
from typing import Any

ARMS=("A_ORIGINAL","B_UPDATER_V01","C_EVOLUTION_CURRENT","D_EVOLUTION_TARGET")

def _num(v: Any) -> bool:
    return isinstance(v,(int,float)) and not isinstance(v,bool)

def _bootstrap(values:list[float],seed:int,n:int=10000)->list[float]:
    if not values:
        return [0.0,0.0]
    rng=random.Random(seed); means=[]
    for _ in range(n):
        means.append(sum(rng.choice(values) for _ in values)/len(values))
    means.sort()
    return [round(means[int(.025*(n-1))],6),round(means[int(.975*(n-1))],6)]

def _validate_arm(a:Any)->list[str]:
    if not isinstance(a,dict): return ["ARM_MISSING"]
    req=("profile_revision","execution_receipt_ref","execution_receipt_sha256","producer_execution_id",
         "evaluator_receipt_ref","evaluator_verification_state","evaluator_execution_id","blind_arm","score")
    missing=[k for k in req if a.get(k) in (None,"")]
    out=[f"ARM_FIELD_MISSING:{k}" for k in missing]
    if a.get("evaluator_verification_state")!="VERIFIED": out.append("EVALUATOR_NOT_VERIFIED")
    if a.get("producer_execution_id")==a.get("evaluator_execution_id"): out.append("EVALUATOR_NOT_INDEPENDENT")
    if a.get("blind_arm") is not True: out.append("EVALUATOR_NOT_BLIND")
    if not _num(a.get("score")) or not 0<=float(a.get("score",0))<=1: out.append("SCORE_INVALID")
    sha=a.get("execution_receipt_sha256")
    if not isinstance(sha,str) or len(sha)!=64 or any(c not in "0123456789abcdef" for c in sha): out.append("EXECUTION_RECEIPT_SHA_INVALID")
    return out

def _w(case:dict[str,Any])->float:
    d=float(case.get("difficulty",1))
    return d*(2.0 if case.get("critical") is True else 1.0)

def _weighted(cases:list[dict[str,Any]],arm:str)->float:
    ws=[_w(c) for c in cases]
    return sum(float(c["arms"][arm]["score"])*w for c,w in zip(cases,ws))/sum(ws)

def _max_difficulty(cases:list[dict[str,Any]],arm:str,threshold:float=.8)->int:
    out=0
    for d in range(1,6):
        xs=[float(c["arms"][arm]["score"]) for c in cases if int(c["difficulty"])==d]
        if xs and sum(xs)/len(xs)>=threshold: out=d
    return out

def evaluate(raw:dict[str,Any],holdout:dict[str,Any],protocol:dict[str,Any])->dict[str,Any]:
    blockers=[]
    if raw.get("benchmark_scope")!="EXPERT_TASK_PERFORMANCE_E2E": blockers.append("BENCHMARK_SCOPE_INVALID")
    if raw.get("raw_frozen") is not True: blockers.append("RAW_NOT_FROZEN")
    if raw.get("thresholds_frozen_before_raw") is not True: blockers.append("THRESHOLDS_NOT_FROZEN")
    plan=raw.get("sample_size_plan",{})
    planned=plan.get("planned_case_count")
    cases=raw.get("cases")
    if not isinstance(cases,list): cases=[]; blockers.append("CASES_INVALID")
    if not isinstance(planned,int) or planned<1 or len(cases)<planned: blockers.append("SAMPLE_SIZE_PLAN_NOT_MET")
    if not plan.get("power_analysis_ref"): blockers.append("POWER_ANALYSIS_REF_MISSING")
    holdout_ids=set(holdout.get("holdout_case_ids",[])) if isinstance(holdout,dict) else set()
    if not holdout_ids or not holdout_ids <= {c.get("case_id") for c in cases}: blockers.append("HOLDOUT_MANIFEST_INVALID")

    for c in cases:
        if not isinstance(c,dict):
            blockers.append("CASE_INVALID"); continue
        for k in ("case_id","domain_family","difficulty","critical","preservation_case","adaptation_case","transfer_case","arms"):
            if k not in c: blockers.append(f"{c.get('case_id','?')}:CASE_FIELD_MISSING:{k}")
        if not _num(c.get("difficulty")) or not 1<=float(c.get("difficulty",0))<=5:
            blockers.append(f"{c.get('case_id','?')}:DIFFICULTY_INVALID")
        arms=c.get("arms",{})
        for arm in ARMS:
            for b in _validate_arm(arms.get(arm) if isinstance(arms,dict) else None):
                blockers.append(f"{c.get('case_id','?')}:{arm}:{b}")

    if blockers:
        return {"schema":"PROFILE_EXPERT_BEHAVIOR_SCORE_V1","status":"BLOCK","blocking_codes":sorted(set(blockers)),"cutover_eligible":False}

    A=_weighted(cases,"A_ORIGINAL"); B=_weighted(cases,"B_UPDATER_V01"); C=_weighted(cases,"C_EVOLUTION_CURRENT"); D=_weighted(cases,"D_EVOLUTION_TARGET")
    dA=[float(c["arms"]["D_EVOLUTION_TARGET"]["score"])-float(c["arms"]["A_ORIGINAL"]["score"]) for c in cases]
    dC=[float(c["arms"]["D_EVOLUTION_TARGET"]["score"])-float(c["arms"]["C_EVOLUTION_CURRENT"]["score"]) for c in cases]
    h=[c for c in cases if c["case_id"] in holdout_ids]
    hdA=[float(c["arms"]["D_EVOLUTION_TARGET"]["score"])-float(c["arms"]["A_ORIGINAL"]["score"]) for c in h]
    hdC=[float(c["arms"]["D_EVOLUTION_TARGET"]["score"])-float(c["arms"]["C_EVOLUTION_CURRENT"]["score"]) for c in h]
    ciA=_bootstrap(dA,20261010); ciC=_bootstrap(dC,20261011); hciA=_bootstrap(hdA,20261012); hciC=_bootstrap(hdC,20261013)
    relative=(D-A)/max(A,1e-9)

    critical_reg=sum(1 for c in cases if c.get("critical") is True and float(c["arms"]["D_EVOLUTION_TARGET"]["score"]) < float(c["arms"]["A_ORIGINAL"]["score"]))
    pres=[c for c in cases if c.get("preservation_case") is True]
    preservation_ratio=(sum(1 for c in pres if float(c["arms"]["D_EVOLUTION_TARGET"]["score"]) >= float(c["arms"]["A_ORIGINAL"]["score"])-.02)/len(pres)) if pres else 0.0

    adaptation=[c for c in cases if c.get("adaptation_case") is True]
    transfer=[c for c in cases if c.get("transfer_case") is True]
    adapD=sum(float(c["arms"]["D_EVOLUTION_TARGET"]["score"]) for c in adaptation)/len(adaptation) if adaptation else None
    transferD=sum(float(c["arms"]["D_EVOLUTION_TARGET"]["score"]) for c in transfer)/len(transfer) if transfer else None

    t=protocol["admission_thresholds"]
    resource=raw.get("resource_metrics",{})
    resource_ok=(resource.get("cost_budget_pass") is True and resource.get("latency_observed") is True and resource.get("token_estimated") is False)

    gates={
      "relative_uplift_D_vs_A":relative>=t["relative_uplift_D_vs_A_min"],
      "paired_ci_D_vs_A":ciA[0]>t["paired_ci_lower_D_vs_A_gt"],
      "paired_ci_D_vs_C":ciC[0]>t["paired_ci_lower_D_vs_C_gt"],
      "holdout_ci_D_vs_A":hciA[0]>t["holdout_ci_lower_D_vs_A_gt"],
      "holdout_ci_D_vs_C":hciC[0]>t["holdout_ci_lower_D_vs_C_gt"],
      "critical_regressions":critical_reg<=t["critical_regressions_max"],
      "preservation":preservation_ratio>=t["preservation_ratio_min"],
      "resource_budget":resource_ok,
    }
    return {
      "schema":"PROFILE_EXPERT_BEHAVIOR_SCORE_V1",
      "status":"BENCHMARK_PASS" if all(gates.values()) else "BENCHMARK_FAIL",
      "blocking_codes":[k for k,v in gates.items() if not v],
      "benchmark_scope":"EXPERT_TASK_PERFORMANCE_E2E",
      "case_count":len(cases),"holdout_case_count":len(h),
      "arm_scores":{"A_ORIGINAL":round(A,6),"B_UPDATER_V01":round(B,6),"C_EVOLUTION_CURRENT":round(C,6),"D_EVOLUTION_TARGET":round(D,6)},
      "relative_uplift_D_vs_A":round(relative,6),
      "paired_delta_ci95_D_vs_A":ciA,"paired_delta_ci95_D_vs_C":ciC,
      "holdout_delta_ci95_D_vs_A":hciA,"holdout_delta_ci95_D_vs_C":hciC,
      "critical_regressions":critical_reg,"preservation_ratio":round(preservation_ratio,6),
      "max_difficulty_solved":{arm:_max_difficulty(cases,arm) for arm in ARMS},
      "adaptation_score_D":adapD,"transfer_score_D":transferD,
      "resource_budget_pass":resource_ok,
      "independent_assurance":"NOT_EXECUTED",
      "cutover_eligible":False,
    }

if __name__=="__main__":
    raw=json.load(open(sys.argv[1],encoding="utf-8"))
    hold=json.load(open(sys.argv[2],encoding="utf-8"))
    protocol=json.load(open(sys.argv[3],encoding="utf-8"))
    print(json.dumps(evaluate(raw,hold,protocol),sort_keys=True))
