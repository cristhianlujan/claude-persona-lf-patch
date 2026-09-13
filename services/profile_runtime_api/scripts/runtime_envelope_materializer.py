#!/usr/bin/env python3
"""Materialize Router advisory profile execution into the strict runtime envelope.

The Router remains authority for whether a non-canonical visual artifact may continue.
This bridge only turns that already-authorized read-only decision into the provenance
shape required by the Hetzner runtime. It never upgrades a blocking decision, never
creates canonical screen evidence, and never permits write/promotion semantics.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
from typing import Any

EXPECTED_BINDINGS = {"artifact_ref", "artifact_sha256", "dimensions"}
EXPECTED_CONSTRAINTS = {
    "operation_must_equal": "EJECUCION_PERFIL_LF",
    "read_only": True,
    "no_write": True,
    "no_promotion": True,
    "canonical_registration_required": False,
    "artifact_binding_required_before_profile_execution": True,
}
CODE_RE = re.compile(r"^[A-Z0-9][A-Z0-9_-]{0,119}$")


def canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _runtime_receipt_already_materialized(governance: dict[str, Any]) -> bool:
    return (
        governance.get("current") is True
        and governance.get("ready") is True
        and isinstance(governance.get("receipt_ref"), str)
        and bool(governance.get("receipt_ref"))
        and isinstance(governance.get("context"), dict)
        and isinstance(governance.get("context_sha256"), str)
    )


def _require_router_advisory(governance: dict[str, Any]) -> None:
    if governance.get("subject_mode") != "NON_CANONICAL_ARTIFACT":
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_SUBJECT_MODE_MISMATCH")
    if governance.get("status") != "ADVISORY_READ_ONLY" or governance.get("decision") != "ADVISORY":
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_STATUS_MISMATCH")
    if governance.get("continuation_allowed") is not True:
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_CONTINUATION_NOT_ALLOWED")
    if governance.get("blocking_code") not in (None, ""):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_BLOCKING_CODE_PRESENT")
    constraints = governance.get("constraints")
    if not isinstance(constraints, dict) or any(
        constraints.get(key) != value for key, value in EXPECTED_CONSTRAINTS.items()
    ):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_CONSTRAINTS_INVALID")
    bindings = governance.get("required_artifact_binding")
    if (
        not isinstance(bindings, list)
        or len(bindings) != len(EXPECTED_BINDINGS)
        or set(bindings) != EXPECTED_BINDINGS
    ):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_ARTIFACT_BINDING_INVALID")


def _required_adapter_codes(governance: dict[str, Any]) -> list[str]:
    raw = governance.get("required_by_adapters") or []
    if not isinstance(raw, list) or any(
        not isinstance(item, str) or CODE_RE.fullmatch(item) is None for item in raw
    ):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_REQUIRED_ADAPTERS_INVALID")
    if len(raw) != len(set(raw)):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_REQUIRED_ADAPTERS_DUPLICATE")
    return list(raw)


def materialize_router_advisory_envelope(
    request_id: str,
    envelope: Any,
    *,
    live_adapter_sources: list[dict[str, Any]],
) -> dict[str, Any]:
    """Return a strict runtime envelope or fail closed.

    Canonical-screen envelopes and already-materialized receipts are intentionally
    left untouched. Only the Router's NON_CANONICAL_ARTIFACT advisory contract may
    be wrapped here.
    """
    if not isinstance(envelope, dict):
        raise RuntimeError("HETZNER_REQUEST_ENVELOPE_NOT_OBJECT")
    governance = envelope.get("input_governance")
    if not isinstance(governance, dict):
        return copy.deepcopy(envelope)
    if _runtime_receipt_already_materialized(governance):
        return copy.deepcopy(envelope)
    if governance.get("subject_mode") != "NON_CANONICAL_ARTIFACT":
        return copy.deepcopy(envelope)

    _require_router_advisory(governance)
    if "artifact_set" not in envelope or "artifact" in envelope or "related_artifacts" in envelope:
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_ARTIFACT_SET_REQUIRED")
    artifact_set = envelope.get("artifact_set")
    if not isinstance(artifact_set, dict):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_ARTIFACT_SET_INVALID")
    if artifact_set.get("schema") != "NON_CANONICAL_ARTIFACT_SET_V1" or artifact_set.get("subject_mode") != "NON_CANONICAL_ARTIFACT":
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_ARTIFACT_SET_CONTRACT_INVALID")

    profile = envelope.get("profile")
    if not isinstance(profile, dict) or profile.get("request_id") != request_id:
        raise RuntimeError("HETZNER_REQUEST_ID_ENVELOPE_MISMATCH")
    if profile.get("operation_code") != "EJECUCION_PERFIL_LF":
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_OPERATION_MISMATCH")

    required_adapters = _required_adapter_codes(governance)
    live_by_code = {
        item.get("adapter_code"): item
        for item in live_adapter_sources
        if isinstance(item, dict) and isinstance(item.get("adapter_code"), str)
    }
    missing = sorted(set(required_adapters) - set(live_by_code))
    if missing:
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_ADAPTER_MATERIALIZATION_MISSING:" + ",".join(missing))

    output = copy.deepcopy(envelope)
    context = copy.deepcopy(governance)
    output["input_governance"] = {
        "receipt_ref": f"router://ACT-0001/noncanonical/{request_id}",
        "current": True,
        "ready": True,
        "context_sha256": canonical_json_sha256(context),
        "context": context,
        "status": "ADVISORY_READ_ONLY",
        "canonical_receipt": None,
        "decision": "ADVISORY",
        "subject_mode": "NON_CANONICAL_ARTIFACT",
        "required_artifact_binding": list(governance["required_artifact_binding"]),
        "constraints": copy.deepcopy(governance["constraints"]),
    }

    materialized_profile = output["profile"]
    declared_required = materialized_profile.get("required_adapter_codes")
    if declared_required not in (None, []) and declared_required != required_adapters:
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_REQUIRED_ADAPTERS_MISMATCH")
    materialized_profile["required_adapter_codes"] = required_adapters
    materialized_profile["lf_adapter_sources"] = [live_by_code[code] for code in required_adapters]

    required_cards = materialized_profile.get("required_card_refs") or []
    supplied_cards = materialized_profile.get("lf_card_sources")
    if required_cards and not isinstance(supplied_cards, list):
        raise RuntimeError("HETZNER_ROUTER_ADVISORY_CARD_MATERIALIZATION_REQUIRED")
    materialized_profile.setdefault("required_card_refs", [])
    materialized_profile.setdefault("lf_card_sources", [])
    materialized_profile.setdefault("input_fields", {})
    materialized_profile["send_image_to_model"] = False
    return output
