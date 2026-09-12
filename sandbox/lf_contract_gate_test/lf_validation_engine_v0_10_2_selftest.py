#!/usr/bin/env python3
"""
LF Validation Engine Python Local v0.10.2 — sandbox self-test.
Scope: sandbox only. No Supabase write. No production/runtime enablement.
Run: python sandbox/lf_contract_gate_test/lf_validation_engine_v0_10_2_selftest.py
"""
from __future__ import annotations
import copy, hashlib, json
from typing import Any, Dict

ALLOWED_OPERATION_TYPES={"CREACION_ACTIVO_LF","REPARACION_ACTIVO_LF","ACTUALIZACION_CAPACIDAD_ACTIVO_LF","PROMOCION_ACTIVO_READ_ONLY_LF","AUDITORIA_READ_ONLY_LF","SANDBOX_SIMULATION_LF","VALIDATION_ENGINE_TEST_LF"}
ALLOWED_FINAL_RESULTS={"PASS","FAIL","BLOCKED_WITH_OBSERVATIONS","RETURN_TO_WORKER"}
ALLOWED_JUDGE_RESULTS={"PASS","FAIL","BLOCKED","PASS_WITH_RESTRICTIONS","NOT_RUN"}
ALLOWED_NA_REASONS={"NOT_APPLICABLE_BY_OPERATION_TYPE","DEFERRED_BY_APPROVED_SCOPE","BLOCKED_BY_DEPENDENCY","READ_ONLY_AUDIT_ONLY"}
HASH64=set("0123456789abcdef")

def canonical_json(data:Dict[str,Any])->str:
    return json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(",",":"))

def compute_hash(proof:Dict[str,Any])->str:
    data=copy.deepcopy(proof); data.setdefault("verification",{})
    if isinstance(data["verification"],dict): data["verification"]["verification_hash"]=""
    return hashlib.sha256(canonical_json(data).encode()).hexdigest()

def gp(data:Dict[str,Any], path:str, default=None):
    cur=data
    for part in path.split("."):
        if not isinstance(cur,dict) or part not in cur: return default
        cur=cur[part]
    return cur

def is_sha256(v): return isinstance(v,str) and len(v)==64 and all(c in HASH64 for c in v)
def src_ref_ok(r): return isinstance(r,dict) and r.get("source_type") and r.get("source_id") and r.get("source_sha_or_row_id")
def ev_ref_ok(r): return isinstance(r,dict) and r.get("id") and r.get("hash_referencia")

