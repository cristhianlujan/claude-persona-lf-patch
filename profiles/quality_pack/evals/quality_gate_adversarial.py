#!/usr/bin/env python3
import copy, hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from validate_gate_bundle import validate_bundle

A,B,C,D,E=(c*64 for c in "abcde")
def ev(ref,sha=A,self_certified=False): return {"ref":ref,"sha256":sha,"observed":True,"self_certified":self_certified}

def base():
    return {
      "final_verdict":"PASS_TO_COMPOSER",
      "gates":{
        "structural":{"applicable":True,"status":"PASS","evidence":[ev("validator://structural",A)]},
        "provenance":{"applicable":True,"status":"PASS","evidence":[ev("receipt://runtime",B)],"receipt_valid":True,"execution_origin":"MODEL_RUNTIME","raw_output_captured":True},
        "semantic":{"applicable":True,"status":"PASS","evidence":[ev("judge://semantic",C)],"producer_oracle_id":"worker-oracle-v1","judge_oracle_id":"independent-judge-v2","decision_supported":True,"uncertainty":"NONE","router_direct_equivalent":True},
        "artifact":{"applicable":True,"status":"PASS","evidence":[ev("artifact://readback",D)],"exists":True,"readback_ok":True,"parseable":True},
        "upstream":{"applicable":True,"status":"PASS","evidence":[ev("upstream://receipt",E)],"current":True,"sha_match":True,"validator_status":"PASS"}
      },
      "acceptance_checks":[{"subject":"selected decision","condition":"observable output satisfies the governed acceptance condition","observable":True}],
      "score":{"total":25,"evidence_by_criterion":{"contract":[ev("criterion://contract",A)],"evidence":[ev("criterion://evidence",B)],"safety":[ev("criterion://safety",C)],"handoff":[ev("criterion://handoff",D)],"scope":[ev("criterion://scope",E)]}},
      "blocking_codes":[],"remaining_risks":[]
    }

def mutate(path,value):
    data=copy.deepcopy(base()); cur=data; keys=path.split(".")
    for key in keys[:-1]: cur=cur[key]
    cur[keys[-1]]=value; return data

cases=[
 ("positive_all_gates","positive",base(),True,None),
 ("receipt_real_semantic_wrong","crosscheck",mutate("gates.semantic.decision_supported",False),False,"decision_supported"),
 ("correct_missing_provenance","crosscheck",mutate("gates.provenance.status","UNCERTAIN"),False,"PASS_TO_COMPOSER requires every applicable gate PASS"),
 ("upstream_stale","negative",mutate("gates.upstream.current",False),False,"stale upstream"),
 ("artifact_plan_only","negative",mutate("gates.artifact.exists",False),False,"artifact PASS requires true"),
 ("router_direct_diverge","adversarial",mutate("gates.semantic.router_direct_equivalent",False),False,"divergence blocks semantic PASS"),
 ("semantic_uncertain","holdout",mutate("gates.semantic.uncertainty","UNCERTAIN"),False,"cannot pass"),
 ("correlated_oracle","adversarial",mutate("gates.semantic.judge_oracle_id","worker-oracle-v1"),False,"must not reuse producer oracle"),
 ("self_certified_evidence","adversarial",mutate("gates.semantic.evidence",[ev("judge://semantic",C,True)]),False,"self-certified evidence"),
 ("generic_acceptance","negative",mutate("acceptance_checks",[{"subject":"","condition":"PASS","observable":False}]),False,"concrete subject required"),
 ("score_25_nominal_evidence","negative",mutate("score",{"total":25,"evidence_by_criterion":{"contract":["PASS"],"evidence":["ok"],"safety":["PASS"],"handoff":["ok"],"scope":["PASS"]}}),False,"evidence must be an object"),
 ("malformed_bundle","negative",None,False,"bundle: expected object")
]

results=[]; failed=False
for case_id,kind,bundle,expected_valid,expected_error in cases:
    errors=validate_bundle(bundle); actual_valid=not errors
    passed=actual_valid==expected_valid and (expected_error is None or any(expected_error in e for e in errors))
    failed |= not passed
    results.append({"id":case_id,"kind":kind,"expected_valid":expected_valid,"actual_valid":actual_valid,"expected_error":expected_error,"errors":errors,"passed":passed})
digest=hashlib.sha256(json.dumps(results,sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed":not failed,"case_count":len(results),"results_sha256":digest,"results":results},indent=2))
raise SystemExit(1 if failed else 0)
