#!/usr/bin/env python3
"""Step 10.1: classify the initial development intent in the existing Analysis RUN.

NOT a Router, source lookup, model judge, implementation-state resolver,
stage-recorder or permission to program. Externally attested intent and
evidence provenance must be checked by the canonical consumer.
"""
from __future__ import annotations

from hashlib import sha256
import re

SHA = re.compile(r"^[0-9a-f]{64}$")
KINDS = {
    "CREATE": ("NEW_CANDIDATE", "CONTINUE_TO_10_2"),
    "EVOLVE": ("EXISTING_EVOLUTION_CANDIDATE", "CONTINUE_TO_10_2"),
    "COMBINE": ("MIXED_CANDIDATE", "CONTINUE_TO_10_2"),
    "REPAIR": ("REPAIR_HANDOFF", "RETURN_TO_ROUTER"),
    "UNKNOWN": ("NEED_MORE_EVIDENCE", "CLARIFY_INTENT"),
}
SCHEMA = "ANALYSIS_10_1_DEVELOPMENT_ENTRY_V1"


def classify(request: dict) -> dict:
    """Classify a typed A1/Router intent, never from string keywords alone."""
    errors = []
    if not isinstance(request, dict):
        return {"schema_version": SCHEMA, "status": "BLOCKED",
                "blocking_codes": ["INPUT_NOT_OBJECT"],
                "operationally_verified": False, "persisted": False,
                "programming_authorized": False}
    business = request.get("business")
    execution = request.get("execution_id")
    literal = request.get("literal_request")
    input_hash = request.get("request_sha256")
    intent = request.get("intent_kind")
    refs = request.get("intent_evidence_refs")
    if business != "LF":
        errors.append("LF_BUSINESS_BINDING_REQUIRED")
    if not isinstance(execution, str) or not execution.strip():
        errors.append("RUN_ID_MISSING")
    if not isinstance(literal, str) or not literal.strip():
        errors.append("LITERAL_REQUEST_MISSING")
    if not isinstance(input_hash, str) or SHA.fullmatch(input_hash) is None:
        errors.append("REQUEST_SHA256_INVALID")
    elif isinstance(literal, str) and sha256(literal.encode("utf-8")).hexdigest() != input_hash:
        errors.append("REQUEST_LITERAL_HASH_MISMATCH")
    if not isinstance(intent, str) or intent not in KINDS:
        errors.append("INTENT_KIND_NOT_CANONICAL")
    if not isinstance(refs, list) or len(refs) == 0 or any(
        not isinstance(ref, str) or not ref.strip() for ref in refs
    ) or len(refs) != len(set(refs)):
        errors.append("INTENT_EVIDENCE_REFS_INVALID")
    if errors:
        return {"schema_version": SCHEMA, "status": "BLOCKED",
                "blocking_codes": sorted(set(errors)),
                "operationally_verified": False, "persisted": False,
                "programming_authorized": False}
    development_class, next_action = KINDS[intent]
    return {
        "schema_version": SCHEMA,
        "status": "PRELIMINARY_ONLY" if intent not in ("REPAIR", "UNKNOWN") else "ROUTE_OR_CLARIFY",
        "development_class": development_class,
        "next_action": next_action,
        "business": business,
        "execution_id": execution,
        "request_sha256": input_hash,
        "intent_kind": intent,
        "intent_evidence_refs": list(refs),
        "authority_state": "UNVERIFIED_PENDING_10_2",
        "implementation_state": "UNVERIFIED_PENDING_10_4",
        "classification_authority": "NOT_ATTESTED",
        "operationally_verified": False,
        "persisted": False,
        "programming_authorized": False,
        "blocking_codes": [],
    }
