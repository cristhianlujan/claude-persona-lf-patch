#!/usr/bin/env python3
"""Independently recompute V3 method selection on the exact frozen known cases."""
from pathlib import Path
import hashlib
import json
import sys
ROOT=Path(__file__).resolve().parents[3]
ASSETS=ROOT/"sandbox/lf_contract_gate_test/transversal_assets"
sys.path.insert(0,str(ASSETS/"capability_selector"))
from capability_selector_v3 import compose_capabilities_v3

CASES=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
REG=ASSETS/"method_pack_registry/method_pack_registry_v2.json"
RECEIPTS=ROOT/"skills/profile_creator/evals/results/pe_causal_v3_selector_real_receipts_v1.json"
SOURCE_SHA="02dbec96739e5a02b21ab5f1775ef113143ec0a4ee045f0d6710b7e6ab20089e"

def sha(x):
    return hashlib.sha256(json.dumps(x,sort_keys=True,ensure_ascii=False,
            separators=(",",":"),allow_nan=False).encode()).hexdigest()

def replay():
    assert hashlib.sha256(RECEIPTS.read_bytes()).hexdigest()==SOURCE_SHA
    corpus=json.loads(CASES.read_text())
    registry=json.loads(REG.read_text())
    receipt=json.loads(RECEIPTS.read_text())
    assert registry["execution_permission"] is False
    assert receipt["registry_sha256"]==hashlib.sha256(REG.read_bytes()).hexdigest()
    assert receipt["corpus_sha256"]==hashlib.sha256(CASES.read_bytes()).hexdigest()
    assert receipt["status"]=="FROZEN_NON_AUTHORITY_SELECTION"
    by_case={x["case_id"]:x for x in receipt["receipts"]}
    assert len(by_case)==len(corpus["cases"])==4
    for case in corpus["cases"]:
        cid=case["case_id"]
        source_refs=[x["evidence_ref"] for x in case["observations"]]
        context={"causal_requirement":"HIGH","budget":{"max_method_cost_points":2},
                 "selection_cycle":0}
        precondition={"evidence_sufficiency":{
            "value":"SUFFICIENT","verification_state":"VERIFIED",
            "evidence_refs":["fixture://verified-corpus:"+sha({"case_id":cid,"refs":source_refs})]}}
        computed=compose_capabilities_v3(context,[],{"fallback_capabilities":[]},registry,precondition)
        observed=by_case[cid]
        assert observed["source_evidence_refs"]==source_refs
        assert observed["selection"]==computed
        assert observed["selection_sha256"]==sha(computed)
        assert observed["input_context_sha256"]==sha(context)
        assert observed["input_preconditions_sha256"]==sha(precondition)
        assert observed["method_execution"]=="NOT_EXECUTED"
        assert observed["method_id"]=="CAUSAL_ANALYSIS"
        assert [x["method_id"] for x in computed["selected_methods"]]==["CAUSAL_ANALYSIS"]
        assert computed["execution_authorized"] is False
    print(json.dumps({"result":"PASS_REAL_V3_SELECTION_REPLAY",
        "cases":len(by_case),"candidate_only":True,
        "registry_execution_enabled":False,"method_executions":0},sort_keys=True))
if __name__=="__main__":replay()
