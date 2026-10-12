#!/usr/bin/env python3
"""Deterministic synthetic controls only; never attest real GPT model execution."""
from copy import deepcopy
from score_profile_expert_asis_tobe_gap_v1 import evaluate, digest

ARMS=("A_ORIGINAL","B_UPDATER_V01","C_EVOLUTION_CURRENT","D_EVOLUTION_TARGET")
def fixture():
    target={"schema":"PE10E_FROZEN_EXPERT_TARGET_V1","source_commit":"git://frozen-immutable","target_standard_ref":"standard://independent",
            "frozen_before_raw":True,"frozen_at":"2026-10-10T00:00:00Z",
            "domain_targets":{x:{"quality_min":0.8,"minimum_open_cases":2,"rubric_ref":f"rubric://{x}","standard_ref":f"expert://{x}"} for x in ("ENGINEERING","CAUSAL_REASONING")}}
    cases=[]
    for i,domain in enumerate(("ENGINEERING","ENGINEERING","CAUSAL_REASONING","CAUSAL_REASONING")):
        cases.append({"case_id":f"F-{i}","domain_family":domain,"task_type":"OPEN_TASK","difficulty":3,"critical":False,
                      "arms":{arm:{"score":value} for arm,value in zip(ARMS,(.5,.55,.6,.88))}})
    raw={"benchmark_scope":"EXPERT_TASK_PERFORMANCE_E2E","raw_frozen":True,"raw_started_at":"2026-10-11T00:00:00Z",
         "target_contract_sha256":digest(target),"cases":cases}
    upstream={"schema":"PROFILE_EXPERT_BEHAVIOR_SCORE_V1","status":"BENCHMARK_PASS","blocking_codes":[],
              "cutover_eligible":False,"case_count":4,
              "arm_scores":dict(zip(ARMS,(.5,.55,.6,.88)))}
    return raw,target,upstream

def test():
    raw,target,upstream=fixture()
    x=evaluate(raw,target,upstream)
    assert x["status"]=="TARGET_PASS" and x["total_domains"]==2 and x["target_met_domains"]==2
    assert all(v["gap_initial"]==0.2 and v["gap_residual"]==0 for v in x["domain_results"])
    assert x["benchmark_admitted"] is False and x["cutover_eligible"] is False
    print("PASS positive: paired C/D task evidence reaches frozen target without granting cutover")
    raw,target,upstream=fixture()
    target["domain_targets"]["ENGINEERING"]["quality_min"]=.95
    raw["target_contract_sha256"]=digest(target)
    x=evaluate(raw,target,upstream)
    assert x["status"]=="TARGET_FAIL" and "TO_BE_NOT_MET:ENGINEERING" in x["blocking_codes"]
    print("PASS negative: relative uplift cannot mask missed expert target")
    raw,target,upstream=fixture()
    raw["target_contract_sha256"]="0"*64
    assert "TO_BE_NOT_SOURCE_BOUND" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: modified TO-BE without binding")
    raw,target,upstream=fixture()
    raw["cases"][0]["task_type"]="MULTIPLE_CHOICE"
    assert "MCQ_OR_PROXY_CASE_NOT_ACCEPTABLE" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: MCQ proxy cannot meet expert target")
    raw,target,upstream=fixture()
    raw["raw_started_at"]="2026-10-09T00:00:00Z"
    assert "TO_BE_NOT_FROZEN_BEFORE_RAW" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: TO-BE cannot be defined after model outputs")
    raw,target,upstream=fixture()
    upstream["status"]="BENCHMARK_FAIL"
    assert "FOUR_ARM_BENCHMARK_NOT_ADMITTED" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: existing four-arm gate cannot be bypassed")
    raw,target,upstream=fixture()
    upstream["arm_scores"]["C_EVOLUTION_CURRENT"]=.1
    assert "UPSTREAM_SCORE_MISMATCH" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: AS-IS scores must reconstruct from same RAW")
    raw,target,upstream=fixture()
    del target["domain_targets"]["CAUSAL_REASONING"]
    raw["target_contract_sha256"]=digest(target)
    assert "TO_BE_DOMAIN_COVERAGE_MISMATCH" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: no domain silently omitted from TO-BE")
    raw,target,upstream=fixture()
    raw["cases"][0]["case_id"]=raw["cases"][1]["case_id"]
    assert "CASE_IDS_NOT_UNIQUE" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: duplicated cases cannot inflate evidence")
    raw,target,upstream=fixture()
    del target["domain_targets"]["ENGINEERING"]["rubric_ref"]
    raw["target_contract_sha256"]=digest(target)
    assert "TO_BE_RUBRIC_OR_STANDARD_MISSING" in evaluate(raw,target,upstream)["blocking_codes"]
    print("PASS negative: target quality must have standard and rubric")

if __name__=="__main__":
    test()
