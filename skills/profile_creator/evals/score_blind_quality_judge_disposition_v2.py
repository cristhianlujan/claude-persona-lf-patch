#!/usr/bin/env python3
"""Accurate failure disposition for the immutable QA judge calibration.

Independent, sealed expected labels from scorer v1 stay unchanged. A model
judge cannot qualify if it does not distinguish even easy support/contradiction
controls. Never promote on free-text fragments of its rationale.
"""
from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
RAW=ROOT/"skills/profile_creator/evals/results/pe_causal_blind_quality_judge_raw_v1.json"
OUT=ROOT/"pe_causal_blind_quality_judge_score_v2.json"
EXPECTED={"S01":"CONTRADICTED","S02":"SUPPORTED",
          "S03":"CONTRADICTED","S04":"SUPPORTED"}

def main():

    raw=json.loads(RAW.read_text())
    assert raw["raw_frozen"] and raw["attestation"]["verified"] is True
    actual={x["review_id"]:x for x in raw["reviews"]}
    assert set(actual)==set(EXPECTED)
    matched=sum(actual[k]["verdict"]==v for k,v in EXPECTED.items())
    data={
      "schema":"PE_BLIND_QUALITY_JUDGE_DISPOSITION_V2",
      "status":"JUDGE_CALIBRATION_PASS" if matched==len(EXPECTED) else "JUDGE_CALIBRATION_FAIL",
      "actual_matches":matched,"required_matches":len(EXPECTED),
      "reviewer_profile":"QUALITY_REVIEW",
      "reviewer_separate_from_producer_execution":True,
      "same_underlying_model_as_producer":True,
      "independent_external_semantic_assurance":"NOT_EXECUTED",
      "raw_sha256":hashlib.sha256(RAW.read_bytes()).hexdigest(),
      "evaluator_eligible_for_admission":matched==len(EXPECTED) and False,
      "results":[{"id":k,"expected":v,"observed":actual[k]["verdict"],
         "matches":v==actual[k]["verdict"]} for k,v in EXPECTED.items()],
      "error_class":"SEMANTIC_VERDICT_DISCRIMINATION_FAILURE" if matched!=len(EXPECTED) else None,
      "cutover_eligible":False}
    encoded=json.dumps(data,sort_keys=True,indent=2)+"\n"
    if OUT.exists():
        assert OUT.read_text()==encoded, 'FROZEN_ARTIFACT_DRIFT'
    else:
        OUT.write_text(encoded)
    print(json.dumps({"status":data["status"],"passed":matched,"total":len(EXPECTED),
       "sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()},sort_keys=True))

if __name__=="__main__":main()
