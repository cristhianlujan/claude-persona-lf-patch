#!/usr/bin/env python3
"""Exploratory D1/D2/D3 matched-case score. D2 uses advisory selection label.

Not a preregistered blind three-way comparison: D2 ran after D1/D3 on
previously exposed cases and did not execute the selector or methods.
"""
from __future__ import annotations
import hashlib,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"skills/profile_creator/evals/results"
CASES=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
BASELINE=BASE/"pe_causal_remaining_holdout_model_raw_v1.json"
D2=ROOT/"pe_causal_d2_selector_model_raw_v1.json"
OUTPUT=BASE/"pe_causal_three_arm_retrospective_diagnostic_v1.json"

def digest(x):
    return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,
        separators=(",",":"),allow_nan=False).encode()).hexdigest()
def check(case):
    observations={}
    for obs in case["observations"]:
        source={"case_id":case["case_id"],"probe_id":obs["probe_id"],
                "observed":obs["observed"],"source":"fixture-primary-readback"}
        if obs["evidence_ref"]=="fixture-verified://"+digest(source):
            observations[obs["probe_id"]]=obs["observed"]
    falsified=[]
    survivors=[]
    missing=False
    for h in case["hypotheses"]:
        counter=any(p in observations and observations[p]!=v
           for p,v in h["predictions"].items())
        if counter:falsified.append(h["id"])
        else:
            survivors.append(h["id"])
            missing=missing or any(p not in observations for p in h["predictions"])
    action=("COLLECT_MORE_EVIDENCE" if len(survivors)!=1 or missing
            else "INVESTIGATE_"+survivors[0])
    return action,sorted(falsified)

def main():
    assert not OUTPUT.exists()
    cases=json.loads(CASES.read_text())["cases"]
    old=json.loads(BASELINE.read_text());d2=json.loads(D2.read_text())
    assert old["raw_frozen"] and d2["raw_frozen"]
    assert len(old["batches"])==4 and len(d2["batches"])==2
    records=[]
    arms={}
    for data in (old,d2):
        for b in data["batches"]:
            assert b["runtime_attestation"]["verified"]
            stats=arms.setdefault(b["arm"],{"cases":0,"correct":0,
                  "prompt_tokens":0,"completion_tokens":0,"wall_ms":0.0,
                  "batch_count":0})
            stats["prompt_tokens"]+=b["usage"]["prompt_tokens"]
            stats["completion_tokens"]+=b["usage"]["completion_tokens"]
            stats["wall_ms"]+=b["wall_ms"]
            stats["batch_count"]+=1
            for a in b["answers"]:
                case=next(c for c in cases if c["case_id"]==a["case_id"])
                decision,falsified=check(case)
                good=(a["decision"]==decision and sorted(a["falsified"])==falsified
                      and a["causality_proven"] is False)
                stats["cases"]+=1
                stats["correct"]+=int(good)
                records.append({"case_id":a["case_id"],"arm":b["arm"],
                   "correct":good,"expected_decision":decision,
                   "expected_falsified":falsified})
    assert all(v["cases"]==4 for v in arms.values()) and len(arms)==3
    for a in arms.values():
        a["total_tokens"]=a["prompt_tokens"]+a["completion_tokens"]
        a["wall_ms"]=round(a["wall_ms"],2)
    result={"schema":"PE_CAUSAL_RETROSPECTIVE_TRIARM_DIAGNOSTIC_V1",
      "status":"RETROSPECTIVE_NOT_BLIND_N4",
      "baseline_raw_sha256":hashlib.sha256(BASELINE.read_bytes()).hexdigest(),
      "d2_raw_sha256":hashlib.sha256(D2.read_bytes()).hexdigest(),
      "case_source_sha256":hashlib.sha256(CASES.read_bytes()).hexdigest(),
      "arms":arms,"records":records,
      "method_selection_d2":"SIMULATED_ADVISORY_LABEL_NO_REAL_SELECTOR_INVOCATION",
      "method_execution_d2":False,
      "statistical_or_causal_uplift":"NOT_ESTABLISHED",
      "context_token_budget_matched":False,
      "independent_semantic_assurance":"NOT_EXECUTED",
      "cutover_eligible":False}
    OUTPUT.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"arms":arms,
     "raw_sha256":hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
     "status":result["status"]},sort_keys=True))

if __name__=="__main__":main()
