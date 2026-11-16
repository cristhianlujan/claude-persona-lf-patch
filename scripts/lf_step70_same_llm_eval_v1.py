"""Deterministic *separate* Step70 evaluator. It does not call a model.

The native LLM review must exist BEFORE evaluation. This evaluator judges
its structured output; it never manufactures model_call_count or receipt_ref.
"""
import hashlib
import json
import re

SCHEMA_ID="LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1"
EVAL_ID="LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1"
EXPECTED=(
 "context_resolution_valid","evidence_supported","decision_resolves_objective",
 "authority_resolution_valid","constraints_preserved","claims_authorized",
 "materiality_handled_correctly","tradeoff_defensible",
 "acceptance_detects_wrong_implementation","handoff_implementation_ready",
 "router_direct_consistency","counterfactual_trajectory"
)

def evaluate(raw, execution_id, candidate_sha, scope_sha):
    errors=[]
    if not isinstance(raw,dict):
        return {"eval_id":EVAL_ID,"eval_status":"FAIL",
                "errors":["STEP70_REVIEW_RAW_NOT_OBJECT"]}
    def chk(ok,code):
        if not ok:errors.append(code)
    chk(raw.get("schema_id")==SCHEMA_ID,"SCHEMA_MISMATCH")
    chk(raw.get("execution_id")==execution_id,"EXECUTION_ID_MISMATCH")
    chk(raw.get("candidate_sha256")==candidate_sha,"CANDIDATE_MISMATCH")
    chk(raw.get("scope_packet_sha256")==scope_sha,"SCOPE_MISMATCH")
    decision=raw.get("decision_body")
    chk(isinstance(decision,dict),"DECISION_BODY_MISSING")
    if isinstance(decision,dict):
        chk(raw.get("verdict")==decision.get("verdict"),"VERDICT_MISMATCH")
        checks=decision.get("decision_checks")
        chk(isinstance(checks,dict) and set(checks)==set(EXPECTED),"CHECK_SET_INVALID")
        if isinstance(checks,dict):
            for k in EXPECTED:
                one=checks.get(k)
                chk(isinstance(one,dict) and bool(one.get("source_refs")) and bool(one.get("reason")),
                    "CHECK_EVIDENCE_MISSING_"+k.upper())
                if isinstance(one,dict) and k!="router_direct_consistency":
                    chk(one.get("result") is True,"CHECK_NOT_PASS_"+k.upper())
                elif isinstance(one,dict) and k=="router_direct_consistency":
                    chk(one.get("result") in (True,"not_applicable"),"ROUTER_DIRECT_INVALID")
        chk(decision.get("unsupported_claims")==[],"UNSUPPORTED_CLAIMS")
        chk(decision.get("blocking_codes")==[],"BLOCKING_CODES_PRESENT")
        chk(isinstance(decision.get("reason"),str) and len(decision["reason"])>=10,
            "DECISION_REASON_MISSING")
    chk(raw.get("verdict")=="PASS_INDEPENDENT_SEMANTIC","NOT_PASS_VERDICT")
    refs=raw.get("source_refs")
    chk(isinstance(refs,list) and len(refs)>0 and all(isinstance(r,str) and len(r)>=4 for r in refs),
        "REVIEW_SOURCE_REFS_MISSING")
    sha=hashlib.sha256(json.dumps(raw,ensure_ascii=False,sort_keys=True,
        separators=(",",":")).encode("utf8")).hexdigest()
    return {"eval_id":EVAL_ID,"eval_status":"PASS" if not errors else "FAIL",
            "errors":errors,"source_schema_id":SCHEMA_ID,"review_raw_sha256":sha,
            "evaluation_performed":True,
            "independent_model_call_attested":False,
            "receipt_minted":False}
