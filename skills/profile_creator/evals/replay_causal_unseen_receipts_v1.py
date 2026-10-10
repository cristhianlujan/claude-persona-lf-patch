#!/usr/bin/env python3
"""PE-Causal receipt replay: fully reconstruct frozen synthetic method receipts.

Does NOT trust a method's verified label, does NOT activate registry, and
never asserts production/real-world causal truth. Run after checking out PR.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
from copy import deepcopy
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
ASSETS=ROOT/"sandbox/lf_contract_gate_test/transversal_assets"
sys.path.insert(0,str(ASSETS/"capability_selector"))
from capability_selector_v3 import compose_capabilities_v3,replan_composition

CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_tasks_v1.json"
REGISTRY=ASSETS/"method_pack_registry/method_pack_registry_v2.json"
RAW=ROOT/"skills/profile_creator/evals/results/pe_causal_unseen_method_raw_v1.json"
CORPUS_SHA="9915c1cd88eeb425eba2e666d573c9b39f43843f470e3d072c9702d4fe1232e7"
RAW_SHA="0cc6c6fe06760e738bd94d914c3c94f414437176958d931f52fd838b6e8f40be"

def digest(obj):
    return hashlib.sha256(json.dumps(obj,sort_keys=True,ensure_ascii=False,
        separators=(",",":"),allow_nan=False).encode()).hexdigest()

def source_verified(cid,observation):
    token={"case_id":cid,"probe_id":observation["probe_id"],
           "observed":observation["observed"],"source":"fixture-primary-readback"}
    return observation["evidence_ref"]=="fixture-verified://"+digest(token)

def recompute(cid,hypotheses,observations):
    verified={}
    rejected=[]
    for x in observations:
        if source_verified(cid,x): verified[x["probe_id"]]=x["observed"]
        else: rejected.append(x["probe_id"])
    assert verified
    rows=[]
    for h in hypotheses:
        pred=h["predictions"]
        contradicted=sorted(p for p,v in pred.items() if p in verified and verified[p]!=v)
        consistent=sorted(p for p,v in pred.items() if p in verified and verified[p]==v)
        missing=sorted(p for p in pred if p not in verified)
        state="FALSIFIED" if contradicted else "NOT_FALSIFIED" if consistent else "UNTESTED"
        rows.append({"hypothesis_id":h["id"],"state":state,"falsified_by":contradicted,
                     "consistent_with":consistent,"unverified_prediction_probes":missing})
    survivor=[x for x in rows if x["state"]!="FALSIFIED"]
    action=("COLLECT_MORE_EVIDENCE" if len(survivor)!=1
        or any(x["unverified_prediction_probes"] for x in survivor)
        else "EVALUATE_ALTERNATIVE_CAUSES_AND_STOP_GATES")
    return {"schema":"CAUSAL_HYPOTHESIS_FALSIFICATION_V2","status":"EVALUATED",
            "hypotheses":rows,"rejected_evidence":sorted(rejected),
            "causal_proof":False,"execution_permission":False,"candidate_only":True,
            "verified_probe_count":len(verified),"next_action":action}

def replay(corpus,raw,registry):
    assert raw["frozen"] is True and raw["candidate_only"] is True
    assert raw["method_registry_permission"] is False
    assert raw["production_invocations"]==0
    assert raw["corpus_sha256"]==CORPUS_SHA
    assert registry["execution_permission"] is False
    test_registry=deepcopy(registry)
    test_registry["execution_permission"]=True   # fixture only, never authority write
    ctx={"causal_requirement":"HIGH","budget":{"max_method_cost_points":3},"selection_cycle":0}
    pre={"evidence_sufficiency":{"value":"SUFFICIENT","verification_state":"VERIFIED",
         "evidence_refs":["fixture://frozen-input-evidence"]}}
    sel=compose_capabilities_v3(ctx,[],{"fallback_capabilities":[]},test_registry,pre)
    assert [x["method_id"] for x in sel["selected_methods"]]==["CAUSAL_ANALYSIS"]
    by_id={x["case_id"]:x for x in raw["cases"]}
    assert len(by_id)==len(corpus["cases"])==8
    checks=0
    for case in corpus["cases"]:
        cid=case["case_id"]
        assert cid in by_id
        expected_stages=[case["observations"]]
        if cid=="HCA-108":
            expected_stages=[case["observations"][:1],case["observations"]]
        actual=by_id[cid]["stages"]
        assert len(actual)==len(expected_stages)
        permission={"scope":"TEST_NON_AUTHORITY","execution_id":"PE-CAUS-DIS-METHOD:"+cid,
           "allowed_method_ids":["CAUSAL_ANALYSIS"],"receipt_ref":"fixture://test-only-permission"}
        for i,(stage,obs) in enumerate(zip(actual,expected_stages)):
            receipt=stage["receipt"]
            payload={"task":{"case_id":cid,"hypotheses":case["hypotheses"],
                  "observations":obs}}
            report=recompute(cid,case["hypotheses"],obs)
            assert stage["phase"]==i and stage["hypothesis_report"]==report
            assert stage["evidence_refs"]==[o["evidence_ref"] for o in obs]
            composition=sel
            if i:
                changed=replan_composition(ctx,{"trigger":"NEW_EVIDENCE",
                    "evidence_refs":[obs[-1]["evidence_ref"]],
                    "signal_updates":{"causal_requirement":"HIGH"}},[],
                    {"fallback_capabilities":[]},test_registry,pre)
                assert changed["status"]=="REPLANNED"
                composition=changed["new_composition"]
            selected=composition["selected_methods"][0]
            assert receipt["selection_precondition_sha256"]==digest(selected["precondition_receipt"])
            assert receipt["input_sha256"]==digest(payload)
            assert receipt["result_sha256"]==digest({
                "verification_state":"VERIFIED",
                "candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V2","result":report})
            assert receipt["permission_receipt_sha256"]==digest(permission)
            assert receipt["receipt_sha256"]==digest({k:v for k,v in receipt.items() if k!="receipt_sha256"})
            assert receipt["execution_id"]==permission["execution_id"]
            assert receipt["scope"]=="TEST_NON_AUTHORITY"
            assert receipt["method_id"]=="CAUSAL_ANALYSIS"
            assert receipt["result_state"]=="EXECUTED_VERIFIED"
            assert receipt["authority_write"] is False
            assert receipt["production_authorized"] is False
            assert receipt["observed_wall_ms"] >= 0
            checks+=1
    assert raw["method_invocations"]==checks==9
    return checks

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--tamper-test",action="store_true")
    args=parser.parse_args()
    assert hashlib.sha256(CORPUS.read_bytes()).hexdigest()==CORPUS_SHA
    assert hashlib.sha256(RAW.read_bytes()).hexdigest()==RAW_SHA
    corpus=json.loads(CORPUS.read_text())
    raw=json.loads(RAW.read_text())
    registry=json.loads(REGISTRY.read_text())
    validated=replay(corpus,raw,registry)
    tamper_detected=None
    if args.tamper_test:
        forged=deepcopy(raw)
        forged["cases"][0]["stages"][0]["hypothesis_report"]["verified_probe_count"]+=1
        try: replay(corpus,forged,registry)
        except AssertionError:tamper_detected=True
        assert tamper_detected is True,"TAMPER_NOT_DETECTED"
    print(json.dumps({"status":"REPLAY_PASS","cases":len(raw["cases"]),
        "stages":validated,"tamper_detected":tamper_detected,
        "raw_sha256":RAW_SHA,
        "scope":"SYNTHETIC_TEST_ONLY","cutover_eligible":False},sort_keys=True))

if __name__=="__main__":main()
