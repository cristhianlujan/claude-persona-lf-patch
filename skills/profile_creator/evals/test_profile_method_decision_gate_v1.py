#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_method_decision_gate_v1 import reconcile_profile_answer
CONSUMER=ROOT/"pe_causal_disruptive_consumption_v1.json"
RAW=ROOT/"pe_causal_disruptive_model_raw_v1.json"
OUT=ROOT/"pe_causal_disruptive_model_gate_v1.json"
def main():
 assert not OUT.exists()
 consumed=json.loads(CONSUMER.read_text())
 models=json.loads(RAW.read_text())
 data={c["case_id"]:c["stages"][-1] for c in consumed["cases"]}
 from_case={}
 for batch in models["batches"]:
  if batch["arm"]!="D3_WITH_CAUSAL_VERIFICATION":continue
  for answer in batch["answers"]:
   from_case[answer["case_id"]]=answer
 report=[]
 for cid,row in data.items():
  plan={"status":"TEST_ONLY_RECONCILED",
    "recommended_action":row["reconciled_action"],
    "falsified_hypotheses":row["falsified_hypotheses"],
    "causality_proven":False,"method_receipt_sha256":row["receipt"]}
  r=reconcile_profile_answer(plan,from_case[cid],verify_plan=lambda x: x==plan)
  assert not r["publication_authorized"] and not r["cutover_eligible"]
  report.append({"case_id":cid,"model_answer":from_case[cid],"result":r})
 count=sum(x["result"]["status"]=="BLOCKED" for x in report)
 assert count==6
 failplan=dict(plan);failplan["method_receipt_sha256"]="corrupted"
 invalid=reconcile_profile_answer(failplan,from_case[cid],verify_plan=lambda x:x==plan)
 assert invalid["reason"]=="METHOD_PLAN_NOT_VERIFIED"
 # Positive gate: only exact semantic agreement, not automatic approval.
 agreeing={"decision":plan["recommended_action"],"falsified":plan["falsified_hypotheses"],"causality_proven":False,"reason":"Evidence-bound, not causal proof"}
 positive=reconcile_profile_answer(plan,agreeing,verify_plan=lambda x:x==plan)
 assert positive["status"]=="TEST_ONLY_RECONCILED" and not positive["publication_authorized"]
 out={"schema":"PE_CAUSAL_DISRUPTIVE_MODEL_RECONCILIATION_V1","model_raw_sha256":hashlib.sha256(RAW.read_bytes()).hexdigest(),
      "method_plan_sha256":hashlib.sha256(CONSUMER.read_bytes()).hexdigest(),
      "cases":report,"model_conflict_count":count,"admitted_model_outputs":0,
      "production_activations":0,"cutover_eligible":False}
 OUT.write_text(json.dumps(out,sort_keys=True,ensure_ascii=False,indent=2)+"\n")
 print(json.dumps({"model_conflicts_blocked":count,"positive_fixture":"PASS",
 "raw_sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()}))
if __name__=="__main__":main()