def validate(proof:Dict[str,Any])->Dict[str,Any]:
    fail=[]
    req=["schema_version","context_integrity_ref.source_event_id","context_integrity_ref.source_snapshot_version","context_integrity_ref.context_hash","operation_type","operation_code","execution_id","actor.actor_type","actor.actor_id","actor.producer_validator_separated","target_asset.asset_code","target_asset.asset_type","phase","step.step_order","step.step_id","step.is_canonical","protocol.protocol_id","protocol.max_canonical_step","judge.judge_result","result.final_result","result.clean_pass_allowed","result.closure_allowed","result.promotion_allowed","readback.required","readback.performed","verification.hash_algorithm","verification.verification_hash"]
    for f in req:
        if gp(proof,f) is None: fail.append(f"MISSING_FIELD:{f}")
    if gp(proof,"operation_type") not in ALLOWED_OPERATION_TYPES: fail.append("FAIL_OPERATION_TYPE_NOT_REGISTERED")
    if gp(proof,"result.final_result") not in ALLOWED_FINAL_RESULTS: fail.append("FAIL_INVALID_FINAL_RESULT_ENUM")
    if gp(proof,"judge.judge_result") not in ALLOWED_JUDGE_RESULTS: fail.append("FAIL_INVALID_JUDGE_RESULT_ENUM")
    if gp(proof,"actor.producer_validator_separated") is not True: fail.append("FAIL_PRODUCER_VALIDATOR_NOT_SEPARATED")
    if gp(proof,"verification.hash_algorithm")!="SHA-256": fail.append("FAIL_INVALID_HASH_ALGORITHM")
    if gp(proof,"context_integrity_ref.context_hash") and not is_sha256(gp(proof,"context_integrity_ref.context_hash")): fail.append("FAIL_CONTEXT_HASH_INVALID")
    if not isinstance(proof.get("source_refs"),list) or not proof.get("source_refs"): fail.append("FAIL_SOURCE_REFS_EMPTY")
    elif not all(src_ref_ok(r) for r in proof["source_refs"]): fail.append("FAIL_SOURCE_REF_WEAK")
    if not isinstance(proof.get("assertions_checked"),list) or not proof.get("assertions_checked"): fail.append("FAIL_ASSERTIONS_EMPTY")
    if not isinstance(proof.get("hard_fails_checked"),list) or not proof.get("hard_fails_checked"): fail.append("FAIL_HARD_FAILS_EMPTY")
    step_order=gp(proof,"step.step_order",999999); max_step=gp(proof,"protocol.max_canonical_step",-1)
    if gp(proof,"step.is_canonical") is not True or not isinstance(step_order,int) or step_order>max_step: fail.append("FATAL_NON_CANONICAL_STEP")
    if gp(proof,"result.final_result")=="PASS" and (gp(proof,"result.clean_pass_allowed") is not True or gp(proof,"result.closure_allowed") is not True): fail.append("FAIL_MANIFEST_BLOCKED_BUT_PASS_ATTEMPTED")
    if gp(proof,"result.final_result")=="PASS" and gp(proof,"result.promotion_allowed") is True: fail.append("FAIL_PROMOTION_ATTEMPTED_WITHOUT_SEPARATE_OPERATION")
    if gp(proof,"judge.judge_result")=="PASS_WITH_RESTRICTIONS" and gp(proof,"result.final_result")=="PASS": fail.append("FAIL_PASS_WITH_RESTRICTIONS_USED_AS_PASS")
    for a in proof.get("assertions_checked",[]) if isinstance(proof.get("assertions_checked"),list) else []:
        if a.get("status") in {"FAIL","BLOCKED"} and gp(proof,"result.final_result")=="PASS": fail.append("FAIL_ASSERTION_BAD_BUT_PASS")
        if not ev_ref_ok(a.get("evidence_ref")): fail.append("FAIL_ASSERTION_EVIDENCE_WEAK")
    for h in proof.get("hard_fails_checked",[]) if isinstance(proof.get("hard_fails_checked"),list) else []:
        if h.get("triggered") is True and gp(proof,"result.final_result")=="PASS": fail.append("FAIL_HARD_FAIL_TRIGGERED_BUT_PASS")
        if not ev_ref_ok(h.get("evidence_ref")): fail.append("FAIL_HARD_FAIL_EVIDENCE_WEAK")
    for n in proof.get("na_controls",[]):
        if n.get("na_reason") not in ALLOWED_NA_REASONS: fail.append("FAIL_INVALID_NA_REASON")
        if n.get("judge_na_result")!="VALID_NA": fail.append("FAIL_INVALID_NA_REVIEW")
        if n.get("is_critical_control") is True: fail.append("FAIL_CRITICAL_CONTROL_MARKED_NA")
    if gp(proof,"readback.required") is True:
        refs=gp(proof,"readback.readback_refs",[])
        if gp(proof,"readback.performed") is not True: fail.append("FAIL_READBACK_REQUIRED_NOT_PERFORMED")
        if not isinstance(refs,list) or not refs: fail.append("FAIL_READBACK_REFS_MISSING")
        for r in refs if isinstance(refs,list) else []:
            if not isinstance(r,dict): fail.append("FAIL_READBACK_NARRATIVE_NOT_STRUCTURED")
            elif not src_ref_ok(r): fail.append("FAIL_READBACK_REF_WEAK")
    if gp(proof,"verification.verification_hash")!=compute_hash(proof): fail.append("FATAL_VERIFICATION_HASH_MISMATCH")
    fail=sorted(set(fail)); fatal=any(x.startswith("FATAL") for x in fail)
    return {"status":"PASS" if not fail else ("FAIL" if fatal else "RETURN_TO_WORKER"),"fail_codes":fail}

