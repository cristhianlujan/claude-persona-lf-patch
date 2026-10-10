#!/usr/bin/env python3
"""Post-RAW deterministic evaluator of disruptive hypothesis decisions.

Does not trust producer-supplied method verdicts. Derives counterevidence directly
from the frozen corpus with an independently implemented fixture-ref validator.
Small n, no inferential uplift/promotion claims.
"""
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
RAW=ROOT/"pe_causal_disruptive_model_raw_v1.json"
OUT=ROOT/"pe_causal_disruptive_score_v1.json"
CORPUS_SHA="8aa2c5bc685239ebd40a165fe429139d27c4c01be36c8f293a62a66d22326ddd"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def evidence_verified(case_id,o):
 token={"case_id":case_id,"probe_id":o["probe_id"],"observed":o["observed"],
        "source":"fixture-primary-readback"}
 return o["evidence_ref"]=="fixture-verified://"+hashlib.sha256(json.dumps(token,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def oracle(case):
 verified={o["probe_id"]:o["observed"] for o in case["observations"]
           if evidence_verified(case["case_id"],o)}
 falsified=[]
 surviving=[]
 untested=[]
 for h in case["hypotheses"]:
  prediction=h["predictions"]
  counter=[k for k,v in prediction.items() if k in verified and verified[k]!=v]
  missing=[k for k in prediction if k not in verified]
  if counter:falsified.append(h["id"])
  else:
   surviving.append(h["id"])
   if missing:untested.extend(missing)
 expected_action=("COLLECT_MORE_EVIDENCE" if len(surviving)!=1 or untested
                  else "INVESTIGATE_"+surviving[0])
 return {"expected_falsified":sorted(falsified),
         "expected_decision":expected_action,"verified_probes":sorted(verified),
         "unverified_probes":sorted(set(untested))}
def evaluate():
 assert not OUT.exists()
 assert sha(CORPUS)==CORPUS_SHA
 c=json.loads(CORPUS.read_text())
 data=json.loads(RAW.read_text())
 assert data["corpus_sha256"]==CORPUS_SHA and data["raw_frozen"] is True and data["oracle_opened"] is False
 rows={}
 for b in data["batches"]:
  assert b["runtime_attestation"]["verified"] is True
  for answer in b["answers"]:
   key=(b["arm"],answer["case_id"])
   assert key not in rows
   rows[key]={"answer":answer,"wall_ms":b["wall_ms"]/len(b["answers"]),"prompt_tokens":b["usage"].get("prompt_tokens"),
              "receipt":b["receipt_sha256"]}
 arms=data["arms"]
 per_arm={}
 all_cases=[]
 for arm in arms:
  scores=[]
  for case in c["cases"]:
   got=rows[(arm,case["case_id"])]["answer"]
   exp=oracle(case)
   decision=got["decision"]==exp["expected_decision"]
   falsified=sorted(set(got["falsified"]))==exp["expected_falsified"]
   no_causal_overclaim=got["causality_proven"] is False
   reason=got["reason"].upper()
   cites_verified_probe=any(probe.upper() in reason for probe in exp["verified_probes"])
   missing_claim=("CASE_ID" in reason or "CASE IDENTIFIER" in reason) and case["case_id"]!="PE-CAUS-03"
   row={"arm":arm,"case_id":case["case_id"],"decision_correct":decision,
        "falsification_correct":falsified,"causal_proof_not_overclaimed":no_causal_overclaim,
        "verified_probe_named_in_reason":cites_verified_probe,
        "unsupported_case_id_causal_claim":missing_claim,
        "expected":exp,"observed":got}
   scores.append(row);all_cases.append(row)
  per_arm[arm]={"decisions_correct":sum(x["decision_correct"] for x in scores),
   "falsification_correct":sum(x["falsification_correct"] for x in scores),
   "no_causal_overclaim":sum(x["causal_proof_not_overclaimed"] for x in scores),
   "verified_probe_named":sum(x["verified_probe_named_in_reason"] for x in scores),
   "cases":len(scores)}
 # Observational paired counts only, not inferential bootstrap.
 scored={"schema":"PE_CAUSAL_DISRUPTIVE_DETERMINISTIC_SCORE_V1",
  "status":"PILOT_SCORED_NOT_EXPERTISE_ADMITTED",
  "producer_raw_sha256":sha(RAW),"frozen_corpus_sha256":sha(CORPUS),
  "scorer_independent_of_producer_verdict":True,
  "n_paired":len(c["cases"]),"per_arm":per_arm,
  "case_results":all_cases,
  "statistical_uplift":"NOT_DETERMINED_SMALL_SYNTHETIC_CORPUS",
  "full_causal_analysis_admission":False,
  "independent_semantic_assurance":"NOT_EXECUTED",
  "cutover_eligible":False}
 OUT.write_text(json.dumps(scored,sort_keys=True,ensure_ascii=False,indent=2)+"\n")
 print(json.dumps({"status":scored["status"],"n":scored["n_paired"],
        "per_arm":per_arm,"score_sha256":sha(OUT)},sort_keys=True))
if __name__=="__main__":evaluate()
