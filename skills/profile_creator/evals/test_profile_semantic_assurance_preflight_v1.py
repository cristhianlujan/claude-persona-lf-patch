#!/usr/bin/env python3
"""Read frozen failed QA + test independence preflight fails closed."""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"skills/profile_creator/evals"))
from profile_semantic_assurance_preflight_v1 import preflight_independent_assurance

def main():
 raw=json.loads((ROOT/"skills/profile_creator/evals/results/pe_causal_blind_quality_judge_raw_v1.json").read_text())
 score=json.loads((ROOT/"skills/profile_creator/evals/results/pe_causal_blind_quality_judge_score_v2.json").read_text())
 assert score["status"]=="JUDGE_CALIBRATION_FAIL"
 assert raw["same_underlying_model_as_producer"] is True
 producer={"execution_id":"PE-REAL-PRODUCER", "model_weights_digest":None,
           "attestation_verified":True}
 judge={"execution_id":"PE-REAL-REVIEWER","model_weights_digest":None,
        "attestation_verified":raw["attestation"]["verified"],
        "source_blinding_verified":True,
        "independent_policy_owner_verified":False}
 failed={"frozen_before_evaluation":True,
         "untrusted_model_verdicts_used_as_oracle":False,
         "qualified_cases":score["total"] if "total" in score else score["required_matches"],
         "by_label":{},"critical_false_approvals":None,
         "source_provenance_audited":False}
 observed=preflight_independent_assurance(producer,judge,failed)
 assert observed["status"]=="BLOCKED"
 assert "CALIBRATION_CASE_FLOOR_NOT_MET" in observed["blocking_codes"]
 assert "EVALUATOR_OWNER_NOT_INDEPENDENTLY_VERIFIED" in observed["blocking_codes"]
 assert "EVALUATOR_WEIGHTS_ATTESTATION_MISSING" in observed["blocking_codes"]
 assert not observed["cutover_eligible"]
 valid_cal={"frozen_before_evaluation":True,
            "untrusted_model_verdicts_used_as_oracle":False,"qualified_cases":16,
            "by_label":{k:{"total":4,"correct":4} for k in
              ("SUPPORTED","CONTRADICTED","INSUFFICIENT_EVIDENCE","MIXED")},
            "critical_false_approvals":0,"source_provenance_audited":True}
 p={"execution_id":"TEST-P","model_weights_digest":"1"*64,"attestation_verified":True}
 j={"execution_id":"TEST-J","model_weights_digest":"2"*64,"attestation_verified":True,
    "source_blinding_verified":True,"independent_policy_owner_verified":True}
 candidate=preflight_independent_assurance(p,j,valid_cal)
 assert candidate["status"]=="PREFLIGHT_PASS_NOT_ADMISSION"
 same=preflight_independent_assurance(p,dict(j,model_weights_digest="1"*64),valid_cal)
 assert "SAME_MODEL_WEIGHTS_NOT_INDEPENDENT" in same["blocking_codes"]
 bad=preflight_independent_assurance(p,j,dict(valid_cal,critical_false_approvals=1))
 assert "CRITICAL_FALSE_APPROVALS_NONZERO" in bad["blocking_codes"]
 print(json.dumps({"real_qa":"BLOCKED","real_reason_codes":observed["blocking_codes"],
    "synthetic_positive":"PREFLIGHT_PASS_NOT_ADMISSION",
    "synthetic_same_weights":"BLOCKED","synthetic_false_approval":"BLOCKED",
    "production_admission":False},sort_keys=True))
if __name__=="__main__":main()
