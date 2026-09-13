#!/usr/bin/env python3
from __future__ import annotations

import hashlib
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

CROSS_BINDING_VERSION = "S31_F_CROSS_BINDING_V0_1"


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def _canonical_digest(value: Any) -> str:
    raw = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolved_source(
    resolver: EvidenceResolver | None,
    ref: str,
    digest: str,
    label: str,
) -> tuple[dict[str, Any], Mapping[str, Any] | None]:
    status, provider = v2.resolve_source(
        resolver,
        ref,
        digest,
        label,
        require_current_content=True,
    )
    if status.get("status") != PASS:
        return _block(
            status.get("code", "BLOCK_TRUSTED_EVIDENCE"),
            **{k: val for k, val in status.items() if k not in {"status", "code"}},
        ), provider
    return {"status": PASS, "code": "PASS_F_SOURCE_RESOLVED"}, provider


def _cross_binding_identity(
    value: Mapping[str, Any],
    input_sources: list[dict[str, Any]],
    authority_provider: Mapping[str, Any],
    provenance_sources: list[dict[str, Any]],
) -> dict[str, Any]:
    input_obj = value.get("input") or {}
    output_obj = value.get("output") or {}
    execution = value.get("execution_identity") or {}
    authority = value.get("authority") or {}
    return {
        "run_id": value.get("run_id"),
        "capability_or_gate_id": value.get("capability_or_gate_id"),
        "execution_id": execution.get("execution_id"),
        "input_digest": input_obj.get("digest"),
        "output_digest": output_obj.get("digest"),
        "input_sources": input_sources,
        "authority": {
            "source": authority.get("source"),
            "ref": authority.get("source_ref"),
            "sha256": authority.get("source_digest"),
            "revision": authority_provider.get("revision"),
        },
        "provenance": provenance_sources,
    }


def validate_evidence_envelope(
    value: Mapping[str, Any],
    resolver: EvidenceResolver | None = None,
) -> dict[str, Any]:
    """IR-002 hardening over v0.2 without coupling all evidence to repo HEAD.

    The execution receipt remains revision-bound to executed_sha by v0.2. This
    layer closes replay/composition by independently resolving source identity,
    deriving one semantic cross-binding digest, and requiring the same digest
    in every non-structural receipt. Historical immutable source refs remain
    valid when their bytes are still current, preserving contract/currentness
    decoupling from unrelated repository HEAD movement.
    """
    base = v2.validate_evidence_envelope(value, resolver)
    if base.get("status") != PASS:
        return base

    producer_id = str(value.get("producer_id") or "")
    owner = value.get("owner_receipt") or {}
    resolved, owner_record, _owner_provider = v2._resolve_binding(
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

    input_obj = value.get("input") or {}
    input_sources: list[dict[str, Any]] = []
    for index, (ref, digest) in enumerate(
        zip(input_obj.get("source_refs") or [], input_obj.get("source_digests") or [])
    ):
        status, provider = _resolved_source(
            resolver,
            ref,
            digest,
            f"input.source_refs[{index}]",
        )
        if status.get("status") != PASS:
            return status
        input_sources.append(
            {"ref": ref, "sha256": digest, "revision": provider.get("revision")}
        )

    authority = value.get("authority") or {}
    status, authority_provider = _resolved_source(
        resolver,
        authority.get("source_ref"),
        authority.get("source_digest"),
        "authority.source_ref",
    )
    if status.get("status") != PASS:
        return status
    if authority_provider.get("revision") != authority.get("source_revision"):
        return _block(
            "BLOCK_F_AUTHORITY_SOURCE_REVISION_MISMATCH",
            expected=authority.get("source_revision"),
            observed=authority_provider.get("revision"),
        )

    provenance = value.get("provenance") or {}
    provenance_sources: list[dict[str, Any]] = []
    for index, (ref, digest) in enumerate(
        zip(provenance.get("refs") or [], provenance.get("digests") or [])
    ):
        status, provider = _resolved_source(
            resolver,
            ref,
            digest,
            f"provenance.refs[{index}]",
        )
        if status.get("status") != PASS:
            return status
        provenance_sources.append(
            {"ref": ref, "sha256": digest, "revision": provider.get("revision")}
        )

    identity = _cross_binding_identity(
        value,
        input_sources,
        authority_provider,
        provenance_sources,
    )
    expected_cross_binding = _canonical_digest(identity)

    bindings = value.get("resolved_evidence") or {}
    receipts: dict[str, Mapping[str, Any]] = {}
    providers: dict[str, Mapping[str, Any]] = {}
    for key, evidence_type in (
        ("execution_receipt", "EXECUTION_RECEIPT"),
        ("authority_currentness_receipt", "AUTHORITY_CURRENTNESS_RECEIPT"),
        ("provenance_receipt", "PROVENANCE_RECEIPT"),
    ):
        resolved, record, provider = v2._resolve_binding(
            bindings.get(key),
            evidence_type,
            resolver,
            producer_id,
            key,
            require_current_content=True,
        )
        if resolved.get("status") != PASS:
            return resolved
        receipts[key] = record
        providers[key] = provider

    if providers["execution_receipt"].get("revision") != execution_sha:
        return _block(
            "BLOCK_F_EXECUTION_RECEIPT_REVISION_MISMATCH",
            expected=execution_sha,
            observed=providers["execution_receipt"].get("revision"),
        )

    for key, record in receipts.items():
        if record.get("cross_binding_version") != CROSS_BINDING_VERSION:
            return _block(
                "BLOCK_F_CROSS_BINDING_VERSION_MISMATCH",
                binding=key,
                expected=CROSS_BINDING_VERSION,
                observed=record.get("cross_binding_version"),
            )
        if record.get("cross_binding_sha256") != expected_cross_binding:
            return _block(
                "BLOCK_F_CROSS_BINDING_DIGEST_MISMATCH",
                binding=key,
                expected=expected_cross_binding,
                observed=record.get("cross_binding_sha256"),
            )

    return {
        "status": PASS,
        "code": "PASS_F_EVIDENCE_ENVELOPE_V0_3_CROSS_BOUND",
        "cross_binding_sha256": expected_cross_binding,
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
