#!/usr/bin/env python3
"""Test-only method dispatch over frozen disruptive evidence; no model or oracle."""
from __future__ import annotations
import json,sys,hashlib,copy
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
D=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
sys.path.insert(0,str(D))
from capability_selector_v3 import compose_capabilities_v3, replan_composition
from method_execution_bridge_v1 import execute_method_selection,_sha
from causal_hypothesis_falsification_v1 import evaluate_hypotheses

CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
CORPUS_SHA="8aa2c5bc685239ebd40a165fe429139d27c4c01be36c8f293a62a66d22326ddd"
REG=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json"
OUT=ROOT/"pe_causal_disruptive_method_raw_v1.json"

def evidence_verified(case_id,obs):
    token={"case_id":case_id,"probe_id":obs["probe_id"],
           "observed":obs["observed"],"source":"fixture-primary-readback"}
    return obs["evidence_ref"]=="fixture-verified://"+_sha(token)

def separate_verify(mid,inputs,result):
    if mid!="CAUSAL_ANALYSIS" or result.get("verification_state")!="VERIFIED":return False
    if result.get("candidate_submethod")!="CAUSAL_HYPOTHESIS_FALSIFICATION_V1":return False
    o=result.get("result",{})
    if o.get("causal_proof") is not False or o.get("status")!="EVALUATED":return False
    source_h={h["id"]:h["predictions"] for h in inputs["task"]["hypotheses"]}
    obs={x["probe_id"]:x["observed"] for x in inputs["task"]["observations"]
         if evidence_verified(inputs["task"]["case_id"],x)}
    for row in o["hypotheses"]:
        pred=source_h.get(row["hypothesis_id"])
        if pred is None:return False
        counter=sorted(k for k,v in pred.items() if k in obs and obs[k]!=v)
        consistent=sorted(k for k,v in pred.items() if k in obs and obs[k]==v)
        if row["falsified_by"]!=counter or row["consistent_with"]!=consistent:return False
        if row["state"]!=("FALSIFIED" if counter else "NOT_FALSIFIED" if consistent else "UNTESTED"):return False
    return len(o["hypotheses"])==len(source_h)

def main():
    assert not OUT.exists()
    assert hashlib.sha256(CORPUS.read_bytes()).hexdigest()==CORPUS_SHA
    corpus=json.loads(CORPUS.read_text())
    reg=json.loads(REG.read_text());assert reg["execution_permission"] is False
    test_registry=copy.deepcopy(reg);test_registry["execution_permission"]=True
    ctx={"causal_requirement":"HIGH","budget":{"max_method_cost_points":3},"selection_cycle":0}
    pre={"evidence_sufficiency":{"value":"SUFFICIENT","verification_state":"VERIFIED",
          "evidence_refs":["fixture://frozen-input-evidence"]}}
    sel=compose_capabilities_v3(ctx,[],{"fallback_capabilities":[]},test_registry,pre)
    assert [x["method_id"] for x in sel["selected_methods"]]==["CAUSAL_ANALYSIS"]
    outputs=[]
    for case in corpus["cases"]:
        current=dict(case)
        recorded=[]
        runid="PE-CAUS-DIS-METHOD:"+case["case_id"]
        permission={"scope":"TEST_NON_AUTHORITY","execution_id":runid,
          "allowed_method_ids":["CAUSAL_ANALYSIS"],"receipt_ref":"fixture://test-only-permission"}
        def handler(inputs):
            ret=evaluate_hypotheses(inputs["task"],evidence_verify=lambda e:evidence_verified(inputs["task"]["case_id"],e))
            return {"verification_state":"VERIFIED" if ret.get("status")=="EVALUATED" else "REJECTED",
              "candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V1","result":ret}
        bindings={"CAUSAL_ANALYSIS":{"scope":"TEST_NON_AUTHORITY","handler":handler,
          "executor_id":"CANDIDATE_HYPOTHESIS_VERIFIER_NON_AUTHORITY",
          "execution_contract_ref":"candidate://CAUSAL_HYPOTHESIS_FALSIFICATION_V1",
          "source_revision":"CANDIDATE_ONLY_V1"}}
        stages=[case["observations"]]
        if case["case_id"]=="PE-CAUS-05":
            stages=[case["observations"][:1],case["observations"]]
        selection=sel
        for phase,obs in enumerate(stages):
            if phase:
                changed=replan_composition(ctx,{
                    "trigger":"NEW_EVIDENCE","evidence_refs":[obs[-1]["evidence_ref"]],
                    "signal_updates":{"causal_requirement":"HIGH"}},
                    [],{"fallback_capabilities":[]},test_registry,pre)
                assert changed["status"]=="REPLANNED",changed
                selection=changed["new_composition"]
            payload={"task":{"case_id":case["case_id"],
                "hypotheses":case["hypotheses"],"observations":obs}}
            out=execute_method_selection(
                selection,test_registry,bindings,{"CAUSAL_ANALYSIS":payload},
                execution_id=runid,evidence_refs=[p["evidence_ref"] for p in obs],
                scope="TEST_NON_AUTHORITY",permission_receipt=permission,
                verify_permission=lambda r:r==permission,
                verify_selection=lambda s: s==selection,
                verify_result=separate_verify,result_verifier_id="SEPARATE_HYPOTHESIS_PREDICTION_VALIDATOR")
            assert out["status"]=="EXECUTED_TEST_ONLY",out
            assert out["actual_method_invocations"]==1
            method_result=handler(payload)["result"]
            assert method_result["causal_proof"] is False
            recorded.append({"phase":phase,"receipt":out["invocations"][0],
                             "hypothesis_report":method_result,
                             "evidence_refs":[p["evidence_ref"] for p in obs]})
        outputs.append({"case_id":case["case_id"],"stages":recorded})
    output={"schema":"PE_CAUSAL_DISRUPTIVE_METHOD_RAW_V1","campaign":corpus["campaign"],
        "corpus_sha256":CORPUS_SHA,"method_invocations":sum(len(c["stages"]) for c in outputs),
        "production_invocations":0,"method_registry_permission":False,
        "candidate_only":True,"cases":outputs,"frozen":True}
    OUT.write_text(json.dumps(output,sort_keys=True,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"status":"FROZEN","cases":len(outputs),
      "method_invocations":output["method_invocations"],
      "replans":sum(len(x["stages"])-1 for x in outputs),
      "raw_sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()},sort_keys=True))
if __name__=="__main__":main()
