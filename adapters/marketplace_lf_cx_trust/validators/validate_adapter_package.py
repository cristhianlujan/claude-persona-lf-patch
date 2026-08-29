#!/usr/bin/env python3
import re
HASH = re.compile(r"^[a-f0-9]{64}$")
STATES = {"BOUND", "BOUND_CANDIDATE_ONLY", "RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY", "BLOCKED_UNSUPPORTED_TRUST_CLAIM", "BLOCKED_SOURCE_CONFLICT"}

def fail(message):
    raise ValueError(message)

def validate_result(doc):
    if set(doc) != {"state", "marketplace_cx_trust_binding", "lf_adapter_invocations"}:
        fail("root keys")
    if doc["state"] not in STATES:
        fail("state")
    invocations = doc["lf_adapter_invocations"]
    if not isinstance(invocations, list) or len(invocations) != 1:
        fail("exactly one invocation")
    inv = invocations[0]
    required_inv = {"adapter_code", "adapter_version", "invocation_id", "activation_reason", "source_sha256", "capsule_sha256", "verdict"}
    if set(inv) != required_inv or inv["adapter_code"] != "ADAPTER_MARKETPLACE_LF_CX_TRUST":
        fail("invocation identity")
    if len(str(inv["invocation_id"])) < 8 or not HASH.fullmatch(str(inv["source_sha256"])) or not HASH.fullmatch(str(inv["capsule_sha256"])):
        fail("invocation evidence")
    binding = doc["marketplace_cx_trust_binding"]
    required_binding = {"source_refs", "promise_boundary", "prioritized_trust_risks", "transparency_improvements", "protected_claims_guardrails", "downstream_dependencies", "blockers"}
    if set(binding) != required_binding or not binding["source_refs"] or not binding["protected_claims_guardrails"]:
        fail("binding")
    blocked = doc["state"].startswith("BLOCKED") or doc["state"].startswith("RETURN_TO_ORCHESTRATOR")
    if blocked != bool(binding["blockers"]):
        fail("blocker consistency")
