#!/usr/bin/env python3
"""Frozen-source independent scorer for the new, synthetic, 8-case transfer holdout.

D1 and D3 decision correctness are comparable; only D3 has tool-backed claim
cards. Neither this pilot nor the compiler is external semantic assurance.
"""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha
CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
METHOD=ROOT/"pe_causal_unseen_method_raw_v1.json"
CARDS=ROOT/"pe_causal_unseen_remaining_cards_v1.json"
RAW=ROOT/"pe_causal_remaining_holdout_model_raw_v1.json"
OUT=ROOT/"pe_causal_remaining_holdout_score_v1.json"
EXPECTED_SHA="4f3009b78989ee43e44c895f78d747df50f20daf4a31a604193f742bfe66cd8b"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verified(cid,obs):
 proof={"case_id":cid,"probe_id":obs["probe_id"],"observed":obs["observed"],"source":"fixture-primary-readback"}
 return obs["evidence_ref"]=="fixture-verified://"+_sha(proof)
def judge(case):
 v={e["probe_id"]:e["observed"] for e in case["observations"] if verified(case["case_id"],e)}
 hypotheses=case["hypotheses"]
 rejected=sorted(h["id"] for h in hypotheses if any(k in v and v[k]!=val for k,val in h["predictions"].items()))
 surviving=[h for h in hypotheses if h["id"] not in rejected]
 gap=any(any(k not in v for k in h["predictions"]) for h in surviving)
 decision=("COLLECT_MORE_EVIDENCE" if len(surviving)!=1 or gap else "INVESTIGATE_"+surviving[0]["id"])
 return decision,rejected
def main():
 assert not OUT.exists() and sha(CORPUS)==EXPECTED_SHA
 corpus=json.loads(CORPUS.read_text())
 raw=json.loads(RAW.read_text())
 assert raw["raw_frozen"] is True and raw["oracle_opened"] is False
 assert raw["corpus_sha256"]==EXPECTED_SHA and len(raw["batches"])==4
 cases={c["case_id"]:c for c in corpus["cases"]}
 cards={x["case_id"]:x for x in json.loads(CARDS.read_text())["cards"]}
 original={x["case_id"]:x["stages"][-1] for x in json.loads(METHOD.read_text())["cases"]}
 answer_index={}
 for batch in raw["batches"]:
  assert batch["runtime_attestation"]["verified"] is True
  for ans in batch["answers"]:
   key=batch["arm"],ans["case_id"];assert key not in answer_index
   answer_index[key]=ans
 records=[]
 for cid,case in cases.items():
  expected,rejected=judge(case)
  for arm in raw["arms"]:
   a=answer_index[arm,cid]
   correct=a["decision"]==expected and sorted(a["falsified"])==rejected and a["causality_proven"] is False
   state="NOT_APPLICABLE_D1"
   if arm=="D3_TYPED_METHOD":
    card=cards[cid];step=original[cid]
    receipt=step["receipt"];result=step["hypothesis_report"]
    bound={"verification_state":"VERIFIED","candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V2","result":result}
    plan={"status":"TEST_ONLY_RECONCILED","method_receipt_sha256":card["method_receipt_sha256"],
       "falsified_hypotheses":card["falsified_hypotheses"],
       "recommended_action":card["method_decision"],"causality_proven":False}
    def receipt_verifier(x):
     return x==plan and receipt["receipt_sha256"]==_sha({k:v for k,v in receipt.items() if k!="receipt_sha256"}) and receipt["result_sha256"]==_sha(bound) and receipt["receipt_sha256"]==plan["method_receipt_sha256"]
    verified_claims=independently_compile_grounded_answer(case,plan,
        proposed_claim_ids=a["claim_ids"],verify_method_receipt=receipt_verifier)
    state=verified_claims["status"]
    # free-form text is *never* admitted as evidence; only compiled citations
    if state=="TEST_ONLY_EVIDENCE_COMPILED":
     assert verified_claims["recommended_action"]==expected
   records.append({"case_id":cid,"arm":arm,"decision_correct":correct,
     "grounded_claims":state,"expected_decision":expected,
     "expected_falsified":rejected,"output":a})
 counts={}
 for arm in raw["arms"]:
  rows=[x for x in records if x["arm"]==arm]
  counts[arm]={"total":len(rows),
    "decision_correct":sum(x["decision_correct"] for x in rows),
    "grounded_claims":sum(x["grounded_claims"]=="TEST_ONLY_EVIDENCE_COMPILED" for x in rows)}
 summary={"schema":"PE_CAUSAL_REMAINING_HOLDOUT_SCORE_V1",
   "status":"TRANSFER_PILOT_SCORED_NO_EXPERT_CUTOVER",
   "producer_raw_sha256":sha(RAW),"holdout_tasks_sha256":sha(CORPUS),
   "method_cards_sha256":sha(CARDS),"arms":counts,"records":records,
   "free_text_explanations_admitted":0,"independent_external_semantic_assurance":"NOT_EXECUTED",
   "statistical_uplift_admission":"NOT_DEMONSTRATED_N8_SYNTHETIC",
   "cutover_eligible":False}
 OUT.write_text(json.dumps(summary,ensure_ascii=False,indent=2,sort_keys=True)+"\n")
 print(json.dumps({"status":summary["status"],"counts":counts,
  "sha256":sha(OUT)},sort_keys=True))
if __name__=="__main__":main()
