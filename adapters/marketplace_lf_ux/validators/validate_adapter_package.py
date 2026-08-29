#!/usr/bin/env python3
import re

HEX64 = re.compile(r"^[a-f0-9]{64}$")
STATES = {"BOUND", "BOUND_CANDIDATE_ONLY", "RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY", "BLOCKED_SOURCE_CONFLICT", "BLOCKED_TARGET_UNRESOLVED"}


def fail(msg):
    raise ValueError(msg)


def validate_result(doc):
    if set(doc) != {"state", "marketplace_ux_binding", "lf_adapter_invocations"}: fail("root keys mismatch")
    if doc["state"] not in STATES: fail("invalid state")
    invs = doc["lf_adapter_invocations"]
    if not isinstance(invs, list) or len(invs) != 1: fail("exactly one invocation required")
    inv = invs[0]
    req_inv = {"adapter_code", "adapter_version", "invocation_id", "activation_reason", "source_sha256", "capsule_sha256", "verdict"}
    if set(inv) != req_inv: fail("invocation keys mismatch")
    if inv["adapter_code"] != "ADAPTER_MARKETPLACE_LF_UX": fail("wrong adapter")
    if len(str(inv["invocation_id"])) < 8: fail("invalid invocation id")
    if not HEX64.fullmatch(str(inv["source_sha256"])) or not HEX64.fullmatch(str(inv["capsule_sha256"])): fail("invalid hashes")
    if inv["verdict"] not in {"APPLIED", "BLOCKED"}: fail("invalid verdict")
    b = doc["marketplace_ux_binding"]
    req = {"source_refs", "marketplace_context", "prioritized_frictions", "improvements", "protected_constraints", "downstream_dependencies", "blockers"}
    if set(b) != req: fail("binding keys mismatch")
    if not isinstance(b["source_refs"], list) or not b["source_refs"]: fail("source refs required")
    blocked = doc["state"].startswith("BLOCKED") or doc["state"].startswith("RETURN_TO_ORCHESTRATOR")
    if blocked and not b["blockers"]: fail("blocker evidence required")
    if not blocked and b["blockers"]: fail("bound state cannot have blockers")
