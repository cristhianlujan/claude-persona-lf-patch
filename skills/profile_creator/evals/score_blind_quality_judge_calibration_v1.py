#!/usr/bin/env python3
"""Known-case calibration score for separately bound QUALITY_REVIEW Llama.

May show that a separate profile detects obvious contradictions. Because
same model and development examples, NOT external independent assurance.
"""
from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
RAW=ROOT/"pe_causal_blind_quality_judge_raw_v1.json"
OUT=ROOT/"pe_causal_blind_quality_judge_score_v1.json"
EXPECTED={"S01":"CONTRADICTED","S02":"SUPPORTED",
          "S03":"CONTRADICTED","S04":"SUPPORTED"}

def main():
    assert not OUT.exists()
    obj=json.loads(RAW.read_text())
    assert obj["raw_frozen"] is True
    assert obj["attestation"]["verified"] is True
    assert obj["same_underlying_model_as_producer"] is True
    observed={x["review_id"]:x for x in obj["reviews"]}
    assert set(observed)==set(EXPECTED)
    results=[]
    for k,label in EXPECTED.items():
        row=observed[k]
        results.append({"review_id":k,"expected":label,
            "judge_verdict":row["verdict"],"calibration_match":row["verdict"]==label})
    data={"schema":"PE_BLIND_SEPARATE_QUALITY_REVIEW_SCORE_V1",
       "status":"KNOWN_CASE_MODEL_JUDGE_CALIBRATED_NOT_EXTERNAL_ASSURANCE",
       "producer_judge_separate_execution":True,
       "same_underlying_model":True,
       "raw_sha256":hashlib.sha256(RAW.read_bytes()).hexdigest(),
       "review_count":len(results),
       "matches":sum(x["calibration_match"] for x in results),
       "results":results,
       "external_independent_assurance":"NOT_EXECUTED",
       "cutover_eligible":False}
    OUT.write_text(json.dumps(data,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"status":data["status"],"matches":data["matches"],
        "total":data["review_count"],
        "sha256":hashlib.sha256(OUT.read_bytes()).hexdigest()},sort_keys=True))
if __name__=="__main__":main()
