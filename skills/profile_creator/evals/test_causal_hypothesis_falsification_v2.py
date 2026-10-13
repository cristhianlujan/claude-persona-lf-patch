#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(root/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from causal_hypothesis_falsification_v2 import evaluate_hypotheses
cases=json.loads((root/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json").read_text())["cases"]
for c in cases:
 def verify(o):
  t={"case_id":c["case_id"],"probe_id":o["probe_id"],"observed":o["observed"],"source":"fixture-primary-readback"}
  return o["evidence_ref"]=="fixture-verified://"+hashlib.sha256(json.dumps(t,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 r=evaluate_hypotheses(c,evidence_verify=verify)
 assert r["status"]=="EVALUATED" and not r["causal_proof"]
 expected="COLLECT_MORE_EVIDENCE" if c["case_id"] in ("PE-CAUS-04","PE-CAUS-06") else "EVALUATE_ALTERNATIVE_CAUSES_AND_STOP_GATES"
 assert r["next_action"]==expected,(c["case_id"],r["next_action"],expected)
 print(c["case_id"],r["next_action"])
print("PASS_V2_MULTIHYPOTHESIS_AND_UNVERIFIED_OBSERVATION_GATES",len(cases))
