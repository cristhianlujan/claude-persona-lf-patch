#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from causal_hypothesis_falsification_v1 import evaluate_hypotheses
C=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
cases=json.loads(C.read_text())["cases"]
def verify(case_id):
 def fn(obs):
  token={"case_id":case_id,"probe_id":obs["probe_id"],"observed":obs["observed"],"source":"fixture-primary-readback"}
  return obs["evidence_ref"]=="fixture-verified://"+hashlib.sha256(json.dumps(token,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 return fn
n=0
for case in cases:
 r=evaluate_hypotheses(case,evidence_verify=verify(case["case_id"]))
 assert r["status"]=="EVALUATED" and len(r["hypotheses"])==2 and r["causal_proof"] is False;n+=1
t=cases[0].copy()
t["observations"]=[dict(cases[0]["observations"][0],observed=False)]
r=evaluate_hypotheses(t,evidence_verify=verify(t["case_id"]))
assert r["status"]=="BLOCKED" and r["reason"]=="NO_INDEPENDENTLY_VERIFIED_OBSERVATIONS";n+=1
r=evaluate_hypotheses(cases[0],evidence_verify=None)
assert r["status"]=="BLOCKED" and r["reason"]=="REQUEST_OR_EVIDENCE_VERIFIER_MISSING";n+=1
r=evaluate_hypotheses({"case_id":"x","hypotheses":cases[0]["hypotheses"]*2,"observations":[]},evidence_verify=lambda x:True)
assert r["status"]=="BLOCKED" and r["reason"]=="DUPLICATE_HYPOTHESIS";n+=1
r=evaluate_hypotheses(cases[5],evidence_verify=verify(cases[5]["case_id"]))
assert "REPLICA_VALID" in r["rejected_evidence"] and r["verified_probe_count"]==1;n+=1
r=evaluate_hypotheses(cases[3],evidence_verify=verify(cases[3]["case_id"]))
assert all(x["state"]=="NOT_FALSIFIED" for x in r["hypotheses"]);n+=1
print("PASS_CAUSAL_HYPOTHESIS_FALSIFICATION_V1",n,"checks","production_eligible=false")
