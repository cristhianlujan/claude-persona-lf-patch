#!/usr/bin/env python3
"""Fail-closed structural preflight for Analysis A1-A9 receipts.

NOT a recorder, executor, authority resolver, independent judge or operational PASS.
Evidence references are NOT dereferenced here; positive results are candidate-only.
"""
from __future__ import annotations
import re

STAGES = tuple(f"A{i}" for i in range(1, 10))
OP_STEPS = (
    "init_execution", "router", "profile_resolve", "profile_source_read",
    "input_validate", "context_admission", "research_baseline_freeze",
    "execute_profile", "output_validate", "semantic_judge", "report_output",
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")
BLOB = re.compile(r"^[0-9a-f]{40}$")


def _sha(v):
    return isinstance(v, str) and bool(SHA256.fullmatch(v))


def validate_readback(packet, binding):
    """Validate a *snapshot of external readbacks*; never declare runtime READY."""
    errs = []
    if not isinstance(packet, dict) or not isinstance(binding, dict):
        return {"status": "FAIL", "errors": ["INVALID_INPUT"], "operational_ready": False}
    run = packet.get("execution")
    if not isinstance(run, dict):
        return {"status": "FAIL", "errors": ["MISSING_CANONICAL_RUN"], "operational_ready": False}
    eid, req = run.get("execution_id"), run.get("request_sha256")
    business = run.get("business")
    # Router handoff is authoritative for business; this candidate binding is LF-only.
    # Never infer LF from schema names or supply LF as an implicit default.
    if not isinstance(business, str) or not business or business != business.strip() or business != business.upper():
        errs.append("BUSINESS_CONTEXT_MISSING_OR_INVALID")
    if not isinstance(binding.get("business"), str) or not binding.get("business"):
        errs.append("BUSINESS_SOURCE_BINDING_MISSING")
    elif business != binding["business"]:
        errs.append("BUSINESS_AUTHORITY_SCOPE_MISMATCH")
    if binding.get("business_source_namespace") != "lf_ops" and business == "LF":
        errs.append("LF_SOURCE_NAMESPACE_MISMATCH")
    if not isinstance(eid, str) or not eid.strip():
        errs.append("EXECUTION_ID_MISSING")
    if not _sha(req):
        errs.append("INPUT_SHA_INVALID")
    if run.get("operation_code") != "EJECUCION_PERFIL_LF":
        errs.append("OPERATION_MISMATCH")
    if run.get("profile_code") != "PERFIL-PROGRAMMING-ANALYSIS-LF":
        errs.append("PROFILE_MISMATCH")
    if run.get("status") != "COMPLETED":
        errs.append("OPERATION_NOT_TERMINAL")

    router = packet.get("router_handoff")
    if not isinstance(router, dict) or router.get("router") != "ACT-0001" or not router.get("authorization_receipt_ref"):
        errs.append("ROUTER_HANDOFF_RECEIPT_MISSING")
    elif (router.get("request_sha256") != req
          or not _sha(router.get("authorization_fingerprint_sha256"))
          or router.get("authorization_receipt_ref") != "router-authorization://" + router.get("authorization_fingerprint_sha256", "")):
        errs.append("ROUTER_RECEIPT_BINDING_MISMATCH")

    if isinstance(router, dict) and router.get("business") != business:
        errs.append("ROUTER_BUSINESS_CONTEXT_MISMATCH")

    steps = packet.get("operation_step_readback")
    if not isinstance(steps, list) or [s.get("step_id") for s in steps if isinstance(s, dict)] != list(OP_STEPS):
        errs.append("OPERATION_11_STEP_READBACK_MISSING")
    else:
        for s in steps:
            if s.get("execution_id") != eid or not s.get("evidence_ref"):
                errs.append("OPERATION_STEP_NOT_BOUND_TO_RUN")
                break
            if s.get("status") != "STEP_PASS_WITH_EVIDENCE":
                errs.append("OPERATION_STEP_NOT_PASS")
                break

    if isinstance(router, dict) and isinstance(steps, list):
        router_step = next((s for s in steps if isinstance(s, dict) and s.get("step_id") == "router"), None)
        if (not isinstance(router_step, dict)
            or router_step.get("evidence_ref") != router.get("authorization_receipt_ref")):
            errs.append("ROUTER_STEP_RECEIPT_NOT_BOUND")

    stages = packet.get("stage_readback")
    if not isinstance(stages, list) or [s.get("stage") for s in stages if isinstance(s, dict)] != list(STAGES):
        errs.append("A1_A9_STAGE_READBACK_MISSING_OR_OUT_OF_ORDER")
    else:
        expected = binding.get("required_stage_sources", {})
        blobs = binding.get("source_readback", {}).get("stage_git_blobs", {})
        for s in stages:
            a = s["stage"]
            if s.get("business") != business:
                errs.append(f"{a}_BUSINESS_CONTEXT_MISMATCH")
            if s.get("execution_id") != eid or s.get("request_sha256") != req:
                errs.append(f"{a}_RUN_BINDING_MISMATCH")
            if (s.get("source_ref") != expected.get(a)
                or s.get("source_git_blob") != blobs.get(a)
                or not isinstance(s.get("source_git_blob"), str)
                or not BLOB.fullmatch(s["source_git_blob"])):
                errs.append(f"{a}_SOURCE_PIN_MISMATCH")
            if s.get("evidence_origin") != "OPERATIONAL_RECORDER" or not s.get("stage_receipt_ref"):
                errs.append(f"{a}_NO_PERSISTED_STAGE_RECEIPT")
            if not _sha(s.get("raw_output_sha256")):
                errs.append(f"{a}_RAW_HASH_MISSING")

    model = packet.get("model_readback")
    if (not isinstance(model, dict) or model.get("business") != business
        or model.get("execution_id") != eid
        or not model.get("raw_ref") or not _sha(model.get("raw_sha256"))):
        errs.append("MODEL_RAW_READBACK_MISSING")
    for key, failure in (
        ("independent_semantic_judge_ref", "INDEPENDENT_JUDGE_RECEIPT_MISSING"),
        ("currentness_authority_receipt_ref", "CURRENTNESS_AUTHORITY_RECEIPT_MISSING"),
        ("downstream_readback_ref", "DOWNSTREAM_READBACK_MISSING"),
    ):
        if not packet.get(key):
            errs.append(failure)

    return {
        "status": "FAIL" if errs else "STRUCTURAL_CANDIDATE_ONLY",
        "errors": sorted(set(errs)),
        "operational_ready": False,
        "source_currentness_verified": False,
        "runtime_provenance_verified": False,
    }
