#!/usr/bin/env python3
import re

HEX64 = re.compile(r"^[a-f0-9]{64}$")
STATES = {"BOUND", "BOUND_CANDIDATE_ONLY", "RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY", "BLOCKED_UNSUPPORTED_TRUST_CLAIM", "BLOCKED_SOURCE_CONFLICT"}


def fail(msg): raise ValueError(msg)

def validate_result(doc):
    if set(doc) != {"state", "marketplace_cx_trust_binding", "lf_adapter_invocations"}: fail("root keys mismatch")
    if doc["state"] not in STATES: fail("invalid state")
    invs=doc["lf_adapter_invocations"]
    if not isinstance(invs,list) or len(invs)!=1: fail("exactly one invocation required")
    inv=invs[0]; req={"adapter_code","adapter_version","invocation_id","activation_reason","source_sha256","capsule_sha256","verdict"}
    if set(inv)!=req: fail("invocation keys mismatch")
    if inv["adapter_code"]!="ADAPTER_MARKETPLACE_LF_CX_TRUST": fail("wrong adapter")
    if len(str(inv["invocation_id"]))<8: fail("invalid invocation id")
    if not HEX64.fullmatch(str(inv["source_sha256"])) or not HEX64.fullmatch(str(inv["capsule_sha256"])): fail("invalid hashes")
    if inv["verdict"] not in {"APPLIED","BLOCKED"}: fail("invalid verdict")
    b=doc["marketplace_cx_trust_binding"]
    keys={"source_refs","promise_boundary","prioritized_trust_risks","transparency_improvements","protected_claims_guardrails","downstream_dependencies","blockers"}
    if set(b)!=keys: fail("binding keys mismatch")
    if not isinstance(b["source_refs"],list) or not b["source_refs"]: fail("source refs required")
    blocked=doc["state"].startswith("BLOCKED") or doc["state"].startswith("RETURN_TO_ORCHESTRATOR")
    if blocked and not b["blockers"]: fail("blocker evidence required")
    if not blocked and b["blockers"]: fail("bound state cannot have blockers")
    if not isinstance(b["protected_claims_guardrails"],list) or not b["protected_claims_guardrails"]: fail("claim guardrails required")
