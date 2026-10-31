"""Deterministic terminality gate for canonical SRCR V0.6 method revision V0.7R1.

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



def _levels_verified(rec: dict, datum: str, trusted_level_reader) -> bool:
    """N6 must never treat producer-provided strings as independent readback.

    This reader is injected by the governed execution/quality boundary, NOT by
    a model payload. It is required only for exhausted-search terminal claims.
    Earlier sufficient evidence does not need to traverse all five levels.
    """
    if not callable(trusted_level_reader):
        return False
    levels = rec.get("levels")
    expected = ("N1", "N2", "N3", "N4", "N5")
    if not isinstance(levels, list) or [x.get("level") if isinstance(x, dict) else None
                                        for x in levels] != list(expected):
        return False
    seen = set()
    for row in levels:
        level, eid, locator = row.get("level"), row.get("evidence_id"), row.get("locator")
        result = row.get("result")
        if (not isinstance(eid, str) or not eid or eid in seen or
            not isinstance(locator, str) or not locator or
            result not in {"NO_EVIDENCE", "NO_SOURCE_ACCESSIBLE", "FOUND_INSUFFICIENT"}):
            return False
        if result == "NO_SOURCE_ACCESSIBLE" and not row.get("error_detail"):
            return False
        seen.add(eid)
        try:
            proof = trusted_level_reader(datum, level, locator, eid)
        except Exception:
            return False
        if not isinstance(proof, dict) or (
            proof.get("verified") is not True or
            proof.get("datum") != datum or
            proof.get("level") != level or
            proof.get("source_locator") != locator or
            proof.get("evidence_id") != eid or
            proof.get("result") != result or
            (result == "NO_SOURCE_ACCESSIBLE" and
             proof.get("error_detail") != row.get("error_detail"))
        ):
            return False
    return True


def _with_evidence_state(verdict: dict, state: dict, trusted_level_reader=None) -> dict:
    """Tell apart 'nothing was searched yet' from 'everything was explored and
    nothing was found'. The terminal status value is unchanged, so existing
    consumers keep working; the sub-state is what the closing answer reports."""
    if verdict.get("status") != "NEEDS_MORE_EVIDENCE":
        return verdict
    records = state.get("search_records")
    classes = {"DIRECT", "DECLARED", "ANALOGY", "RELATED", "HISTORY"}
    open_items = [i for i in (state.get("material_items") or [])
                  if str(i.get("status") or "UNKNOWN") in OPEN_MATERIAL_STATES]
    ids = [i.get("code") for i in open_items if isinstance(i, dict)]
    if (not isinstance(records, list) or not ids or
            len(ids) != len(set(ids)) or len(records) != len(ids)):
        verdict["evidence_state"] = "SEARCH_INCOMPLETE"
        return verdict
    found = {}
    for rec in records:
        if not isinstance(rec, dict) or not isinstance(rec.get("classes"), list):
            verdict["evidence_state"] = "SEARCH_INCOMPLETE"
            return verdict
        datum, rows = rec.get("datum"), rec["classes"]
        if not datum or datum in found or len(rows) != len(classes):
            verdict["evidence_state"] = "SEARCH_INCOMPLETE"
            return verdict
        observed = [c.get("class") for c in rows if isinstance(c, dict)]
        if (set(observed) != classes or len(observed) != len(classes) or
                any(not (c.get("source") and c.get("locator") and
                         c.get("result") in {"NO_EVIDENCE", "NO_SOURCE_ACCESSIBLE"})
                    for c in rows)):
            verdict["evidence_state"] = "SEARCH_INCOMPLETE"
            return verdict
        found[datum] = rec
    if set(found) != set(ids) or any(
        not _levels_verified(found[d], d, trusted_level_reader) for d in ids
    ):
        verdict["evidence_state"] = "SEARCH_INCOMPLETE"
        return verdict
    verdict["evidence_state"] = "EXPLORED_NO_EVIDENCE_FOUND"
    verdict["explored"] = [{"datum": d, "classes": found[d]["classes"]} for d in ids]
    return verdict


def decide_terminal(state: dict, *, trusted_level_reader=None) -> dict:
    return _with_evidence_state(_decide_terminal(state), state, trusted_level_reader)


def _decide_terminal(state: dict) -> dict:
    """Return a deterministic SRCR terminal verdict and blocking reasons."""
    reasons: list[str] = []

    pipeline_blocking_codes = list(state.get("pipeline_blocking_codes") or [])
    if pipeline_blocking_codes:
        return {
            "status": "BLOCK_PIPELINE",
            "reasons": [
                f"PIPELINE_BLOCKING_CODE:{code}"
                for code in pipeline_blocking_codes
            ],
        }

    material_items = list(state.get("material_items") or [])
    for item in material_items:
        code = str(item.get("code") or "UNNAMED_MATERIAL_ITEM")
        status = str(item.get("status") or "UNKNOWN")
        if status in OPEN_MATERIAL_STATES:
            reasons.append(f"MATERIAL_OPEN:{code}:{status}")

    for code in list(state.get("blocking_codes") or []):
        reasons.append(f"MATERIAL_BLOCKING_CODE:{code}")

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
