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
from typing import Any

V03_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
EXISTING_AUTHORITY = "EXISTING_AUTHORITY"
CURRENT_AUTHORITY_EVIDENCE_CLASSES = {
    "OBSERVED_LIVE",
    "OBSERVED_READBACK",
    "GOVERNED_RECEIPT",
    "SOURCE_PROVENANCE",
}

SIGNAL_TO_OBLIGATION_TYPES = {
    "CROSS_OPERATION": {"WIRING_PHYSICALITY"},
    "AUTHORITY_CHANGE": {"AUTHORITY_EXISTENCE"},
    "POLICY_CONTRACT_CHANGE": {"POLICY_CONTRACT"},
    "CONTEXT_TRANSPORT": {"CONTEXT_TRANSPORT"},
    "STATE_RECOVERY": {"STATE_RECOVERY_SEMANTICS"},
    "CONCURRENCY": {"CONCURRENCY"},
    "MIGRATION_TRANSITION": {"MIGRATION_TRANSITION"},
    "SECURITY_BOUNDARY": {"SECURITY_BOUNDARY", "AUTHORITY_EXISTENCE"},
    "MULTI_RUNTIME": {"WIRING_PHYSICALITY", "COMPATIBILITY"},
    "COST_SCALE": {"OTHER_MATERIAL"},
}

DIMENSION_TO_OBLIGATION_TYPES = {
    "ARCHITECTURE": {"DECISION_CLOSURE"},
    "CONTROLS": {"DECISION_CLOSURE"},
    "POLICIES_CONTRACTS": {"POLICY_CONTRACT"},
    "CONTEXT_TRANSPORT": {"CONTEXT_TRANSPORT"},
    "WIRING": {"WIRING_PHYSICALITY"},
    "COMPATIBILITY_TRANSITION": {"COMPATIBILITY"},
    "RECOVERY_TERMINALITY": {"STATE_RECOVERY_SEMANTICS"},
    "OBSERVABILITY": {"OBSERVABILITY"},
    "SECURITY_AUTHORITY": {"AUTHORITY_EXISTENCE"},
    "COST_PERFORMANCE": {"OTHER_MATERIAL"},
    "TESTING_ASSURANCE": {"TEST_ASSURANCE"},
    "OPERABILITY_MAINTENANCE": {"OTHER_MATERIAL"},
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
    normalized = copy.deepcopy(candidate)
    try:
        normalized["closure_proof"]["candidate_binding"].pop("candidate_digest", None)
    except Exception:
        pass
    return _canonical_digest(normalized)


def canonical_evidence_bundle_digest(manifest: dict) -> str:
    normalized = copy.deepcopy(manifest)
    if isinstance(normalized, dict):
        normalized.pop("bundle_digest", None)
        # Excluded to avoid a two-way digest cycle. Candidate digest is verified
        # separately against the manifest after the bundle digest is fixed.
        normalized.pop("candidate_digest", None)
    return _canonical_digest(normalized)


def derive_required_obligation_types(candidate: dict) -> tuple[set[str], set[str]]:
    """Return required obligation types and generic material signals."""
    required = set(BASELINE_REQUIRED_TYPES)
    material_signals = {"DECISION_CLOSURE", "EVIDENCE_PROVENANCE"}

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
            if dimension == "WIRING":
                material_signals.add("WIRING")

    return required, material_signals


def _validate_manifest_shape(manifest: Any) -> tuple[list[dict], dict[str, dict]]:
    errors: list[dict] = []
    evidence_by_id: dict[str, dict] = {}
    if not isinstance(manifest, dict):
        return [_err("SRCR_EVIDENCE_MANIFEST_REQUIRED", "$.evidence_manifest")], evidence_by_id

    if manifest.get("manifest_version") != "SRCR_EVIDENCE_MANIFEST_V1":
        errors.append(_err("SRCR_EVIDENCE_MANIFEST_VERSION_INVALID", "$.evidence_manifest.manifest_version"))

    for key in ("bundle_id", "bundle_digest", "candidate_revision", "candidate_digest", "observed_at"):
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

    binding = proof.get("candidate_binding")
    if not isinstance(binding, dict):
        errors.append(_err("SRCR_CANDIDATE_BINDING_REQUIRED", "$.closure_proof.candidate_binding"))
        return errors, {"applies": True}

    actual_candidate_digest = canonical_candidate_digest(candidate)
    if binding.get("candidate_digest") != actual_candidate_digest:
        errors.append(_err("SRCR_CANDIDATE_DIGEST_MISMATCH", "$.closure_proof.candidate_binding.candidate_digest", actual_candidate_digest))

    if isinstance(evidence_manifest, dict):
        if binding.get("candidate_revision") != evidence_manifest.get("candidate_revision"):
            errors.append(_err("SRCR_CANDIDATE_REVISION_EVIDENCE_MISMATCH", "$.closure_proof.candidate_binding.candidate_revision"))
        if binding.get("candidate_digest") != evidence_manifest.get("candidate_digest"):
            errors.append(_err("SRCR_CANDIDATE_DIGEST_EVIDENCE_MISMATCH", "$.evidence_manifest.candidate_digest"))
        if binding.get("evidence_bundle_id") != evidence_manifest.get("bundle_id"):
            errors.append(_err("SRCR_EVIDENCE_BUNDLE_ID_MISMATCH", "$.closure_proof.candidate_binding.evidence_bundle_id"))
        if binding.get("evidence_bundle_digest") != evidence_manifest.get("bundle_digest"):
            errors.append(_err("SRCR_EVIDENCE_BUNDLE_BINDING_MISMATCH", "$.closure_proof.candidate_binding.evidence_bundle_digest"))

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
        if oid in obligation_by_id:
            errors.append(_err("SRCR_PROOF_OBLIGATION_ID_DUPLICATED", f"{path}.obligation_id", oid))
        else:
            obligation_by_id[oid] = row

    present_types = {row.get("obligation_type") for row in obligation_by_id.values()}
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

    wiring_material = any(
        isinstance(x, dict) and x.get("dimension") == "WIRING" and x.get("disposition") == "REQUIRED_CHANGE"
        for x in (candidate.get("omission_discovery") or [])
    )
    wiring = proof.get("wiring_proofs") if isinstance(proof.get("wiring_proofs"), list) else []
    if wiring_material and not wiring:
        errors.append(_err("SRCR_MATERIAL_WIRING_UNDERCLOSED", "$.closure_proof.wiring_proofs"))

    required_ids = {
        oid for oid, row in obligation_by_id.items()
        if row.get("obligation_type") in required_types
    }
    closed_ids = {oid for oid in required_ids if obligation_by_id[oid].get("status") == "CLOSED"}
    open_ids = required_ids - closed_ids

    # Any explicitly open obligation is incompatible with ready SYSTEMIC_REPAIR_SPEC.
    any_open_ids = {oid for oid, row in obligation_by_id.items() if row.get("status") == "OPEN"}

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
        "computed_handoff_ready": computed_ready,
        "candidate_digest": actual_candidate_digest,
        "evidence_bundle_digest": evidence_manifest.get("bundle_digest") if isinstance(evidence_manifest, dict) else None,
        "evidence_refs_resolved": len(referenced_evidence),
        "canonical_quality_accepted": False,
        "quality_stage": "PRE_QUALITY_FLOOR",
    }
    return errors, summary


def unwrap_runtime_input(value: Any) -> tuple[Any, Any]:
    if isinstance(value, dict) and isinstance(value.get("candidate"), dict) and "evidence_manifest" in value:
        return value["candidate"], value.get("evidence_manifest")
    return value, None
