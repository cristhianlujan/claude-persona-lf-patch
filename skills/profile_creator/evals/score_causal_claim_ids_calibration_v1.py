#!/usr/bin/env python3
"""Evaluate known-case claim-ID transport independently of the model runner."""
from __future__ import annotations
import json,hashlib,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha
RAW=ROOT/"pe_causal_claim_ids_calibration_raw_v1.json"
CASE=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
PLAN=ROOT/"pe_causal_disruptive_consumption_v1.json"
METHOD=ROOT/"pe_causal_disruptive_method_raw_v1.json"
SCORE=ROOT/"pe_causal_claim_ids_calibration_score_v1.json"
def main():
 assert not SCORE.exists()
 raw=json.loads(RAW.read_text())
 assert raw["raw_frozen"] and raw["runtime_attestation"]["verified"]
 cases={c["case_id"]:c for c in json.loads(CASE.read_text())["cases"]}
 plans={p["case_id"]:p["stages"][-1] for p in json.loads(PLAN.read_text())["cases"]}
 original={m["case_id"]:m["stages"][-1] for m in json.loads(METHOD.read_text())["cases"]}
 results=[]
 for answer in raw["answer"]["answers"]:
  cid=answer["case_id"]; x=plans[cid]; rec=original[cid]["receipt"]
  method_out=original[cid]["hypothesis_report"]
  trusted={"verification_state":"VERIFIED","candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V1","result":method_out}
  plan={"status":"TEST_ONLY_RECONCILED","method_receipt_sha256":x["receipt"],
    "falsified_hypotheses":x["falsified_hypotheses"],
    "recommended_action":x["reconciled_action"],"causality_proven":False}
  def verify_receipt(p):
   return p==plan and rec["receipt_sha256"]==_sha({k:v for k,v in rec.items() if k!="receipt_sha256"}) and rec["result_sha256"]==_sha(trusted) and rec["receipt_sha256"]==p["method_receipt_sha256"]
  grounded=independently_compile_grounded_answer(
    cases[cid],plan,proposed_claim_ids=answer["claim_ids"],
    verify_method_receipt=verify_receipt)
  correct_fields=(answer["decision"]==plan["recommended_action"]
    and sorted(answer["falsified"])==plan["falsified_hypotheses"]
    and answer["causality_proven"] is False)
  results.append({"case_id":cid,"decision_fields_match":correct_fields,
    "grounding_status":grounded["status"],"blocking_code":grounded.get("blocking_code"),
    "claims":grounded["claims"],"final_text":grounded["final_text"]})
 assert {x["case_id"] for x in results}==set(raw["known_cases"])
 report={"schema":"PE_CAUSAL_CLAIM_IDS_CALIBRATION_SCORE_V1","scope":"KNOWN_CASES_NOT_HOLDOUT",
   "producer_sha256":hashlib.sha256(RAW.read_bytes()).hexdigest(),
   "decision_correct_count":sum(x["decision_fields_match"] for x in results),
   "grounding_accepted_count":sum(x["grounding_status"]=="TEST_ONLY_EVIDENCE_COMPILED" for x in results),
   "cases":results,"external_independent_semantic_assurance":"NOT_EXECUTED",
   "global_quality_uplift":"NOT_ESTABLISHED","cutover_eligible":False}
 SCORE.write_text(json.dumps(report,ensure_ascii=False,indent=2,sort_keys=True)+"\n")
 print(json.dumps({"status":"SCORED_DEVELOPMENT_CALIBRATION",
   "n":len(results),"decisions":report["decision_correct_count"],
   "grounded":report["grounding_accepted_count"],
   "sha256":hashlib.sha256(SCORE.read_bytes()).hexdigest(),
   "reasons":[(x["case_id"],x["blocking_code"]) for x in results]}))
if __name__=="__main__":main()
