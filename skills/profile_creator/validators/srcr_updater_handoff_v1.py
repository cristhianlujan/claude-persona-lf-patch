#!/usr/bin/env python3
"""Preflight structural SRCR -> Updater. Never grants authority or proves E2E."""
import json
import re
import sys
SHA = re.compile(r"[0-9a-f]{64}")
SHA40 = re.compile(r"[0-9a-f]{40}")
EXEC = re.compile(r"EXEC-[A-Za-z0-9][A-Za-z0-9_-]{7,172}")
CODE = re.compile(r"PERFIL-[A-Z0-9][A-Z0-9-]{2,119}")
PATH = re.compile(r"profiles/[a-z0-9][a-z0-9_-]{1,100}/SKILL\.md")
FIXED = dict(schema_version="LF_SRCR_UPDATER_HANDOFF_V1", business="LF",
             mode="REQUEST_ONLY", source_operation="EJECUCION_PERFIL_LF",
             source_profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
             target_operation="ACTUALIZACION_PERFIL_LF")
REQUIRED = set(FIXED) | {"source_execution_id", "target_code", "target_path",
    "request_sha256", "router_authorization_receipt_sha256",
    "policy_snapshot_sha256", "diagnosis_ref", "diagnosis_sha256",
    "target_main_revision_sha", "target_blob_sha",
    "authorized_scope"}
FORBIDDEN = {"repair_execution_authority", "direct_dispatch_authorized",
             "service_role", "jwt", "oidc_token", "production_authorized"}

def inspect(h):
    if not isinstance(h, dict):
        return {"status":"BLOCKED", "blocking_codes":["HANDOFF_NOT_OBJECT"],
                "server_verified":False, "dispatch_authorized":False}
    errors = []
    if set(h) != REQUIRED: errors.append("HANDOFF_FIELDS_NOT_EXACT")
    if set(h) & FORBIDDEN: errors.append("HANDOFF_AUTHORITY_ESCALATION")
    for key,value in FIXED.items():
        if h.get(key) != value: errors.append("HANDOFF_FIXED_"+key.upper())
    for key in ("request_sha256", "router_authorization_receipt_sha256",
                "policy_snapshot_sha256", "diagnosis_sha256"):
        if not isinstance(h.get(key),str) or not SHA.fullmatch(h[key]):
            errors.append("HANDOFF_SHA_"+key.upper())
    for key in ("target_main_revision_sha", "target_blob_sha"):
        if not isinstance(h.get(key),str) or not SHA40.fullmatch(h[key]):
            errors.append("HANDOFF_SHA_"+key.upper())
    if not isinstance(h.get("source_execution_id"),str) or not EXEC.fullmatch(h["source_execution_id"]):
        errors.append("HANDOFF_PARENT_INVALID")
    if not isinstance(h.get("target_code"),str) or not CODE.fullmatch(h["target_code"]):
        errors.append("HANDOFF_TARGET_INVALID")
    if not isinstance(h.get("target_path"),str) or not PATH.fullmatch(h["target_path"]):
        errors.append("HANDOFF_PATH_INVALID")
    if not isinstance(h.get("diagnosis_ref"),str) or not h["diagnosis_ref"].strip() or len(h["diagnosis_ref"])>1024:
        errors.append("HANDOFF_DIAGNOSIS_REF_INVALID")
    if not isinstance(h.get("authorized_scope"),list) or h["authorized_scope"] != [h.get("target_code")]:
        errors.append("HANDOFF_SCOPE_INVALID")
    return {"status":"BLOCKED" if errors else "READY_FOR_SERVER_VERIFICATION",
            "blocking_codes":sorted(set(errors)), "server_verified":False,
            "dispatch_authorized":False}

def inspect_return(h, r):
    if inspect(h)["status"] != "READY_FOR_SERVER_VERIFICATION":
        return {"status":"BLOCKED", "blocking_codes":["HANDOFF_REQUEST_INVALID"],
                "terminal_verified":False}
    required = {"schema_version", "source_execution_id", "child_execution_id",
                "target_code", "status", "terminal_receipt_ref",
                "terminal_receipt_sha256", "exact_head_sha", "next_action"}
    errors=[]
    if not isinstance(r,dict):
        errors.append("RETURN_NOT_OBJECT")
    else:
        if set(r)!=required: errors.append("RETURN_FIELDS_NOT_EXACT")
        if r.get("schema_version")!="LF_SRCR_UPDATER_RETURN_V1": errors.append("RETURN_SCHEMA")
        if r.get("source_execution_id")!=h["source_execution_id"]: errors.append("RETURN_PARENT")
        if r.get("target_code")!=h["target_code"]: errors.append("RETURN_TARGET")
        ch=r.get("child_execution_id")
        if not isinstance(ch,str) or not EXEC.fullmatch(ch) or ch==h["source_execution_id"]:
            errors.append("RETURN_CHILD")
        if r.get("status") not in ("COMPLETED","BLOCKED","NO_CHANGE","NEEDS_MORE_EVIDENCE"):
            errors.append("RETURN_STATUS")
        sha=r.get("terminal_receipt_sha256")
        if not isinstance(sha,str) or not SHA.fullmatch(sha): errors.append("RETURN_RECEIPT_SHA")
        head=r.get("exact_head_sha")
        if not isinstance(head,str) or not SHA40.fullmatch(head):
            errors.append("RETURN_EXACT_HEAD_SHA")
        for key in ("terminal_receipt_ref","next_action"):
            if not isinstance(r.get(key),str) or not r[key].strip():
                errors.append("RETURN_"+key.upper())
    return {"status":"BLOCKED" if errors else "READY_FOR_INDEPENDENT_READBACK",
            "blocking_codes":sorted(set(errors)), "terminal_verified":False}

if __name__=="__main__":
    payload=json.load(sys.stdin)
    outcome=inspect(payload)
    print(json.dumps(outcome,sort_keys=True))
    sys.exit(0 if outcome["status"]=="READY_FOR_SERVER_VERIFICATION" else 1)
