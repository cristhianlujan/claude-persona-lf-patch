#!/usr/bin/env python3
"""Second-pass independent constrained semantic audit of four unseen cases."""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha
from profile_grounded_claim_independent_judge_v1 import audit_grounded_rationale

CASES=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
METHOD=ROOT/"pe_causal_unseen_method_raw_v1.json"
CARDS=ROOT/"pe_causal_unseen_remaining_cards_v1.json"
MODEL=ROOT/"pe_causal_remaining_holdout_model_raw_v1.json"
OUT=ROOT/"pe_causal_remaining_holdout_semantic_audit_v1.json"

def main():
 assert not OUT.exists()
 tasks={x["case_id"]:x for x in json.loads(CASE.read_text())["cases"]}
 methods={x["case_id"]:x["stages"][-1] for x in json.loads(METHOD.read_text())["cases"]}
 cards={x["case_id"]:x for x in json.loads(CARDS.read_text())["cards"]}
 raw=json.loads(MODEL.read_text())
 assert raw["raw_frozen"] is True and raw["oracle_opened"] is False
 answers={}
 for batch in raw["batches"]:
  if batch["arm"]!="D3_TYPED_METHOD":continue
  assert batch["runtime_attestation"]["verified"] is True
  for x in batch["answers"]:
   assert x["case_id"] not in answers
   answers[x["case_id"]]=x
 assert set(answers)==set(tasks)
 rows=[]
 for cid,case in tasks.items():
  answer=answers[cid];card=cards[cid];mr=methods[cid]
  receipt=mr["receipt"];result=mr["hypothesis_report"]
  payload={"verification_state":"VERIFIED",
    "candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V2","result":result}
  plan={"status":"TEST_ONLY_RECONCILED",
    "recommended_action":card["method_decision"],
    "falsified_hypotheses":card["falsified_hypotheses"],
    "method_receipt_sha256":card["method_receipt_sha256"],
    "causality_proven":False}
  def verified(x):
   return (x==plan and receipt["receipt_sha256"]==_sha({k:v for k,v in receipt.items() if k!="receipt_sha256"})
     and receipt["result_sha256"]==_sha(payload)
     and receipt["receipt_sha256"]==plan["method_receipt_sha256"])
  compiled=independently_compile_grounded_answer(
    case,plan,proposed_claim_ids=answer["claim_ids"],
    verify_method_receipt=verified)
  independent=(audit_grounded_rationale(case,compiled)
      if compiled["status"]=="TEST_ONLY_EVIDENCE_COMPILED"
      else {"status":"BLOCKED","reason":compiled.get("blocking_code")})
  exact_decision=(answer["decision"]==plan["recommended_action"]
       and sorted(answer["falsified"])==sorted(plan["falsified_hypotheses"])
       and answer["causality_proven"] is False)
  rows.append({"case_id":cid,"model_decision_matches_method":exact_decision,
    "compiled_status":compiled["status"],
    "independent_restricted_semantic_status":independent["status"],
    "reason":independent.get("reason"),
    "model_free_text_admitted":False})
 result={"schema":"PE_CAUSAL_REMAINING_HOLDOUT_INDEPENDENT_SEMANTIC_AUDIT_V1",
   "source_raw_sha256":hashlib.sha256(MODEL.read_bytes()).hexdigest(),
   "results":rows,"case_count":len(rows),
   "verified_and_consistent":sum(x["model_decision_matches_method"] and
       x["independent_restricted_semantic_status"]=="TEST_ONLY_CONSTRAINED_SEMANTIC_PASS" for x in rows),
   "unrestricted_semantic_assurance":"NOT_EXECUTED",
   "production_activation":False,"cutover_eligible":False}
 OUT.write_text(json.dumps(result,sort_keys=True,indent=2,ensure_ascii=False)+"\n")
 print(json.dumps({"status":"RESTRICTED_SEMANTIC_AUDIT_COMPLETED",
    "verified":result["verified_and_consistent"],"n":len(rows),
    "sha256":hashlib.sha256(OUT.read_bytes()).hexdigest(),
    "reasons":[(x["case_id"],x["reason"]) for x in rows]}))
if __name__=="__main__":main()
