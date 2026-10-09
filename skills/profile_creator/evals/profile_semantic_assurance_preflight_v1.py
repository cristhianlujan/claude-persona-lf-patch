"""Non-authority preflight for existing independent-assurance admission requirement.

Independent evaluator must use verified distinct model weights and separate
execution identity; control calibration and semantic evidence must be present.
Does not write gates/policies, grant authority, or approve expert promotion.
"""
from __future__ import annotations
from typing import Any

def preflight_independent_assurance(
    producer:dict[str,Any],evaluator:dict[str,Any],
    calibration:dict[str,Any],
)->dict[str,Any]:
    result={"schema":"PROFILE_EVOLUTION_SEMANTIC_ASSURANCE_PREFLIGHT_V1",
        "status":"BLOCKED","blocking_codes":[],
        "authority_change":False,"production_authorized":False,
        "cutover_eligible":False}
    fail=result["blocking_codes"]
    if not all(isinstance(x,dict) for x in (producer,evaluator,calibration)):
        return {**result,"blocking_codes":["ATTESTATION_INPUT_INVALID"]}
    for side,item in (("PRODUCER",producer),("EVALUATOR",evaluator)):
        if not isinstance(item.get("execution_id"),str) or not item["execution_id"]:
            fail.append(side+"_EXECUTION_ID_MISSING")
        if not isinstance(item.get("model_weights_digest"),str) or len(item["model_weights_digest"])!=64:
            fail.append(side+"_WEIGHTS_ATTESTATION_MISSING")
        if item.get("attestation_verified") is not True:
            fail.append(side+"_ATTESTATION_UNVERIFIED")
    if producer.get("execution_id") and producer.get("execution_id")==evaluator.get("execution_id"):
        fail.append("EXECUTION_NOT_SEPARATE")
    if (producer.get("model_weights_digest") and
        producer.get("model_weights_digest")==evaluator.get("model_weights_digest")):
        fail.append("SAME_MODEL_WEIGHTS_NOT_INDEPENDENT")
    if evaluator.get("source_blinding_verified") is not True:
        fail.append("EVALUATOR_NOT_BLINDED")
    if evaluator.get("independent_policy_owner_verified") is not True:
        fail.append("EVALUATOR_OWNER_NOT_INDEPENDENTLY_VERIFIED")
    if calibration.get("frozen_before_evaluation") is not True:
        fail.append("CALIBRATION_NOT_FROZEN")
    if calibration.get("untrusted_model_verdicts_used_as_oracle") is not False:
        fail.append("ORACLE_ORIGIN_NOT_INDEPENDENT")
    if type(calibration.get("qualified_cases")) is not int or calibration["qualified_cases"]<16:
        fail.append("CALIBRATION_CASE_FLOOR_NOT_MET")
    confusion=calibration.get("by_label",{})
    labels=("SUPPORTED","CONTRADICTED","INSUFFICIENT_EVIDENCE","MIXED")
    if (not isinstance(confusion,dict) or
       any(not isinstance(confusion.get(label),dict) or
         type(confusion[label].get("total")) is not int or confusion[label]["total"]<4
         for label in labels)):
        fail.append("CALIBRATION_LABEL_COVERAGE_INSUFFICIENT")
    else:
        if any(type(confusion[label].get("correct")) is not int or
             not 0<=confusion[label]["correct"]<=confusion[label]["total"]
             for label in labels):
            fail.append("CALIBRATION_COUNTS_INVALID")
        elif sum(confusion[z]["correct"] for z in labels)/sum(confusion[z]["total"] for z in labels)<.9:
            fail.append("CALIBRATION_ACCURACY_BELOW_FLOOR")
    if calibration.get("critical_false_approvals")!=0:
        fail.append("CRITICAL_FALSE_APPROVALS_NONZERO")
    if calibration.get("source_provenance_audited") is not True:
        fail.append("CLAIM_PROVENANCE_AUDIT_MISSING")
    if not fail:
        return {**result,"status":"PREFLIGHT_PASS_NOT_ADMISSION",
            "blocking_codes":[],
            "required_next_gate":"INDEPENDENT_HOLDOUT_AND_LONGITUDINAL_EVIDENCE"}
    return result
