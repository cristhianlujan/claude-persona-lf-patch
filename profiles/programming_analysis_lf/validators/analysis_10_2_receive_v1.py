#!/usr/bin/env python3
"""A1 / 10.2: deterministic receiver for existing LF canonical-source adapters.

This function neither queries Supabase nor attests issuer/currentness. It does
not register a RUN, persist a checkpoint, or authorize programming.
"""
from __future__ import annotations
from hashlib import sha256
import json
import re

HEX = re.compile(r"^[0-9a-f]{64}$")
CLASS = {"NEW_CANDIDATE", "EXISTING_EVOLUTION_CANDIDATE", "MIXED_CANDIDATE"}
SCHEMA = "ANALYSIS_10_2_SOURCE_RECEPTION_V1"


def digest(payload):
    return sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False).encode("utf-8")).hexdigest()


def receive(previous, run, transfer, sources):
    """Read back 10.1 candidate + exact evidence, return *only* local receipt."""
    errors = []
    if not all(isinstance(x, dict) for x in (previous, run, transfer)):
        return {"schema_version": SCHEMA, "status": "BLOCKED",
                "blocking_codes": ["REQUIRED_READBACK_MISSING"],
                "persisted": False, "operationally_verified": False}
    eid = run.get("execution_id")
    request_sha = run.get("request_sha256")
    business = run.get("business")
    if (business != "LF" or previous.get("business") != "LF"
            or transfer.get("business") != "LF"):
        errors.append("BUSINESS_BINDING_MISMATCH")
    if not isinstance(eid, str) or not eid.strip():
        errors.append("CANONICAL_RUN_MISSING")
    if run.get("operation_code") != "EJECUCION_PERFIL_LF" or run.get("profile_code") != "PERFIL-PROGRAMMING-ANALYSIS-LF":
        errors.append("WRONG_RUN_OWNER")
    if run.get("status") != "IN_PROGRESS":
        errors.append("RUN_NOT_IN_PROGRESS")
    if not isinstance(request_sha, str) or HEX.fullmatch(request_sha) is None:
        errors.append("REQUEST_SHA_INVALID")
    if (previous.get("execution_id") != eid or transfer.get("execution_id") != eid
            or previous.get("request_sha256") != request_sha
            or transfer.get("request_sha256") != request_sha):
        errors.append("EXECUTION_OR_REQUEST_DRIFT")
    if (previous.get("status") != "PRELIMINARY_ONLY"
            or previous.get("development_class") not in CLASS
            or previous.get("persisted") is not False
            or previous.get("programming_authorized") is not False):
        errors.append("10_1_NOT_ELIGIBLE")
    if (transfer.get("from_step") != "10.1" or transfer.get("to_step") != "10.2"
            or transfer.get("sender_payload_sha256") != digest(previous)):
        errors.append("10_1_TO_10_2_TRANSPORT_MISMATCH")

    if not isinstance(sources, dict):
        errors.append("SOURCE_READBACK_MISSING")
    else:
        if sources.get("status") != "FOUND":
            errors.append("SOURCE_NOT_FOUND_OR_UNRESOLVED")
        if (sources.get("business") != "LF"
                or sources.get("source_namespace") != "lf_ops"):
            errors.append("CROSS_BUSINESS_SOURCE_FORBIDDEN")
        if (not isinstance(sources.get("target_type"), str)
                or not sources["target_type"].strip()
                or sources.get("target_type") != transfer.get("target_type")
                or not isinstance(sources.get("target_code"), str)
                or not sources["target_code"].strip()
                or sources.get("target_code") != transfer.get("target_code")):
            errors.append("TARGET_NOT_EXACTLY_RESOLVED")
        target_id = sources.get("definition_id")
        if (not isinstance(target_id, (str, int)) or isinstance(target_id, bool)
            or (isinstance(target_id, int) and target_id < 1)
            or (isinstance(target_id, str) and not target_id.strip())):
            errors.append("DEFINITION_ID_INVALID")
        for key in ("definition_source_ref", "definition_status",
                    "definition_version", "resolved_by", "source_receipt_ref"):
            if not isinstance(sources.get(key), str) or not sources[key].strip():
                errors.append("SOURCE_READBACK_FIELD_MISSING")
                break
        if type(sources.get("rule_count")) is not int or sources["rule_count"] < 0:
            errors.append("RULE_COUNT_INVALID")
        if isinstance(sources.get("rule_count"), int) and sources["rule_count"] > 0 and (
            not isinstance(sources.get("rule_relation_source_ref"), str)
            or not sources["rule_relation_source_ref"].strip()
        ):
            errors.append("RULE_RELATION_SOURCE_REQUIRED")

    if errors:
        return {"schema_version": SCHEMA, "status": "BLOCKED",
                "blocking_codes": sorted(set(errors)), "persisted": False,
                "operationally_verified": False}
    return {
        "schema_version": SCHEMA,
        "status": "RECEIVED_CANDIDATE",
        "business": business,
        "execution_id": eid,
        "request_sha256": request_sha,
        "sender_payload_sha256": digest(previous),
        "from_step": "10.1",
        "to_step": "10.2",
        "target_code": sources["target_code"],
        "target_type": sources["target_type"],
        "definition_id": sources["definition_id"],
        "definition_status": sources["definition_status"],
        "definition_version": sources["definition_version"],
        "definition_source_ref": sources["definition_source_ref"],
        "rule_relation_source_ref": sources.get("rule_relation_source_ref"),
        "rule_count": sources["rule_count"],
        "source_receipt_ref": sources["source_receipt_ref"],
        "source_currentness": "NOT_ATTESTED",
        "definition_approval": "UNVERIFIED_PENDING_10_3",
        "implementation_state": "UNVERIFIED_PENDING_10_4",
        "transport_verification": "STRUCTURAL_CANDIDATE_ONLY",
        "operationally_verified": False,
        "persisted": False,
        "programming_authorized": False,
        "next_action": "10.3",
    }
