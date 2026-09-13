#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from typing import Any, Callable, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"
CARD_MODES = {"EXACT", "COMPATIBLE", "COMPOSED", "GENERIC_SAFE"}
EvidenceResolver = Callable[[str], Mapping[str, Any] | None]

FORBIDDEN_AUTHORITY_EFFECTS = {
    "AUTHORIZE_DOWNSTREAM",
    "PROMOTE_GOLDEN",
    "ENABLE_PRODUCTION",
    "ALTER_AUTHORITY",
}
FORBIDDEN_AUTHORITY_FLAGS = {
    "downstream_authorized",
    "golden_authorized",
    "production_authorized",
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


def _canonical_digest(record: Mapping[str, Any]) -> str:
    raw = json.dumps(dict(record), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolve_binding(
    binding: Mapping[str, Any] | None,
    expected_type: str,
    resolver: EvidenceResolver | None,
    producer_id: str,
    label: str,
) -> tuple[dict[str, Any], Mapping[str, Any] | None]:
    if not isinstance(binding, Mapping):
        return _block("BLOCK_EVIDENCE_BINDING_MISSING", binding=label), None
    if resolver is None:
        return _block("BLOCK_EVIDENCE_RESOLVER_MISSING", binding=label), None
    ref = binding.get("ref")
    expected_sha = binding.get("sha256")
    declared_resolver = binding.get("resolver_id")
    if not isinstance(ref, str) or not ref:
        return _block("BLOCK_EVIDENCE_REF_MISSING", binding=label), None
    if not isinstance(expected_sha, str) or len(expected_sha) != 64:
        return _block("BLOCK_EVIDENCE_SHA256_INVALID", binding=label), None
    if declared_resolver == producer_id:
        return _block("BLOCK_EVIDENCE_SELF_RESOLVER", binding=label, resolver_id=declared_resolver), None
    try:
        record = resolver(ref)
    except Exception as exc:
        return _block("BLOCK_EVIDENCE_RESOLUTION_FAILED", binding=label, error=type(exc).__name__), None
    if not isinstance(record, Mapping):
        return _block("BLOCK_EVIDENCE_UNRESOLVED", binding=label, ref=ref), None
    observed_sha = _canonical_digest(record)
    if observed_sha != expected_sha:
        return _block("BLOCK_EVIDENCE_DIGEST_MISMATCH", binding=label, expected=expected_sha, observed=observed_sha), None
    if record.get("evidence_type") != expected_type:
        return _block("BLOCK_EVIDENCE_TYPE_MISMATCH", binding=label, expected=expected_type, observed=record.get("evidence_type")), None
    if record.get("status") != PASS:
        return _block("BLOCK_RESOLVED_EVIDENCE_NOT_PASS", binding=label, status=record.get("status")), None
    if record.get("resolver_id") != declared_resolver:
        return _block("BLOCK_EVIDENCE_RESOLVER_ID_MISMATCH", binding=label), None
    return {"status": PASS, "code": "PASS_RESOLVED_EVIDENCE", "binding": label}, record


def validate_shared_typed_context(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    producer_id = str(value.get("producer_id") or "")
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
        resolved, receipt = _resolve_binding(
            authority.get("currentness_evidence"),
            "SOURCE_CURRENTNESS_RECEIPT",
            resolver,
            producer_id,
            f"authority_resolution[{index}].currentness_evidence",
        )
        if resolved.get("status") != PASS:
            return resolved
        expected = {
            "source_refs": list(authority.get("source_refs") or []),
            "source_sha256": authority.get("source_sha256"),
            "run_id": current_run_id,
            "currentness": "CURRENT",
        }
        mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
        if mismatches:
            return _block("BLOCK_D_AUTHORITY_CURRENTNESS_MISMATCH", index=index, mismatches=mismatches)

    runtime_schema = value.get("runtime_schema") or {}
    if runtime_schema.get("schema_invention_allowed") is not False:
        return _block("BLOCK_D_RUNTIME_SCHEMA_INVENTION_ALLOWED")
    resolved, receipt = _resolve_binding(
        runtime_schema.get("currentness_evidence"),
        "SOURCE_CURRENTNESS_RECEIPT",
        resolver,
        producer_id,
        "runtime_schema.currentness_evidence",
    )
    if resolved.get("status") != PASS:
        return resolved
    expected = {
        "source_refs": [runtime_schema.get("source_ref")],
        "source_sha256": runtime_schema.get("sha256"),
        "run_id": current_run_id,
        "currentness": "CURRENT",
    }
    mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
    if mismatches:
        return _block("BLOCK_D_RUNTIME_SCHEMA_CURRENTNESS_MISMATCH", mismatches=mismatches)
    if value.get("provenance_reconstructible") is not True:
        return _block("BLOCK_D_PROVENANCE_NOT_RECONSTRUCTIBLE")
    return {"status": PASS, "code": "PASS_D_SHARED_TYPED_CONTEXT"}


def validate_registry_inventory_schema(inventory: Mapping[str, Any], schema: Mapping[str, Any]) -> dict[str, Any]:
    declared = inventory.get("required_capability_manifest_fields") or []
    target = schema.get("required") or []
    if len(declared) != len(set(declared)):
        return _block("BLOCK_E_INVENTORY_DUPLICATE_REQUIRED_FIELD")
    if set(declared) != set(target):
        return _block(
            "BLOCK_E_SOURCE_MODEL_REQUIRED_FIELDS_MISMATCH",
            inventory_only=sorted(set(declared) - set(target)),
            schema_only=sorted(set(target) - set(declared)),
        )
    if "lifecycle_state" in declared or "lifecycle" not in declared:
        return _block("BLOCK_E_LIFECYCLE_FIELD_CONTRACT_MISMATCH")
    return {"status": PASS, "code": "PASS_E_SOURCE_MODEL_CONSISTENT"}


def validate_capability_manifest(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
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

    binding = {
        "ref": currentness.get("evidence_ref"),
        "sha256": currentness.get("evidence_sha256"),
        "resolver_id": currentness.get("resolver_id"),
    }
    resolved, receipt = _resolve_binding(binding, "CAPABILITY_CURRENTNESS_RECEIPT", resolver, str(value.get("owner") or ""), "currentness_binding")
    if resolved.get("status") != PASS:
        return resolved
    expected = {"source_refs": list(refs), "source_digests": list(digests), "currentness": "CURRENT"}
    mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
    if mismatches:
        return _block("BLOCK_E_CURRENTNESS_RECEIPT_MISMATCH", mismatches=mismatches)
    return {"status": PASS, "code": "PASS_E_CAPABILITY_MANIFEST"}


def validate_evidence_envelope(value: Mapping[str, Any], resolver: EvidenceResolver | None = None) -> dict[str, Any]:
    level = value.get("evidence_level")
    ceiling = value.get("claim_ceiling")
    order = {"STRUCTURAL": 0, "PROVENANCE_EXECUTION": 1, "SEMANTIC": 2, "BEHAVIORAL": 3}
    if level not in order or ceiling not in order:
        return _block("BLOCK_F_EVIDENCE_LEVEL_UNKNOWN")
    if order[ceiling] > order[level]:
        return _block("BLOCK_F_CLAIM_EXCEEDS_EVIDENCE", level=level, ceiling=ceiling)
    owner = value.get("owner_receipt") or {}
    if owner.get("preserved_without_rewrite") is not True:
        return _block("BLOCK_F_OWNER_RECEIPT_NOT_PRESERVED")
    if level == "STRUCTURAL":
        return {"status": PASS, "code": "PASS_F_STRUCTURAL_EVIDENCE_ENVELOPE"}

    execution = value.get("execution_identity") or {}
    authority = value.get("authority") or {}
    provenance = value.get("provenance") or {}
    if execution.get("executed") is not True:
        return _block("BLOCK_F_NONSTRUCTURAL_NOT_EXECUTED")
    if authority.get("currentness") != "CURRENT":
        return _block("BLOCK_F_NONSTRUCTURAL_AUTHORITY_NOT_CURRENT")
    if provenance.get("reconstructible") is not True:
        return _block("BLOCK_F_NONSTRUCTURAL_PROVENANCE_NOT_RECONSTRUCTIBLE")

    producer_id = str(value.get("producer_id") or "")
    bindings = value.get("resolved_evidence") or {}
    checks = [
        ("execution_receipt", "EXECUTION_RECEIPT"),
        ("authority_currentness_receipt", "AUTHORITY_CURRENTNESS_RECEIPT"),
        ("provenance_receipt", "PROVENANCE_RECEIPT"),
    ]
    receipts: dict[str, Mapping[str, Any]] = {}
    for key, expected_type in checks:
        resolved, receipt = _resolve_binding(bindings.get(key), expected_type, resolver, producer_id, key)
        if resolved.get("status") != PASS:
            return resolved
        receipts[key] = receipt
    resolved, owner_record = _resolve_binding(owner, "OWNER_RECEIPT", resolver, producer_id, "owner_receipt")
    if resolved.get("status") != PASS:
        return resolved

    exec_expected = {
        "run_id": value.get("run_id"),
        "executed": True,
        "executed_sha": execution.get("executed_sha"),
        "execution_id": execution.get("execution_id"),
    }
    mismatches = {k: {"expected": v, "observed": receipts["execution_receipt"].get(k)} for k, v in exec_expected.items() if receipts["execution_receipt"].get(k) != v}
    if mismatches:
        return _block("BLOCK_F_EXECUTION_RECEIPT_MISMATCH", mismatches=mismatches)

    auth_expected = {"authority_source": authority.get("source"), "currentness": "CURRENT"}
    mismatches = {k: {"expected": v, "observed": receipts["authority_currentness_receipt"].get(k)} for k, v in auth_expected.items() if receipts["authority_currentness_receipt"].get(k) != v}
    if mismatches:
        return _block("BLOCK_F_AUTHORITY_CURRENTNESS_RECEIPT_MISMATCH", mismatches=mismatches)

    prov_expected = {"reconstructible": True, "refs": list(provenance.get("refs") or [])}
    mismatches = {k: {"expected": v, "observed": receipts["provenance_receipt"].get(k)} for k, v in prov_expected.items() if receipts["provenance_receipt"].get(k) != v}
    if mismatches:
        return _block("BLOCK_F_PROVENANCE_RECEIPT_MISMATCH", mismatches=mismatches)

    owner_expected = {"owner_capability_id": owner.get("owner_capability_id"), "run_id": value.get("run_id")}
    mismatches = {k: {"expected": v, "observed": owner_record.get(k)} for k, v in owner_expected.items() if owner_record.get(k) != v}
    if mismatches:
        return _block("BLOCK_F_OWNER_RECEIPT_MISMATCH", mismatches=mismatches)
    return {"status": PASS, "code": "PASS_F_EVIDENCE_ENVELOPE_RESOLVED"}


def validate_runtime_port_request(value: Mapping[str, Any]) -> dict[str, Any]:
    runtime_policy = value.get("runtime_policy") or {}
    if runtime_policy.get("silent_fallback_allowed") is not False:
        return _block("BLOCK_G_SILENT_FALLBACK_ALLOWED")
    forbidden = value.get("authority_decisions_forbidden") or []
    expected = {"AUTHORITY", "CURRENTNESS", "CARD_APPLICABILITY", "PROMOTION", "GOLDEN", "PRODUCTION"}
    if set(forbidden) != expected:
        return _block("BLOCK_G_AUTHORITY_FORBIDDEN_SET_INCOMPLETE", observed=sorted(set(forbidden)))
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_REQUEST"}


def _scan_runtime_receipt(node: Any, path: str = "runtime_receipt") -> dict[str, Any] | None:
    if isinstance(node, Mapping):
        for key, val in node.items():
            current_path = f"{path}.{key}"
            if key in FORBIDDEN_AUTHORITY_FLAGS and val is True:
                return _block("BLOCK_G_NESTED_AUTHORITY_FLAG", path=current_path)
            if key == "authority_grants_allowed" and val is not False:
                return _block("BLOCK_G_NESTED_AUTHORITY_GRANT_ALLOWED", path=current_path)
            if key == "authority_effects":
                if not isinstance(val, list):
                    return _block("BLOCK_G_NESTED_AUTHORITY_EFFECT_SHAPE", path=current_path)
                forbidden = sorted(set(val) & FORBIDDEN_AUTHORITY_EFFECTS)
                if forbidden:
                    return _block("BLOCK_G_NESTED_AUTHORITY_EFFECT", path=current_path, effects=forbidden)
                if val:
                    return _block("BLOCK_G_UNDECLARED_AUTHORITY_EFFECT", path=current_path)
            nested = _scan_runtime_receipt(val, current_path)
            if nested:
                return nested
    elif isinstance(node, list):
        for index, val in enumerate(node):
            nested = _scan_runtime_receipt(val, f"{path}[{index}]")
            if nested:
                return nested
    return None


def validate_runtime_port_output(value: Mapping[str, Any]) -> dict[str, Any]:
    missing = sorted(REQUIRED_RUNTIME_OUTPUT_FIELDS - set(value))
    if missing:
        return _block("BLOCK_G_RUNTIME_OUTPUT_FIELDS_MISSING", missing=missing)
    receipt = value.get("runtime_receipt")
    if not isinstance(receipt, Mapping):
        return _block("BLOCK_G_RUNTIME_RECEIPT_SHAPE")
    nested = _scan_runtime_receipt(receipt)
    if nested:
        return nested
    if receipt.get("authority_grants_allowed") is not False:
        return _block("BLOCK_G_RUNTIME_RECEIPT_AUTHORITY_BOUNDARY_MISSING")
    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_OUTPUT"}
