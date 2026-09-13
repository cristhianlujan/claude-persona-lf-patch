#!/usr/bin/env python3
from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"
CARD_MODES = {"EXACT", "COMPATIBLE", "COMPOSED", "GENERIC_SAFE"}
FORBIDDEN_AUTHORITY_EFFECTS = {
    "AUTHORIZE_DOWNSTREAM",
    "PROMOTE_GOLDEN",
    "ENABLE_PRODUCTION",
    "ALTER_AUTHORITY",
}
REQUIRED_RUNTIME_OUTPUT_FIELDS = {
    "raw_output",
    "runtime_receipt",
    "transport_diagnostics",
    "resource_usage",
    "failure_code",
}


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def validate_shared_typed_context(value: Mapping[str, Any]) -> dict[str, Any]:
    current_run_id = value.get("current_run_id")
    card = value.get("card_resolution") or {}
    status = card.get("status")
    mode = card.get("mode")

    if status == "RESOLVED" and mode not in CARD_MODES:
        return _block("BLOCK_D_RESOLVED_CARD_MODE_INVALID", mode=mode)
    if status in {"NO_DIRECT_CARD", "AMBIGUOUS", "BLOCKED"} and mode is not None:
        return _block("BLOCK_D_NONRESOLVED_CARD_HAS_MODE", status=status, mode=mode)
    if card.get("schema_invention_allowed") is not False:
        return _block("BLOCK_D_SCHEMA_INVENTION_ALLOWED")

    authorities = value.get("authority_resolution") or []
    for index, authority in enumerate(authorities):
        if not isinstance(authority, Mapping):
            return _block("BLOCK_D_AUTHORITY_SHAPE", index=index)
        run_id = authority.get("run_id")
        if run_id != current_run_id and authority.get("cross_run_declared") is not True:
            return _block("BLOCK_D_UNDECLARED_CROSS_RUN_AUTHORITY", index=index, run_id=run_id)

    runtime_schema = value.get("runtime_schema") or {}
    if runtime_schema.get("schema_invention_allowed") is not False:
        return _block("BLOCK_D_RUNTIME_SCHEMA_INVENTION_ALLOWED")
    if value.get("provenance_reconstructible") is not True:
        return _block("BLOCK_D_PROVENANCE_NOT_RECONSTRUCTIBLE")
    return {"status": PASS, "code": "PASS_D_SHARED_TYPED_CONTEXT"}


def validate_capability_manifest(value: Mapping[str, Any]) -> dict[str, Any]:
    lifecycle = value.get("lifecycle") or {}
    if lifecycle.get("self_certification_allowed") is not False:
        return _block("BLOCK_E_SELF_CERTIFICATION")
    if lifecycle.get("canonical_vocabulary_status") != "UNRESOLVED":
        return _block("BLOCK_E_LIFECYCLE_VOCABULARY_OVERCLAIM")
    currentness = value.get("currentness_binding") or {}
    if currentness.get("stale_action") != "FAIL_CLOSED":
        return _block("BLOCK_E_STALE_NOT_FAIL_CLOSED")

    refs = value.get("source_refs") or []
    digests = value.get("source_digests") or []
    if len(refs) != len(digests):
        return _block("BLOCK_E_SOURCE_BINDING_CARDINALITY", refs=len(refs), digests=len(digests))

    dependencies = value.get("dependencies") or []
    dep_ids = [d.get("capability_id") for d in dependencies if isinstance(d, Mapping)]
    if len(dep_ids) != len(set(dep_ids)):
        return _block("BLOCK_E_DUPLICATE_DEPENDENCY")
    return {"status": PASS, "code": "PASS_E_CAPABILITY_MANIFEST"}


def validate_evidence_envelope(value: Mapping[str, Any]) -> dict[str, Any]:
    level = value.get("evidence_level")
    ceiling = value.get("claim_ceiling")
    order = {
        "STRUCTURAL": 0,
        "PROVENANCE_EXECUTION": 1,
        "SEMANTIC": 2,
        "BEHAVIORAL": 3,
    }
    if level not in order or ceiling not in order:
        return _block("BLOCK_F_EVIDENCE_LEVEL_UNKNOWN")
    if order[ceiling] > order[level]:
        return _block("BLOCK_F_CLAIM_EXCEEDS_EVIDENCE", level=level, ceiling=ceiling)

    if level != "STRUCTURAL":
        execution = value.get("execution_identity") or {}
        authority = value.get("authority") or {}
        provenance = value.get("provenance") or {}
        if execution.get("executed") is not True:
            return _block("BLOCK_F_NONSTRUCTURAL_NOT_EXECUTED")
        if authority.get("currentness") != "CURRENT":
            return _block("BLOCK_F_NONSTRUCTURAL_AUTHORITY_NOT_CURRENT")
        if provenance.get("reconstructible") is not True:
            return _block("BLOCK_F_NONSTRUCTURAL_PROVENANCE_NOT_RECONSTRUCTIBLE")
    return {"status": PASS, "code": "PASS_F_EVIDENCE_ENVELOPE"}


def validate_runtime_port_request(value: Mapping[str, Any]) -> dict[str, Any]:
    runtime_policy = value.get("runtime_policy") or {}
    if runtime_policy.get("silent_fallback_allowed") is not False:
        return _block("BLOCK_G_SILENT_FALLBACK_ALLOWED")
    forbidden = value.get("authority_decisions_forbidden") or []
    expected = {"AUTHORITY", "CURRENTNESS", "CARD_APPLICABILITY", "PROMOTION", "GOLDEN", "PRODUCTION"}
    if set(forbidden) != expected:
        return _block("BLOCK_G_AUTHORITY_FORBIDDEN_SET_INCOMPLETE", observed=sorted(set(forbidden)))
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_REQUEST"}


def validate_runtime_port_output(value: Mapping[str, Any]) -> dict[str, Any]:
    missing = sorted(REQUIRED_RUNTIME_OUTPUT_FIELDS - set(value))
    if missing:
        return _block("BLOCK_G_RUNTIME_OUTPUT_FIELDS_MISSING", missing=missing)
    if value.get("downstream_authorized") is True:
        return _block("BLOCK_G_OUTPUT_AUTHORIZES_DOWNSTREAM")
    if value.get("golden_authorized") is True:
        return _block("BLOCK_G_OUTPUT_AUTHORIZES_GOLDEN")
    if value.get("production_authorized") is True:
        return _block("BLOCK_G_OUTPUT_AUTHORIZES_PRODUCTION")
    effects = value.get("authority_effects")
    if effects:
        if isinstance(effects, (list, tuple, set)):
            forbidden = sorted(set(effects) & FORBIDDEN_AUTHORITY_EFFECTS)
            if forbidden:
                return _block("BLOCK_G_OUTPUT_AUTHORITY_EFFECT", effects=forbidden)
        else:
            return _block("BLOCK_G_OUTPUT_AUTHORITY_EFFECT_SHAPE")
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_OUTPUT"}
