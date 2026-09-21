#!/usr/bin/env python3
"""Shared deterministic closure-proof helpers for SRCR V0.3.

This module is deliberately local and network-free. It validates consistency
between a V0.3 candidate and an evidence manifest already resolved by the
existing source-first execution/quality boundary. It is not a semantic judge
and cannot issue canonical quality acceptance.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from typing import Any

V03_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
EXISTING_AUTHORITY = "EXISTING_AUTHORITY"
CLOSURE_V1 = "SRCR_CLOSURE_PROOF_V1"
CLOSURE_V2 = "SRCR_CLOSURE_PROOF_V2"

_VOCAB_PATH = Path(__file__).resolve().parents[1] / "contracts" / "closure_vocabulary.v2.json"
_VOCAB = json.loads(_VOCAB_PATH.read_text(encoding="utf-8"))

PROOF_PHASES = set(_VOCAB["proof_phases"])
SPEC_BLOCKING_PHASES = set(_VOCAB["spec_blocking_phases"])
CURRENT_AUTHORITY_EVIDENCE_CLASSES = set(_VOCAB["current_authority_evidence_classes"])
CURRENT_WIRING_EVIDENCE_CLASSES = set(_VOCAB["current_wiring_evidence_classes"])
CURRENT_WIRING_ABSENCE_EVIDENCE_CLASSES = set(_VOCAB["current_wiring_absence_evidence_classes"])
RECURRENCE_EVIDENCE_CLASSES = set(_VOCAB["recurrence_evidence_classes"])
OMISSION_DIMENSIONS = set(_VOCAB["omission_dimensions"])
SOLUTION_DEPTH_SIGNALS = set(_VOCAB["solution_depth_signals"])
CLOSURE_MATERIALITY_SIGNALS = set(_VOCAB["closure_materiality_signals"])
SIGNAL_TO_OBLIGATION_TYPES = {
    key: set(values) for key, values in _VOCAB["signal_to_obligation_types"].items()
}
DIMENSION_TO_OBLIGATION_TYPES = {
    key: set(SIGNAL_TO_OBLIGATION_TYPES[key]) for key in _VOCAB["omission_dimensions"]
}

BASELINE_REQUIRED_TYPES = {
    "AUTHORITY_EXISTENCE",
    "DECISION_CLOSURE",
    "EVIDENCE_PROVENANCE",
}


def _err(code: str, path: str = "$", message: str = "") -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def _canonical_digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def canonical_candidate_digest(candidate: dict) -> str:
    # Exact identity is derived from final candidate bytes/structure by the
    # deterministic quality boundary. The producer does not self-bind a digest.
    return _canonical_digest(candidate)


def canonical_evidence_bundle_digest(manifest: dict) -> str:
    normalized = copy.deepcopy(manifest)
    if isinstance(normalized, dict):
        normalized.pop("bundle_digest", None)
    return _canonical_digest(normalized)


def derive_required_obligation_types(candidate: dict) -> tuple[set[str], set[str]]:
    """Derive generic proof requirements from materiality, never from domain literals."""
    required = set(BASELINE_REQUIRED_TYPES)
    material_signals = {"DECISION_CLOSURE", "EVIDENCE_PROVENANCE"}
    proof = candidate.get("closure_proof") if isinstance(candidate, dict) else {}
    is_v2 = isinstance(proof, dict) and proof.get("contract_version") == CLOSURE_V2

    depth = candidate.get("solution_depth")
    signals = depth.get("complexity_signals") if isinstance(depth, dict) else []
    if isinstance(signals, list):
        for signal in signals:
            if signal == "NONE":
                continue
            if isinstance(signal, str):
                material_signals.add(signal)
                required.update(SIGNAL_TO_OBLIGATION_TYPES.get(signal, {"OTHER_MATERIAL"}))

    omissions = candidate.get("omission_discovery")
    if isinstance(omissions, list):
        for row in omissions:
            if not isinstance(row, dict) or row.get("disposition") != "REQUIRED_CHANGE":
                continue
            dimension = row.get("dimension")
            required.update(DIMENSION_TO_OBLIGATION_TYPES.get(dimension, {"OTHER_MATERIAL"}))
            # V2 makes every REQUIRED_CHANGE dimension explicit materiality.
            # V1 keeps its historical contract, where only WIRING was promoted.
            if is_v2 and dimension in CLOSURE_MATERIALITY_SIGNALS:
                material_signals.add(dimension)
            elif dimension == "WIRING":
                material_signals.add("WIRING")

    return required, material_signals


def _current_evidence_ok(evidence_by_id: dict[str, dict], evidence_ids: list[str], allowed_classes: set[str]) -> bool:
    return bool(evidence_ids) and all(
        evidence_by_id.get(eid, {}).get("state") == "CURRENT"
        and evidence_by_id.get(eid, {}).get("evidence_class") in allowed_classes
        for eid in evidence_ids
    )


def _wiring_current_state_complete(row: dict, evidence_by_id: dict[str, dict]) -> bool:
    state = row.get("binding_state")
    if state == "OBSERVED_WIRED":
        return (
            row.get("binding_kind") in {"EXISTING_AUTHORITY", "EXISTING_REUSABLE_CAPABILITY"}
            and _current_evidence_ok(
                evidence_by_id,
                row.get("evidence_ids") or [],
                CURRENT_WIRING_EVIDENCE_CLASSES,
            )
        )
    if state == "OBSERVED_NOT_WIRED":
        return (
            row.get("binding_kind") == "NO_BINDING"
            and _current_evidence_ok(
                evidence_by_id,
                row.get("evidence_ids") or [],
                CURRENT_WIRING_ABSENCE_EVIDENCE_CLASSES,
            )
        )
    return False


def _wiring_design_complete(row: dict, evidence_by_id: dict[str, dict]) -> bool:
    if row.get("binding_state") == "PROPOSED_WIRING":
        return (
            row.get("binding_kind") == "PROPOSED_DELIVERABLE"
            and all(
                isinstance(row.get(key), str) and row.get(key).strip()
                for key in (
                    "producer_ref",
                    "data_contract_ref",
                    "consumer_ref",
                    "enforcement_point_ref",
                    "failure_behavior",
                    "binding_ref",
                )
            )
        )
    # Reusing a physically observed current edge is also a closed repair-design choice.
    return _wiring_current_state_complete(row, evidence_by_id) and row.get("binding_state") == "OBSERVED_WIRED"


def _validate_manifest_shape(manifest: Any) -> tuple[list[dict], dict[str, dict]]:
    errors: list[dict] = []
    evidence_by_id: dict[str, dict] = {}
    if not isinstance(manifest, dict):
        return [_err("SRCR_EVIDENCE_MANIFEST_REQUIRED", "$.evidence_manifest")], evidence_by_id

    if manifest.get("manifest_version") != "SRCR_EVIDENCE_MANIFEST_V1":
        errors.append(_err("SRCR_EVIDENCE_MANIFEST_VERSION_INVALID", "$.evidence_manifest.manifest_version"))

    allowed_root = {
        "manifest_version", "bundle_id", "bundle_digest", "observed_at", "producer", "evidence"
    }
    for forbidden in ("candidate_revision", "candidate_digest"):
        if forbidden in manifest:
            errors.append(
                _err(
                    "SRCR_EVIDENCE_MANIFEST_CANDIDATE_SELF_BINDING_FORBIDDEN",
                    f"$.evidence_manifest.{forbidden}",
                )
            )
    for extra in sorted(set(manifest) - allowed_root - {"candidate_revision", "candidate_digest"}):
        errors.append(_err("SRCR_EVIDENCE_MANIFEST_FIELD_UNDECLARED", f"$.evidence_manifest.{extra}"))
    for key in ("bundle_id", "bundle_digest", "observed_at"):
        if not isinstance(manifest.get(key), str) or not manifest.get(key).strip():
            errors.append(_err("SRCR_EVIDENCE_MANIFEST_FIELD_REQUIRED", f"$.evidence_manifest.{key}"))

    producer = manifest.get("producer")
    if not isinstance(producer, dict) or not producer.get("kind") or not producer.get("resolver_ref"):
        errors.append(_err("SRCR_EVIDENCE_MANIFEST_PRODUCER_INVALID", "$.evidence_manifest.producer"))

    rows = manifest.get("evidence")
    if not isinstance(rows, list) or not rows:
        errors.append(_err("SRCR_EVIDENCE_MANIFEST_EMPTY", "$.evidence_manifest.evidence"))
        return errors, evidence_by_id

    for idx, row in enumerate(rows):
        path = f"$.evidence_manifest.evidence[{idx}]"
        if not isinstance(row, dict):
            errors.append(_err("SRCR_EVIDENCE_ENTRY_INVALID", path))
            continue
        eid = row.get("evidence_id")
        if not isinstance(eid, str) or not eid.strip():
            errors.append(_err("SRCR_EVIDENCE_ID_REQUIRED", f"{path}.evidence_id"))
            continue
        if eid in evidence_by_id:
            errors.append(_err("SRCR_EVIDENCE_ID_DUPLICATED", f"{path}.evidence_id", eid))
        else:
            evidence_by_id[eid] = row
        for key in ("subject", "evidence_class", "source_locator", "revision_or_observed_at", "digest", "state"):
            if not isinstance(row.get(key), str) or not row.get(key).strip():
                errors.append(_err("SRCR_EVIDENCE_ENTRY_FIELD_REQUIRED", f"{path}.{key}"))

    expected = canonical_evidence_bundle_digest(manifest)
    if manifest.get("bundle_digest") != expected:
        errors.append(_err("SRCR_EVIDENCE_BUNDLE_DIGEST_MISMATCH", "$.evidence_manifest.bundle_digest", expected))
    return errors, evidence_by_id


def validate_v03_closure(candidate: Any, evidence_manifest: Any) -> tuple[list[dict], dict]:
    """Validate V0.3 closure proof and return errors plus derived summary."""
    if not isinstance(candidate, dict) or candidate.get("profile_pack_id") != V03_PACK_ID:
        return [], {"applies": False}

    errors, evidence_by_id = _validate_manifest_shape(evidence_manifest)
    proof = candidate.get("closure_proof")
    if not isinstance(proof, dict):
        errors.append(_err("SRCR_CLOSURE_PROOF_REQUIRED", "$.closure_proof"))
        return errors, {"applies": True}

    contract_version = proof.get("contract_version")
    if contract_version not in {CLOSURE_V1, CLOSURE_V2}:
        errors.append(_err("SRCR_CLOSURE_CONTRACT_VERSION_INVALID", "$.closure_proof.contract_version"))
    is_v2 = contract_version == CLOSURE_V2

    # Candidate and evidence exact identity are external-boundary facts. A V0.3
    # producer must not self-certify candidate/evidence digests inside its output.
    if "candidate_binding" in proof:
        errors.append(
            _err(
                "SRCR_CANDIDATE_SELF_BINDING_FORBIDDEN",
                "$.closure_proof.candidate_binding",
            )
        )

    actual_candidate_digest = canonical_candidate_digest(candidate)

    required_types, system_material_signals = derive_required_obligation_types(candidate)

    obligations = proof.get("proof_obligations")
    if not isinstance(obligations, list):
        obligations = []
        errors.append(_err("SRCR_PROOF_OBLIGATIONS_REQUIRED", "$.closure_proof.proof_obligations"))

    obligation_by_id: dict[str, dict] = {}
    for idx, row in enumerate(obligations):
        path = f"$.closure_proof.proof_obligations[{idx}]"
        if not isinstance(row, dict):
            errors.append(_err("SRCR_PROOF_OBLIGATION_INVALID", path))
            continue
        oid = row.get("obligation_id")
        if not isinstance(oid, str) or not oid.strip():
            errors.append(_err("SRCR_PROOF_OBLIGATION_ID_REQUIRED", f"{path}.obligation_id"))
            continue
        if is_v2:
            phase = row.get("proof_phase")
            if phase not in PROOF_PHASES:
                errors.append(_err("SRCR_PROOF_PHASE_REQUIRED", f"{path}.proof_phase"))
        if oid in obligation_by_id:
            errors.append(_err("SRCR_PROOF_OBLIGATION_ID_DUPLICATED", f"{path}.obligation_id", oid))
        else:
            obligation_by_id[oid] = row

    present_types = {
        row.get("obligation_type")
        for row in obligation_by_id.values()
        if not is_v2 or row.get("proof_phase") in SPEC_BLOCKING_PHASES
    }
    for required_type in sorted(required_types - present_types):
        errors.append(_err("SRCR_REQUIRED_PROOF_OBLIGATION_MISSING", "$.closure_proof.proof_obligations", required_type))

    materiality = proof.get("materiality")
    materiality_by_signal: dict[str, dict] = {}
    if not isinstance(materiality, list):
        errors.append(_err("SRCR_MATERIALITY_REQUIRED", "$.closure_proof.materiality"))
        materiality = []
    for idx, row in enumerate(materiality):
        if not isinstance(row, dict) or not isinstance(row.get("signal"), str):
            errors.append(_err("SRCR_MATERIALITY_ROW_INVALID", f"$.closure_proof.materiality[{idx}]"))
            continue
        signal = row["signal"]
        if signal in materiality_by_signal:
            errors.append(_err("SRCR_MATERIALITY_SIGNAL_DUPLICATED", f"$.closure_proof.materiality[{idx}].signal", signal))
        materiality_by_signal[signal] = row
        if row.get("material") is True:
            for oid in row.get("obligation_ids") or []:
                obligation = obligation_by_id.get(oid)
                if not obligation:
                    errors.append(_err("SRCR_MATERIALITY_OBLIGATION_REF_MISSING", f"$.closure_proof.materiality[{idx}].obligation_ids", oid))
                elif signal not in (obligation.get("derived_from") or []):
                    errors.append(_err("SRCR_MATERIALITY_DERIVATION_MISMATCH", f"$.closure_proof.proof_obligations[{oid}].derived_from", signal))

    for signal in sorted(system_material_signals):
        row = materiality_by_signal.get(signal)
        if not isinstance(row, dict) or row.get("material") is not True:
            errors.append(_err("SRCR_SYSTEM_MATERIALITY_NOT_DECLARED", "$.closure_proof.materiality", signal))

    # Every proof evidence ID must resolve to current external evidence.
    referenced_evidence: set[str] = set()
    for oid, row in obligation_by_id.items():
        for eid in row.get("evidence_ids") or []:
            referenced_evidence.add(eid)
            entry = evidence_by_id.get(eid)
            if not entry:
                errors.append(_err("SRCR_PROOF_EVIDENCE_ID_UNRESOLVED", f"$.closure_proof.proof_obligations[{oid}].evidence_ids", eid))
            elif entry.get("state") != "CURRENT":
                errors.append(_err("SRCR_PROOF_EVIDENCE_STALE", f"$.closure_proof.proof_obligations[{oid}].evidence_ids", eid))

    authority_bindings = proof.get("authority_bindings")
    if not isinstance(authority_bindings, list):
        authority_bindings = []
        errors.append(_err("SRCR_AUTHORITY_BINDINGS_REQUIRED", "$.closure_proof.authority_bindings"))

    for idx, row in enumerate(authority_bindings):
        path = f"$.closure_proof.authority_bindings[{idx}]"
        if not isinstance(row, dict):
            errors.append(_err("SRCR_AUTHORITY_BINDING_INVALID", path))
            continue
        if row.get("used_as_existing_authority") is True and row.get("authority_kind") != EXISTING_AUTHORITY:
            errors.append(_err("SRCR_PROPOSED_DELIVERABLE_AS_EXISTING_AUTHORITY", f"{path}.authority_kind"))
        for eid in row.get("evidence_ids") or []:
            referenced_evidence.add(eid)
            entry = evidence_by_id.get(eid)
            if not entry:
                errors.append(_err("SRCR_AUTHORITY_EVIDENCE_ID_UNRESOLVED", f"{path}.evidence_ids", eid))
            elif entry.get("state") != "CURRENT":
                errors.append(_err("SRCR_AUTHORITY_EVIDENCE_STALE", f"{path}.evidence_ids", eid))
            elif row.get("used_as_existing_authority") is True and entry.get("evidence_class") not in CURRENT_AUTHORITY_EVIDENCE_CLASSES:
                errors.append(_err("SRCR_AUTHORITY_EVIDENCE_CLASS_INSUFFICIENT", f"{path}.evidence_ids", eid))

    # Origin authority slots must be current existing authority and bind exact evidence subjects.
    for field in ("origin_asset", "origin_operation", "owner"):
        value = candidate.get(field)
        path = f"$.{field}"
        if not isinstance(value, dict):
            errors.append(_err("SRCR_EXISTING_AUTHORITY_SLOT_INVALID", path))
            continue
        if value.get("status") != "RESOLVED" or value.get("authority_kind") != EXISTING_AUTHORITY:
            errors.append(_err("SRCR_EXISTING_AUTHORITY_REQUIRED", path))
            continue
        eid = value.get("evidence_id")
        entry = evidence_by_id.get(eid)
        if not entry:
            errors.append(_err("SRCR_EXISTING_AUTHORITY_EVIDENCE_UNRESOLVED", f"{path}.evidence_id"))
            continue
        expected_subject = value.get("subject") or value.get("code")
        if entry.get("subject") != expected_subject:
            errors.append(_err("SRCR_EXISTING_AUTHORITY_SUBJECT_MISMATCH", f"{path}.evidence_id", str(expected_subject)))
        if entry.get("state") != "CURRENT":
            errors.append(_err("SRCR_EXISTING_AUTHORITY_EVIDENCE_STALE", f"{path}.evidence_id"))
        if entry.get("evidence_class") not in CURRENT_AUTHORITY_EVIDENCE_CLASSES:
            errors.append(_err("SRCR_EXISTING_AUTHORITY_EVIDENCE_CLASS_INSUFFICIENT", f"{path}.evidence_id"))

    # Material state/migration must have executable behavioral proof for the exact signal.
    behavior = proof.get("behavioral_proofs") if isinstance(proof.get("behavioral_proofs"), list) else []
    complexity = candidate.get("solution_depth", {}).get("complexity_signals", []) if isinstance(candidate.get("solution_depth"), dict) else []
    for signal in ("STATE_RECOVERY", "MIGRATION_TRANSITION"):
        if signal in complexity and not any(isinstance(x, dict) and x.get("materiality_signal") == signal for x in behavior):
            errors.append(_err("SRCR_MATERIAL_BEHAVIOR_UNDERCLOSED", "$.closure_proof.behavioral_proofs", signal))

    wiring = proof.get("wiring_proofs") if isinstance(proof.get("wiring_proofs"), list) else []
    wiring_by_obligation: dict[str, list[dict]] = {}
    wiring_by_edge: dict[str, dict] = {}
    for idx, row in enumerate(wiring):
        path = f"$.closure_proof.wiring_proofs[{idx}]"
        if not isinstance(row, dict):
            errors.append(_err("SRCR_WIRING_PROOF_INVALID", path))
            continue
        edge_id = row.get("edge_id")
        if isinstance(edge_id, str) and edge_id:
            if edge_id in wiring_by_edge:
                errors.append(_err("SRCR_WIRING_EDGE_ID_DUPLICATED", f"{path}.edge_id", edge_id))
            else:
                wiring_by_edge[edge_id] = row
        for oid in row.get("obligation_ids") or []:
            obligation = obligation_by_id.get(oid)
            if not obligation:
                errors.append(_err("SRCR_WIRING_OBLIGATION_REF_MISSING", f"{path}.obligation_ids", oid))
                continue
            if obligation.get("obligation_type") != "WIRING_PHYSICALITY":
                errors.append(_err("SRCR_WIRING_OBLIGATION_TYPE_MISMATCH", f"{path}.obligation_ids", oid))
                continue
            wiring_by_obligation.setdefault(oid, []).append(row)
        state = row.get("binding_state")
        kind = row.get("binding_kind")
        if state == "OBSERVED_WIRED" and kind not in {"EXISTING_AUTHORITY", "EXISTING_REUSABLE_CAPABILITY"}:
            errors.append(_err("SRCR_OBSERVED_WIRING_KIND_INVALID", f"{path}.binding_kind"))
        if state == "OBSERVED_NOT_WIRED" and kind != "NO_BINDING":
            errors.append(_err("SRCR_OBSERVED_WIRING_ABSENCE_KIND_INVALID", f"{path}.binding_kind"))
        if state == "PROPOSED_WIRING" and kind != "PROPOSED_DELIVERABLE":
            errors.append(_err("SRCR_PROPOSED_WIRING_KIND_INVALID", f"{path}.binding_kind"))
        for eid in row.get("evidence_ids") or []:
            referenced_evidence.add(eid)
            entry = evidence_by_id.get(eid)
            if not entry:
                errors.append(_err("SRCR_WIRING_EVIDENCE_ID_UNRESOLVED", f"{path}.evidence_ids", eid))
            elif entry.get("state") != "CURRENT":
                errors.append(_err("SRCR_WIRING_EVIDENCE_STALE", f"{path}.evidence_ids", eid))
            elif state == "OBSERVED_WIRED" and entry.get("evidence_class") not in CURRENT_WIRING_EVIDENCE_CLASSES:
                errors.append(_err("SRCR_WIRING_EVIDENCE_CLASS_INSUFFICIENT", f"{path}.evidence_ids", eid))
            elif state == "OBSERVED_NOT_WIRED" and entry.get("evidence_class") not in CURRENT_WIRING_ABSENCE_EVIDENCE_CLASSES:
                errors.append(_err("SRCR_WIRING_ABSENCE_EVIDENCE_CLASS_INSUFFICIENT", f"{path}.evidence_ids", eid))

    wiring_required_ids = {
        oid for oid, row in obligation_by_id.items()
        if row.get("obligation_type") == "WIRING_PHYSICALITY"
        and row.get("obligation_type") in required_types
        and (not is_v2 or row.get("proof_phase") in SPEC_BLOCKING_PHASES)
    }
    wiring_closed_post_ids = {
        oid for oid, row in obligation_by_id.items()
        if is_v2
        and row.get("obligation_type") == "WIRING_PHYSICALITY"
        and row.get("proof_phase") == "POST_IMPLEMENTATION"
        and row.get("status") == "CLOSED"
    }
    if wiring_required_ids and not wiring:
        errors.append(_err("SRCR_MATERIAL_WIRING_UNDERCLOSED", "$.closure_proof.wiring_proofs"))
    for oid in sorted(wiring_required_ids | wiring_closed_post_ids):
        obligation = obligation_by_id[oid]
        if obligation.get("status") != "CLOSED":
            continue
        rows = wiring_by_obligation.get(oid, [])

        if not is_v2:
            complete = any(
                row.get("binding_state") == "OBSERVED_WIRED"
                and _wiring_current_state_complete(row, evidence_by_id)
                for row in rows
            )
            if not complete:
                errors.append(
                    _err(
                        "SRCR_CLOSED_WIRING_NOT_OBSERVED",
                        "$.closure_proof.wiring_proofs",
                        oid,
                    )
                )
            continue

        phase = obligation.get("proof_phase")
        if phase == "CURRENT_STATE":
            complete = any(_wiring_current_state_complete(row, evidence_by_id) for row in rows)
            code = "SRCR_CURRENT_STATE_WIRING_NOT_PROVEN"
        elif phase == "REPAIR_DESIGN":
            complete = any(_wiring_design_complete(row, evidence_by_id) for row in rows)
            code = "SRCR_REPAIR_DESIGN_WIRING_NOT_CLOSED"
        else:
            # POST_IMPLEMENTATION may remain OPEN without blocking the repair spec.
            complete = any(
                row.get("binding_state") == "OBSERVED_WIRED"
                and _wiring_current_state_complete(row, evidence_by_id)
                for row in rows
            )
            code = "SRCR_POST_IMPLEMENTATION_WIRING_NOT_OBSERVED"

        if not complete:
            errors.append(_err(code, "$.closure_proof.wiring_proofs", oid))

    transport = proof.get("context_transport_proofs") if isinstance(proof.get("context_transport_proofs"), list) else []
    transport_by_obligation: dict[str, list[dict]] = {}
    for idx, row in enumerate(transport):
        path = f"$.closure_proof.context_transport_proofs[{idx}]"
        if not isinstance(row, dict):
            errors.append(_err("SRCR_CONTEXT_TRANSPORT_PROOF_INVALID", path))
            continue
        required_fields = (
            "transport_id", "selection_ref", "transport_contract_ref", "consumer_ref",
            "enforcement_point_ref", "budget_guard_ref", "failure_behavior"
        )
        for field in required_fields:
            if not isinstance(row.get(field), str) or not row.get(field).strip():
                errors.append(_err("SRCR_CONTEXT_TRANSPORT_FIELD_REQUIRED", f"{path}.{field}"))
        if row.get("hydration_mode") == "JIT_BY_REF" and not (
            isinstance(row.get("hydration_resolver_ref"), str)
            and row.get("hydration_resolver_ref").strip()
        ):
            errors.append(_err("SRCR_CONTEXT_JIT_RESOLVER_MISSING", f"{path}.hydration_resolver_ref"))
        for edge_id in row.get("wiring_edge_ids") or []:
            if edge_id not in wiring_by_edge:
                errors.append(_err("SRCR_CONTEXT_WIRING_EDGE_UNRESOLVED", f"{path}.wiring_edge_ids", edge_id))
        for oid in row.get("obligation_ids") or []:
            obligation = obligation_by_id.get(oid)
            if not obligation:
                errors.append(_err("SRCR_CONTEXT_OBLIGATION_REF_MISSING", f"{path}.obligation_ids", oid))
                continue
            if obligation.get("obligation_type") != "CONTEXT_TRANSPORT":
                errors.append(_err("SRCR_CONTEXT_OBLIGATION_TYPE_MISMATCH", f"{path}.obligation_ids", oid))
                continue
            transport_by_obligation.setdefault(oid, []).append(row)
        for eid in row.get("readback_evidence_ids") or []:
            referenced_evidence.add(eid)
            entry = evidence_by_id.get(eid)
            if not entry:
                errors.append(_err("SRCR_CONTEXT_READBACK_EVIDENCE_UNRESOLVED", f"{path}.readback_evidence_ids", eid))
            elif entry.get("state") != "CURRENT":
                errors.append(_err("SRCR_CONTEXT_READBACK_EVIDENCE_STALE", f"{path}.readback_evidence_ids", eid))
            elif entry.get("evidence_class") not in CURRENT_WIRING_EVIDENCE_CLASSES:
                errors.append(_err("SRCR_CONTEXT_READBACK_EVIDENCE_CLASS_INSUFFICIENT", f"{path}.readback_evidence_ids", eid))

    context_required_ids = {
        oid for oid, row in obligation_by_id.items()
        if row.get("obligation_type") == "CONTEXT_TRANSPORT"
        and row.get("obligation_type") in required_types
        and (not is_v2 or row.get("proof_phase") in SPEC_BLOCKING_PHASES)
    }
    context_closed_post_ids = {
        oid for oid, row in obligation_by_id.items()
        if is_v2
        and row.get("obligation_type") == "CONTEXT_TRANSPORT"
        and row.get("proof_phase") == "POST_IMPLEMENTATION"
        and row.get("status") == "CLOSED"
    }

    def _transport_shape_complete(row: dict) -> bool:
        return (
            bool(row.get("selection_ref"))
            and bool(row.get("transport_contract_ref"))
            and bool(row.get("consumer_ref"))
            and bool(row.get("enforcement_point_ref"))
            and bool(row.get("budget_guard_ref"))
            and bool(row.get("failure_behavior"))
            and bool(row.get("wiring_edge_ids"))
            and (
                row.get("hydration_mode") != "JIT_BY_REF"
                or bool(row.get("hydration_resolver_ref"))
            )
        )

    def _transport_current_complete(row: dict) -> bool:
        return (
            _transport_shape_complete(row)
            and bool(row.get("readback_evidence_ids"))
            and all(
                wiring_by_edge.get(edge_id, {}).get("binding_state") == "OBSERVED_WIRED"
                and _wiring_current_state_complete(wiring_by_edge.get(edge_id, {}), evidence_by_id)
                for edge_id in row.get("wiring_edge_ids") or []
            )
            and _current_evidence_ok(
                evidence_by_id,
                row.get("readback_evidence_ids") or [],
                CURRENT_WIRING_EVIDENCE_CLASSES,
            )
        )

    def _transport_design_complete(row: dict) -> bool:
        return (
            _transport_shape_complete(row)
            and all(
                wiring_by_edge.get(edge_id, {}).get("binding_state") in {"OBSERVED_WIRED", "PROPOSED_WIRING"}
                and (
                    _wiring_design_complete(wiring_by_edge.get(edge_id, {}), evidence_by_id)
                    or _wiring_current_state_complete(wiring_by_edge.get(edge_id, {}), evidence_by_id)
                )
                for edge_id in row.get("wiring_edge_ids") or []
            )
        )

    for oid in sorted(context_required_ids | context_closed_post_ids):
        obligation = obligation_by_id[oid]
        if obligation.get("status") != "CLOSED":
            continue
        rows = transport_by_obligation.get(oid, [])

        if not is_v2:
            complete = any(_transport_current_complete(row) for row in rows)
            code = "SRCR_CLOSED_CONTEXT_TRANSPORT_NOT_PROVEN"
        elif obligation.get("proof_phase") == "CURRENT_STATE":
            complete = any(_transport_current_complete(row) for row in rows)
            code = "SRCR_CURRENT_CONTEXT_TRANSPORT_NOT_PROVEN"
        elif obligation.get("proof_phase") == "REPAIR_DESIGN":
            complete = any(_transport_design_complete(row) for row in rows)
            code = "SRCR_REPAIR_DESIGN_CONTEXT_TRANSPORT_NOT_CLOSED"
        else:
            complete = any(_transport_current_complete(row) for row in rows)
            code = "SRCR_POST_IMPLEMENTATION_CONTEXT_TRANSPORT_NOT_OBSERVED"

        if not complete:
            errors.append(_err(code, "$.closure_proof.context_transport_proofs", oid))

    required_ids = {
        oid for oid, row in obligation_by_id.items()
        if row.get("obligation_type") in required_types
        and (not is_v2 or row.get("proof_phase") in SPEC_BLOCKING_PHASES)
    }
    post_implementation_ids = {
        oid for oid, row in obligation_by_id.items()
        if is_v2 and row.get("proof_phase") == "POST_IMPLEMENTATION"
    }
    closed_ids = {oid for oid in required_ids if obligation_by_id[oid].get("status") == "CLOSED"}
    open_ids = required_ids - closed_ids

    # V2 explicitly separates post-implementation verification from spec readiness.
    any_open_ids = {
        oid for oid, row in obligation_by_id.items()
        if row.get("status") == "OPEN"
        and (not is_v2 or row.get("proof_phase") in SPEC_BLOCKING_PHASES)
    }

    derived = proof.get("derived_decision_closure")
    if not isinstance(derived, dict):
        errors.append(_err("SRCR_DERIVED_CLOSURE_REQUIRED", "$.closure_proof.derived_decision_closure"))
        derived = {}

    declared_required = set(derived.get("required_obligation_ids") or [])
    declared_closed = set(derived.get("closed_obligation_ids") or [])
    declared_open = set(derived.get("open_obligation_ids") or [])

    if declared_required != required_ids:
        errors.append(_err("SRCR_DERIVED_REQUIRED_SET_MISMATCH", "$.closure_proof.derived_decision_closure.required_obligation_ids"))
    if declared_closed != closed_ids:
        errors.append(_err("SRCR_DERIVED_CLOSED_SET_MISMATCH", "$.closure_proof.derived_decision_closure.closed_obligation_ids"))
    if declared_open != open_ids:
        errors.append(_err("SRCR_DERIVED_OPEN_SET_MISMATCH", "$.closure_proof.derived_decision_closure.open_obligation_ids"))

    if is_v2:
        declared_post = set(derived.get("post_implementation_obligation_ids") or [])
        if declared_post != post_implementation_ids:
            errors.append(_err("SRCR_DERIVED_POST_IMPLEMENTATION_SET_MISMATCH", "$.closure_proof.derived_decision_closure.post_implementation_obligation_ids"))

    computed_ready = bool(required_ids) and not open_ids and not any_open_ids
    if derived.get("handoff_ready") is not computed_ready:
        errors.append(_err("SRCR_HANDOFF_READY_NOT_DERIVED", "$.closure_proof.derived_decision_closure.handoff_ready"))

    package = candidate.get("implementation_package")
    decision_closure = package.get("decision_closure") if isinstance(package, dict) else {}
    if isinstance(decision_closure, dict):
        if decision_closure.get("handoff_ready") is not computed_ready:
            errors.append(_err("SRCR_IMPLEMENTATION_HANDOFF_READY_NOT_DERIVED", "$.implementation_package.decision_closure.handoff_ready"))
        if computed_ready and decision_closure.get("open_design_decisions") != []:
            errors.append(_err("SRCR_READY_WITH_OPEN_DESIGN_DECISIONS", "$.implementation_package.decision_closure.open_design_decisions"))

    if candidate.get("status") == "SYSTEMIC_REPAIR_SPEC":
        if open_ids or any_open_ids:
            errors.append(_err("SRCR_CLOSURE_PROOF_INCOMPLETE", "$.closure_proof.proof_obligations"))
        if not computed_ready:
            errors.append(_err("SRCR_SYSTEMIC_SPEC_NOT_DERIVED_READY", "$.closure_proof.derived_decision_closure"))
        if derived.get("quality_state") != "QUALITY_PENDING":
            errors.append(_err("SRCR_UTILITY_CANNOT_CLAIM_QUALITY_ACCEPTANCE", "$.closure_proof.derived_decision_closure.quality_state"))

    summary = {
        "applies": True,
        "required_obligation_types": sorted(required_types),
        "required_obligation_ids": sorted(required_ids),
        "closed_obligation_ids": sorted(closed_ids),
        "open_obligation_ids": sorted(open_ids | any_open_ids),
        "post_implementation_obligation_ids": sorted(post_implementation_ids),
        "closure_contract_version": contract_version,
        "computed_handoff_ready": computed_ready,
        "candidate_digest": actual_candidate_digest,
        "evidence_bundle_id": evidence_manifest.get("bundle_id") if isinstance(evidence_manifest, dict) else None,
        "evidence_bundle_digest": (
            canonical_evidence_bundle_digest(evidence_manifest)
            if isinstance(evidence_manifest, dict)
            else None
        ),
        "evidence_refs_resolved": len(referenced_evidence),
        "canonical_quality_accepted": False,
        "quality_stage": "PRE_QUALITY_FLOOR",
    }
    return errors, summary


def unwrap_runtime_input(value: Any) -> tuple[Any, Any]:
    if isinstance(value, dict) and isinstance(value.get("candidate"), dict) and "evidence_manifest" in value:
        return value["candidate"], value.get("evidence_manifest")
    return value, None
