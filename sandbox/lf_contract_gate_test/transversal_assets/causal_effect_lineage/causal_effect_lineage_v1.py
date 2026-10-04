from __future__ import annotations

import hashlib
import json
import re
from typing import Any

_STATES = {"LINKED", "UNLINKED", "AMBIGUOUS"}
_HEURISTIC_KEYS = {"name", "object_name", "object_ref", "timestamp", "observed_at", "created_at"}
_PII_KEYS = {
    "email", "phone", "mobile", "full_name", "first_name", "last_name", "address",
    "dni", "document_number", "passport", "tax_id", "ruc",
}
_OPAQUE = re.compile(r"^[A-Za-z0-9._:-]{1,160}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _result(state: str, reasons: list[str], edge_digest: str | None = None) -> dict[str, Any]:
    if state not in _STATES:
        raise ValueError("STATE_INVALID")
    return {
        "state": state,
        "reasons": reasons,
        "causal_edge_digest": edge_digest,
        "business_authority": False,
        "execution_permission": False,
    }


def _contains_pii(value: Any) -> bool:
    if isinstance(value, dict):
        for key, nested in value.items():
            if str(key).lower() in _PII_KEYS:
                return True
            if _contains_pii(nested):
                return True
    elif isinstance(value, list):
        return any(_contains_pii(item) for item in value)
    return False


def _identity(value: Any) -> tuple[str, str] | None:
    if not isinstance(value, dict):
        return None
    if set(value) != {"scope", "opaque_id"}:
        return None
    scope = value.get("scope")
    opaque_id = value.get("opaque_id")
    if not isinstance(scope, str) or not isinstance(opaque_id, str):
        return None
    if not _OPAQUE.fullmatch(scope) or not _OPAQUE.fullmatch(opaque_id):
        return None
    return scope, opaque_id


def _receipt(value: Any, role: str) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    receipt_id = value.get("receipt_id")
    receipt_sha = value.get("receipt_sha256")
    verification_state = value.get("verification_state")
    payload = value.get("receipt_payload")
    if (
        not isinstance(receipt_id, str)
        or not _OPAQUE.fullmatch(receipt_id)
        or not isinstance(receipt_sha, str)
        or not _SHA256.fullmatch(receipt_sha)
        or verification_state != "VERIFIED"
        or not isinstance(payload, dict)
        or payload.get("causal_role") != role
    ):
        return None
    return value


def _edge_digest(parent: tuple[str, str], correlation: tuple[str, str], producer_sha: str, receiver_sha: str) -> str:
    canonical = {
        "schema_version": "LF_CAUSAL_EFFECT_EDGE_V1",
        "parent_identity": {"scope": parent[0], "opaque_id": parent[1]},
        "correlation_identity": {"scope": correlation[0], "opaque_id": correlation[1]},
        "producer_receipt_sha256": producer_sha,
        "receiver_effect_receipt_sha256": receiver_sha,
    }
    encoded = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def evaluate_lineage(request: dict[str, Any]) -> dict[str, Any]:
    """Evaluate explicit causal continuity. Heuristic similarity never creates LINKED."""
    if not isinstance(request, dict):
        return _result("UNLINKED", ["REQUEST_INVALID"])
    if _contains_pii(request):
        return _result("UNLINKED", ["PII_NOT_ALLOWED"])

    parent = _identity(request.get("parent_identity"))
    correlation = _identity(request.get("correlation_identity"))
    if parent is None or correlation is None:
        heuristics = sorted(k for k in _HEURISTIC_KEYS if k in request)
        return _result("UNLINKED", ["EXPLICIT_IDENTITY_REQUIRED"] + (["HEURISTIC_ONLY_INSUFFICIENT"] if heuristics else []))

    provenance = request.get("provenance")
    currentness = request.get("currentness")
    if not isinstance(provenance, dict) or not isinstance(currentness, dict):
        return _result("UNLINKED", ["PROVENANCE_OR_CURRENTNESS_MISSING"])
    if provenance.get("boundary") not in {"SYNC", "ASYNC_EVENT", "ASYNC_QUEUE", "ASYNC_JOB"}:
        return _result("UNLINKED", ["BOUNDARY_PROVENANCE_INVALID"])
    if not all(isinstance(provenance.get(k), str) and _OPAQUE.fullmatch(provenance[k]) for k in ("producer", "receiver", "authority_ref")):
        return _result("UNLINKED", ["PROVENANCE_INVALID"])
    if any(currentness.get(k) != "CURRENT" for k in ("producer", "receiver", "correlation")):
        return _result("UNLINKED", ["CURRENTNESS_NOT_PROVEN"])

    producer = _receipt(request.get("producer_receipt"), "PRODUCER")
    receiver = _receipt(request.get("receiver_effect_receipt"), "RECEIVER_EFFECT")
    readback = request.get("receiver_readback")
    if producer is None or receiver is None or not isinstance(readback, dict):
        return _result("UNLINKED", ["PRODUCER_RECEIPT_RECEIVER_RECEIPT_AND_READBACK_REQUIRED"])

    pp = producer["receipt_payload"]
    rp = receiver["receipt_payload"]
    p_parent = _identity(pp.get("parent_identity"))
    p_corr = _identity(pp.get("correlation_identity"))
    r_parent = _identity(rp.get("parent_identity"))
    r_corr = _identity(rp.get("correlation_identity"))

    explicit_sets = {x for x in (p_parent, r_parent) if x is not None}
    correlation_sets = {x for x in (p_corr, r_corr) if x is not None}
    if len(explicit_sets) > 1 or len(correlation_sets) > 1:
        return _result("AMBIGUOUS", ["CONFLICTING_EXPLICIT_RECEIPT_IDENTITIES"])
    if p_parent != parent or r_parent != parent or p_corr != correlation or r_corr != correlation:
        return _result("UNLINKED", ["RECEIPT_IDENTITY_MISMATCH"])

    producer_sha = producer["receipt_sha256"]
    receiver_sha = receiver["receipt_sha256"]
    if rp.get("producer_receipt_sha256") != producer_sha:
        return _result("UNLINKED", ["RECEIVER_DOES_NOT_CROSSLINK_PRODUCER"])
    if pp.get("currentness") != "CURRENT" or rp.get("currentness") != "CURRENT":
        return _result("UNLINKED", ["RECEIPT_CURRENTNESS_NOT_PROVEN"])

    effect_ref = rp.get("effect_ref")
    if not isinstance(effect_ref, str) or not _OPAQUE.fullmatch(effect_ref):
        return _result("UNLINKED", ["RECEIVER_EFFECT_REF_INVALID"])
    if (
        readback.get("observed") is not True
        or readback.get("currentness") != "CURRENT"
        or readback.get("effect_ref") != effect_ref
        or readback.get("receiver_receipt_sha256") != receiver_sha
    ):
        return _result("UNLINKED", ["RECEIVER_EFFECT_READBACK_NOT_PROVEN"])

    digest = _edge_digest(parent, correlation, producer_sha, receiver_sha)
    return _result("LINKED", ["EXPLICIT_CAUSAL_EDGE_AND_RECEIVER_READBACK_VERIFIED"], digest)
