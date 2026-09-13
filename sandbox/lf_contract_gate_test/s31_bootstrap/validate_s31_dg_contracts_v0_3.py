#!/usr/bin/env python3
from __future__ import annotations

import json
from typing import Any, Mapping

import validate_s31_dg_contracts_v0_2 as v2

PASS = v2.PASS
BLOCKED = v2.BLOCKED
TRUSTED_RESOLVER_ID = v2.TRUSTED_RESOLVER_ID
TrustedRefResolver = v2.TrustedRefResolver
EvidenceResolver = v2.EvidenceResolver

validate_shared_typed_context = v2.validate_shared_typed_context
validate_registry_inventory_schema = v2.validate_registry_inventory_schema
validate_capability_manifest = v2.validate_capability_manifest
validate_runtime_port_output = v2.validate_runtime_port_output


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def _require_execution_revision(
    provider: Mapping[str, Any] | None,
    execution_sha: str,
    label: str,
) -> dict[str, Any] | None:
    observed = (provider or {}).get("revision")
    if observed != execution_sha:
        return _block(
            "BLOCK_F_PROVIDER_REVISION_NOT_EXECUTION_BOUND",
            binding=label,
            expected_execution_sha=execution_sha,
            observed_revision=observed,
        )
    return None


def validate_evidence_envelope(
    value: Mapping[str, Any],
    resolver: EvidenceResolver | None = None,
) -> dict[str, Any]:
    """IR-002 hardening over v0.2.

    v0.2 remains the compatibility baseline. v0.3 closes two gaps:
    owner identity is bound to the envelope capability even for STRUCTURAL
    evidence, and every non-structural evidence/source provider is bound to
    the exact executed revision rather than merely content-current.
    """
    base = v2.validate_evidence_envelope(value, resolver)
    if base.get("status") != PASS:
        return base

    producer_id = str(value.get("producer_id") or "")
    owner = value.get("owner_receipt") or {}
    resolved, owner_record, owner_provider = v2._resolve_binding(
        owner,
        "OWNER_RECEIPT",
        resolver,
        producer_id,
        "owner_receipt",
        require_current_content=True,
    )
    if resolved.get("status") != PASS:
        return resolved

    envelope_capability = value.get("capability_or_gate_id")
    if owner_record.get("owner_capability_id") != envelope_capability:
        return _block(
            "BLOCK_F_OWNER_CAPABILITY_BINDING_MISMATCH",
            expected=envelope_capability,
            observed=owner_record.get("owner_capability_id"),
        )

    if value.get("evidence_level") == "STRUCTURAL":
        return {
            "status": PASS,
            "code": "PASS_F_STRUCTURAL_EVIDENCE_ENVELOPE_V0_3_STRICT",
        }

    execution = value.get("execution_identity") or {}
    execution_sha = execution.get("executed_sha")
    if not isinstance(execution_sha, str) or len(execution_sha) != 40:
        return _block("BLOCK_F_EXECUTION_SHA_INVALID")

    revision_error = _require_execution_revision(
        owner_provider, execution_sha, "owner_receipt"
    )
    if revision_error:
        return revision_error

    input_obj = value.get("input") or {}
    for index, (ref, digest) in enumerate(
        zip(input_obj.get("source_refs") or [], input_obj.get("source_digests") or [])
    ):
        status, provider = v2.resolve_source(
            resolver,
            ref,
            digest,
            f"input.source_refs[{index}]",
            require_current_content=True,
        )
        if status.get("status") != PASS:
            return _block(
                status.get("code", "BLOCK_TRUSTED_EVIDENCE"),
                **{k: val for k, val in status.items() if k not in {"status", "code"}},
            )
        revision_error = _require_execution_revision(
            provider, execution_sha, f"input.source_refs[{index}]"
        )
        if revision_error:
            return revision_error

    authority = value.get("authority") or {}
    status, authority_provider = v2.resolve_source(
        resolver,
        authority.get("source_ref"),
        authority.get("source_digest"),
        "authority.source_ref",
        require_current_content=True,
    )
    if status.get("status") != PASS:
        return _block(
            status.get("code", "BLOCK_TRUSTED_EVIDENCE"),
            **{k: val for k, val in status.items() if k not in {"status", "code"}},
        )
    revision_error = _require_execution_revision(
        authority_provider, execution_sha, "authority.source_ref"
    )
    if revision_error:
        return revision_error

    provenance = value.get("provenance") or {}
    for index, (ref, digest) in enumerate(
        zip(provenance.get("refs") or [], provenance.get("digests") or [])
    ):
        status, provider = v2.resolve_source(
            resolver,
            ref,
            digest,
            f"provenance.refs[{index}]",
            require_current_content=True,
        )
        if status.get("status") != PASS:
            return _block(
                status.get("code", "BLOCK_TRUSTED_EVIDENCE"),
                **{k: val for k, val in status.items() if k not in {"status", "code"}},
            )
        revision_error = _require_execution_revision(
            provider, execution_sha, f"provenance.refs[{index}]"
        )
        if revision_error:
            return revision_error

    bindings = value.get("resolved_evidence") or {}
    for key, evidence_type in (
        ("execution_receipt", "EXECUTION_RECEIPT"),
        ("authority_currentness_receipt", "AUTHORITY_CURRENTNESS_RECEIPT"),
        ("provenance_receipt", "PROVENANCE_RECEIPT"),
    ):
        resolved, _record, provider = v2._resolve_binding(
            bindings.get(key),
            evidence_type,
            resolver,
            producer_id,
            key,
            require_current_content=True,
        )
        if resolved.get("status") != PASS:
            return resolved
        revision_error = _require_execution_revision(provider, execution_sha, key)
        if revision_error:
            return revision_error

    return {
        "status": PASS,
        "code": "PASS_F_EVIDENCE_ENVELOPE_V0_3_STRICT",
    }


def validate_runtime_port_request(
    value: Mapping[str, Any],
    resolver: EvidenceResolver | None = None,
) -> dict[str, Any]:
    """Require both exact Typed Context bytes and its governed internals."""
    base = v2.validate_runtime_port_request(value, resolver)
    if base.get("status") != PASS:
        return base

    status, observed = v2.resolve_source(
        resolver,
        value.get("typed_context_ref"),
        value.get("typed_context_sha256"),
        "typed_context_ref",
        require_current_content=True,
    )
    if status.get("status") != PASS:
        return _block(
            status.get("code", "BLOCK_TRUSTED_EVIDENCE"),
            **{k: val for k, val in status.items() if k not in {"status", "code"}},
        )
    try:
        context = json.loads(observed["raw"].decode("utf-8"))
    except Exception:
        return _block("BLOCK_G_TYPED_CONTEXT_NOT_JSON")

    semantic = v2.validate_shared_typed_context(context, resolver)
    if semantic.get("status") != PASS:
        return _block(
            "BLOCK_G_TYPED_CONTEXT_SEMANTIC_GOVERNANCE",
            nested_code=semantic.get("code"),
        )

    return {"status": PASS, "code": "PASS_G_RUNTIME_PORT_REQUEST_V0_3_STRICT"}