def base_proof():
    src={"source_type":"SUPABASE_ROW","source_id":"public.lf_eventos.id=38","source_sha_or_row_id":"38"}
    ev={"id":"EV-PROOF-001","hash_referencia":hashlib.sha256(b"evidence").hexdigest()}
    p={"schema_version":"PROOF_OBJECT_SCHEMA_LF_v0.2_DRAFT","context_integrity_ref":{"source_event_id":38,"source_snapshot_version":"v0.8_consolidado","context_hash":hashlib.sha256(b"lf-context-v0.10.2").hexdigest()},"operation_type":"VALIDATION_ENGINE_TEST_LF","operation_code":"PYTHON_LOCAL_VALIDATION_ENGINE_TEST","execution_id":"EXEC-LF-PY-VALIDATION-001","actor":{"actor_type":"LLM","actor_id":"chatgpt","producer_validator_separated":True},"target_asset":{"asset_code":"PLAN_GOV_SECURITY_PROFILE_CARDS_CORRECCION_ORIGEN_LF","asset_type":"PLAN"},"phase":"E","step":{"step_order":29,"step_id":"report_output","is_canonical":True},"protocol":{"protocol_id":"PROTOCOLO_TEST_LF","max_canonical_step":29},"source_refs":[src],"judge":{"judge_result":"PASS"},"result":{"final_result":"PASS","clean_pass_allowed":True,"closure_allowed":True,"promotion_allowed":False},"assertions_checked":[{"assertion_id":"A001","status":"PASS","evidence_ref":ev}],"hard_fails_checked":[{"hard_fail_id":"HF001","triggered":False,"evidence_ref":ev}],"na_controls":[],"readback":{"required":True,"performed":True,"readback_refs":[src]},"verification":{"hash_algorithm":"SHA-256","verification_hash":""}}
    p["verification"]["verification_hash"]=compute_hash(p); return p

def with_hash(p): p["verification"]["verification_hash"]=compute_hash(p); return p

def main():
    cases={"valid_pass":"PASS"}; proofs={"valid_pass":base_proof()}
    def add(name, expected, mut):
        p=copy.deepcopy(base_proof()); mut(p); proofs[name]=with_hash(p); cases[name]=expected
    add("invalid_noncanonical_step_30","FAIL",lambda p:p["step"].update({"step_order":30,"step_id":"production_read_only_promotion","is_canonical":False}))
    add("invalid_pass_when_blocked","RETURN_TO_WORKER",lambda p:p["result"].update({"closure_allowed":False,"clean_pass_allowed":False,"final_result":"PASS"}))
    p=copy.deepcopy(base_proof()); p["verification"]["verification_hash"]="0"*64; proofs["invalid_bad_hash"]=p; cases["invalid_bad_hash"]="FAIL"
    add("invalid_narrative_readback","RETURN_TO_WORKER",lambda p:p["readback"].update({"readback_refs":["lo revise en el chat anterior"]}))
    add("invalid_empty_assertions","RETURN_TO_WORKER",lambda p:p.update({"assertions_checked":[]}))
    add("invalid_empty_hard_fails","RETURN_TO_WORKER",lambda p:p.update({"hard_fails_checked":[]}))
    add("invalid_empty_source_refs","RETURN_TO_WORKER",lambda p:p.update({"source_refs":[]}))
    add("invalid_weak_evidence_ref","RETURN_TO_WORKER",lambda p:p["assertions_checked"][0].update({"evidence_ref":{"id":"EV-WEAK"}}))
    results=[]; ok_all=True
    for name,exp in cases.items():
        out=validate(proofs[name]); ok=out["status"]==exp; ok_all=ok_all and ok
        results.append({"case":name,"expected":exp,"actual":out["status"],"ok":ok,"fail_codes":out["fail_codes"]})
    report={"suite":"LF_VALIDATION_ENGINE_PYTHON_LOCAL_v0_10_2_SELFTEST","overall_status":"PASS" if ok_all else "FAIL","results":results}
    print(json.dumps(report,indent=2,ensure_ascii=False)); raise SystemExit(0 if ok_all else 1)
if __name__=="__main__": main()
