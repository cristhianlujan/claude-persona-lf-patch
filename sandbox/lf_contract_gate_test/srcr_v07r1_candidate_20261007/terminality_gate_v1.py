"""Deterministic terminality gate for SRCR V0.7R1.

This module decides only terminal status from an already-diagnosed closure state.
It performs no evidence acquisition and does not alter the V0.7 RAW output shape.
"""

from __future__ import annotations

OPEN_MATERIAL_STATES = {
    "GAP",
    "UNKNOWN",
    "EVIDENCE_REQUIREMENT",
    "DESIGN_BLOCKING",
}

OPERABILITY_CLOSED_STATES = {
    "RESOLVED",
    "NOT_APPLICABLE_WITH_PROOF",
}

CORE_BOOLEAN_FIELDS = (
    "root_cause_established",
    "first_bad_boundary_established",
    "topology_evidence_bound",
    "blast_radius_evidence_bound",
    "repair_coherent",
    "rollback_executable",
    "acceptance_executable",
)


def decide_terminal(state: dict) -> dict:
    """Return a deterministic SRCR terminal verdict and blocking reasons."""
    reasons: list[str] = []

    blocking_codes = list(state.get("blocking_codes") or [])
    if blocking_codes:
        return {
            "status": "BLOCK_PIPELINE",
            "reasons": [f"BLOCKING_CODE:{code}" for code in blocking_codes],
        }

    material_items = list(state.get("material_items") or [])
    for item in material_items:
        code = str(item.get("code") or "UNNAMED_MATERIAL_ITEM")
        status = str(item.get("status") or "UNKNOWN")
        if status in OPEN_MATERIAL_STATES:
            reasons.append(f"MATERIAL_OPEN:{code}:{status}")

    second_order = list(state.get("uncontained_second_order_paths") or [])
    for path in second_order:
        reasons.append(f"UNCONTAINED_SECOND_ORDER:{path}")

    if state.get("operability_applicable") is True:
        operability_status = str(state.get("operability_status") or "UNKNOWN")
        if operability_status not in OPERABILITY_CLOSED_STATES:
            reasons.append(
                "OPERABILITY_MAINTENANCE_OWNERSHIP_OPEN:"
                + operability_status
            )

    repair_required = state.get("repair_required", True)
    if repair_required is False:
        if reasons:
            return {"status": "NEEDS_MORE_EVIDENCE", "reasons": reasons}
        if state.get("no_repair_positive_evidence") is True:
            return {"status": "NO_REPAIR_REQUIRED", "reasons": []}
        return {
            "status": "NEEDS_MORE_EVIDENCE",
            "reasons": ["NO_REPAIR_POSITIVE_EVIDENCE_MISSING"],
        }

    for field in CORE_BOOLEAN_FIELDS:
        if state.get(field) is not True:
            reasons.append(f"CORE_CLOSURE_INCOMPLETE:{field}")

    if reasons:
        return {"status": "NEEDS_MORE_EVIDENCE", "reasons": reasons}

    return {"status": "SYSTEMIC_REPAIR_SPEC", "reasons": []}
