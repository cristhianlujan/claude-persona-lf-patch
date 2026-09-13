from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

EXPECTED_CANDIDATE="3b39657fbf14f29c7839ecb26d715ed5c6fad59e"
REQUIRED_AUTH={"PROFILE_SOURCE","INPUT_GOVERNANCE"}


def canon(v):
    return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()).hexdigest()


def main():
    ap=argparse.ArgumentParser(); ap.add_argument("receipt",type=Path); a=ap.parse_args()
    r=json.loads(a.receipt.read_text(encoding="utf-8")); errors=[]
    if r.get("schema")!="S26_F10_REAL_E2E_EXECUTION_RECEIPT_V2": errors.append("SCHEMA_INVALID")
    if r.get("final_candidate_sha")!=EXPECTED_CANDIDATE: errors.append("CANDIDATE_SHA_MISMATCH")
    if r.get("fresh_input") is not True: errors.append("FRESH_INPUT_NOT_PROVEN")
    if r.get("fresh_run_identity") is not True: errors.append("FRESH_RUN_ID_NOT_PROVEN")
    if r.get("reused_hp001_upstream_context") is not False: errors.append("HP001_REUSE_NOT_FALSE")
    if r.get("forbidden_hp001_references") not in ([],None): errors.append("HP001_REFERENCE_PRESENT")
    if r.get("full_governed_pipeline_observed") is not True: errors.append("FULL_PIPELINE_NOT_OBSERVED")
    if r.get("typed_context_present") is not True: errors.append("TYPED_CONTEXT_MISSING")
    if r.get("typed_context_consumed_by_runtime_exact_match") is not True: errors.append("TYPED_CONTEXT_NOT_CONSUMED_EXACTLY")
    if r.get("authority_resolution_count",0)<2: errors.append("AUTHORITY_COUNT_TOO_LOW")
    if not REQUIRED_AUTH.issubset(set(r.get("authority_types") or [])): errors.append("AUTHORITY_TYPES_INCOMPLETE")
    if r.get("runtime_status")!="PASS": errors.append("RUNTIME_NOT_PASS")
    if r.get("runtime_execution_origin")!="MODEL_RUNTIME": errors.append("NOT_MODEL_RUNTIME")
    if r.get("runtime_source_sha")!=EXPECTED_CANDIDATE: errors.append("RUNTIME_SOURCE_SHA_MISMATCH")
    if r.get("profile_contract_status")!="PASS": errors.append("CONTRACT_NOT_PASS")
    if r.get("semantic_utility_floor_status")!="PASS": errors.append("SEMANTIC_FLOOR_NOT_PASS")
    da=r.get("deterministic_material_acceptance") or {}
    if not da or not all(v is True for v in da.values()): errors.append("MATERIAL_ACCEPTANCE_NOT_PASS")
    if r.get("independent_semantic_review")!="PENDING_INDEPENDENT_CHAT_CONTEXT": errors.append("INDEPENDENT_STATE_INVALID")
    if r.get("pass") is not False or "INDEPENDENT_CHAT_CONTEXT_REQUIRED" not in (r.get("blocking_codes") or []): errors.append("PREMATURE_FINAL_PASS")
    claimed=r.get("receipt_sha256"); payload=dict(r); payload.pop("receipt_sha256",None)
    if claimed!=canon(payload): errors.append("RECEIPT_SHA_MISMATCH")
    print(json.dumps({"valid":not errors,"errors":errors,"run_id":r.get("run_id"),"producer_pipeline_status":r.get("producer_pipeline_status")},sort_keys=True))
    return 0 if not errors else 1

if __name__=="__main__": raise SystemExit(main())
