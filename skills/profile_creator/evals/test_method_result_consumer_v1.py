#!/usr/bin/env python3
"""Frozen method-result consumer verification against independently recomputed probes."""
from pathlib import Path
import copy,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from method_result_consumer_v1 import consume_hypothesis_method_result,_sha

CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
MRAW=ROOT/"pe_causal_disruptive_method_raw_v1.json"
OUT=ROOT/"pe_causal_disruptive_consumption_v1.json"
def verified(caseid,e):
 t={"case_id":caseid,"probe_id":e["probe_id"],"observed":e["observed"],"source":"fixture-primary-readback"}
 return e["evidence_ref"]=="fixture-verified://"+_sha(t)
def check_report(case,stage,report):
 observations=case["observations"][:1] if case["case_id"]=="PE-CAUS-05" and stage==0 else case["observations"]
 obs={x["probe_id"]:x["observed"] for x in observations if verified(case["case_id"],x)}
 if report.get("causal_proof") is not False or report.get("status")!="EVALUATED":return False
 for row in report["hypotheses"]:
  predictions=next((x["predictions"] for x in case["hypotheses"] if x["id"]==row["hypothesis_id"]),None)
  if predictions is None:return False
  contradicted=sorted(k for k,v in predictions.items() if k in obs and obs[k]!=v)
  compatible=sorted(k for k,v in predictions.items() if k in obs and obs[k]==v)
  missing=sorted(k for k in predictions if k not in obs)
  if row["falsified_by"]!=contradicted or row["consistent_with"]!=compatible or row["unverified_prediction_probes"]!=missing:
   return False
 return len(report["hypotheses"])==len(case["hypotheses"])
def main():
 assert not OUT.exists()
 tasks={c["case_id"]:c for c in json.loads(CORPUS.read_text())["cases"]}
 raw=json.loads(MRAW.read_text())
 summaries=[];num=0
 for c in raw["cases"]:
  case=tasks[c["case_id"]]
  stage_receipts=[]
  for s in c["stages"]:
   receipt=s["receipt"];report=s["hypothesis_report"]
   def verify_receipt(x):
    if x!=receipt:return False
    if x.get("receipt_sha256")!=_sha({k:v for k,v in x.items() if k!="receipt_sha256"}):return False
    reconstructed={"verification_state":"VERIFIED","candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V1","result":report}
    return x.get("result_sha256")==_sha(reconstructed)
   candidate=consume_hypothesis_method_result(receipt,report,
        verify_receipt=verify_receipt,
        verify_method_result=lambda x:check_report(case,s["phase"],x))
   assert candidate["status"]=="TEST_ONLY_RECONCILED",candidate
   stage_receipts.append({"phase":s["phase"],"reconciled_action":candidate["recommended_action"],
         "falsified_hypotheses":candidate["falsified_hypotheses"],
         "receipt":candidate["method_receipt_sha256"],
         "causality_proven":candidate["causality_proven"],
         "unverified_probes":candidate["unverified_probes"]})
   num+=1
  summaries.append({"case_id":c["case_id"],"stages":stage_receipts,
      "final_action":stage_receipts[-1]["reconciled_action"]})
 expected={"PE-CAUS-01":"INVESTIGATE_H2","PE-CAUS-02":"INVESTIGATE_H2",
 "PE-CAUS-03":"INVESTIGATE_H2","PE-CAUS-04":"COLLECT_MORE_EVIDENCE",
 "PE-CAUS-05":"INVESTIGATE_H2","PE-CAUS-06":"COLLECT_MORE_EVIDENCE"}
 assert all(s["final_action"]==expected[s["case_id"]] for s in summaries),summaries
 assert summaries[4]["stages"][0]["reconciled_action"]=="COLLECT_MORE_EVIDENCE"
 assert summaries[4]["stages"][1]["reconciled_action"]=="INVESTIGATE_H2"
 # Missing authorization/verification must not be silently accepted.
 test=raw["cases"][0]["stages"][0]
 invalid=consume_hypothesis_method_result(test["receipt"],test["hypothesis_report"],
                                           verify_receipt=None,verify_method_result=None)
 assert invalid["status"]=="BLOCKED"
 corrupted=copy.deepcopy(test["receipt"]);corrupted["receipt_sha256"]="0"*64
 bad=consume_hypothesis_method_result(corrupted,test["hypothesis_report"],
      verify_receipt=lambda x:True,verify_method_result=lambda x:True)
 assert bad["status"]=="BLOCKED" and bad["reason"]=="RECEIPT_HASH_MISMATCH"
 content={"schema":"PE_CAUSAL_METHOD_RESULT_CONSUMPTION_V1",
   "scope":"TEST_NON_AUTHORITY","provider_method_raw_sha256":hashlib.sha256(MRAW.read_bytes()).hexdigest(),
   "cases":summaries,"stage_count":num,
   "causal_proof":False,"production_activation":False,
   "model_reasoning_uplift_claimed":False,"cutover_eligible":False}
 OUT.write_text(json.dumps(content,ensure_ascii=False,sort_keys=True,indent=2)+"\n")
 print(json.dumps({"status":"PASS","cases":len(summaries),
   "verified_stages":num,"decisions":{s["case_id"]:s["final_action"] for s in summaries},
   "frozen_sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()},sort_keys=True))
if __name__=="__main__":main()
