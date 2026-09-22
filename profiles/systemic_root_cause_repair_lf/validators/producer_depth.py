"""SRCR V0.5 producer-depth floor.

Purpose: make the non-ready exit (NEEDS_MORE_EVIDENCE) cost the same kind of
evidence as the ready exit. A DESIGN_BLOCKING uncertainty is accepted only when
the producer shows which accessible surfaces it actually consulted and every
attempt resolves to an evidence_id in the externally assembled evidence
manifest. The producer cannot manufacture that manifest, so a claimed attempt
that did not happen cannot resolve.

Deterministically bound: attempt.locator must equal the manifest row's
source_locator for that evidence_id (no borrowed evidence). Whether that row
really supports attempt.result is checked by the judge, which hydrates it.

This module adds no new stop condition for ready outputs. It only prices the
stop exit and relaxes incident-only requirements when the case is an
architecture audit (see case_mode).
"""
from __future__ import annotations

from typing import Any

V05_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5"
V06_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
V05_FAMILY_PACK_IDS = {V05_PACK_ID, V06_PACK_ID}

CASE_MODES = {"INCIDENT_REPAIR", "ARCHITECTURE_AUDIT"}
ATTEMPT_SURFACES = {
    "GITHUB_SOURCE",
    "SUPABASE_TABLE_OR_VIEW",
    "SUPABASE_FUNCTION",
    "OPERATION_DEFINITION",
    "OPERATION_EXECUTION_RECEIPT",
    "RUNTIME_READBACK",
    "EDGE_FUNCTION",
    "EKB",
    "OTHER_GOVERNED_SOURCE",
}
BLOCKING_ATTEMPT_RESULTS = {"ABSENT", "UNREACHABLE", "ACCESS_DENIED", "FOUND_INSUFFICIENT"}


def _err(code: str, path: str = "$", message: str = "") -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def applies(payload: Any) -> bool:
    return isinstance(payload, dict) and payload.get("profile_pack_id") in V05_FAMILY_PACK_IDS


def case_mode(payload: Any) -> str | None:
    if not applies(payload):
        return None
    mode = payload.get("case_mode")
    return mode if mode in CASE_MODES else None


def _current_evidence(evidence_manifest: Any) -> dict[str, dict] | None:
    """evidence_id -> manifest row, CURRENT rows only."""
    if not isinstance(evidence_manifest, dict):
        return None
    rows = evidence_manifest.get("evidence")
    if not isinstance(rows, list):
        return None
    return {
        row["evidence_id"]: row
        for row in rows
        if isinstance(row, dict) and _nonempty(row.get("evidence_id")) and row.get("state") == "CURRENT"
    }


def _norm_locator(value: Any) -> str:
    return " ".join(value.split()) if isinstance(value, str) else ""


def validate_producer_depth(payload: Any, evidence_manifest: Any = None) -> list[dict[str, str]]:
    if not applies(payload):
        return []
    errors: list[dict[str, str]] = []

    if payload.get("case_mode") not in CASE_MODES:
        errors.append(_err("V05_CASE_MODE_INVALID", "$.case_mode", "Use INCIDENT_REPAIR or ARCHITECTURE_AUDIT."))

    manifest = _current_evidence(evidence_manifest)
    rows = payload.get("current_uncertainties") if isinstance(payload.get("current_uncertainties"), list) else []
    blocking_ids: set[str] = set()
    for idx, row in enumerate(rows):
        if not isinstance(row, dict) or row.get("impact") != "DESIGN_BLOCKING":
            continue
        path = f"$.current_uncertainties[{idx}]"
        uid = row.get("uncertainty_id")
        if not _nonempty(uid):
            errors.append(_err("V05_DESIGN_BLOCKER_ID_REQUIRED", f"{path}.uncertainty_id", "Needed so blocked process nodes can reference it."))
        elif uid in blocking_ids:
            errors.append(_err("V05_DESIGN_BLOCKER_ID_DUPLICATE", f"{path}.uncertainty_id"))
        else:
            blocking_ids.add(uid)
        attempts = row.get("attempted_sources")
        if not isinstance(attempts, list) or not attempts:
            errors.append(_err(
                "V05_DESIGN_BLOCKER_WITHOUT_ATTEMPT",
                f"{path}.attempted_sources",
                "A design-blocking gap must list the accessible surfaces actually consulted.",
            ))
            continue
        for aidx, attempt in enumerate(attempts):
            apath = f"{path}.attempted_sources[{aidx}]"
            if not isinstance(attempt, dict):
                errors.append(_err("V05_ATTEMPT_INVALID", apath))
                continue
            if attempt.get("surface") not in ATTEMPT_SURFACES:
                errors.append(_err("V05_ATTEMPT_SURFACE_INVALID", f"{apath}.surface"))
            if not _nonempty(attempt.get("locator")):
                errors.append(_err("V05_ATTEMPT_LOCATOR_REQUIRED", f"{apath}.locator", "Exact query, path@revision or endpoint."))
            if attempt.get("result") not in BLOCKING_ATTEMPT_RESULTS:
                errors.append(_err(
                    "V05_ATTEMPT_RESULT_INVALID",
                    f"{apath}.result",
                    "If the evidence was found and sufficient, the gap is not design-blocking.",
                ))
            if not _nonempty(attempt.get("observation")):
                errors.append(_err("V05_ATTEMPT_OBSERVATION_REQUIRED", f"{apath}.observation"))
            evidence_id = attempt.get("evidence_id")
            if not _nonempty(evidence_id):
                errors.append(_err("V05_ATTEMPT_EVIDENCE_ID_REQUIRED", f"{apath}.evidence_id"))
            elif manifest is None:
                errors.append(_err(
                    "V05_ATTEMPT_UNVERIFIABLE_WITHOUT_MANIFEST",
                    f"{apath}.evidence_id",
                    "Attempts resolve only against the external evidence manifest.",
                ))
            elif evidence_id not in manifest:
                errors.append(_err(
                    "V05_ATTEMPT_EVIDENCE_NOT_IN_MANIFEST",
                    f"{apath}.evidence_id",
                    "Claimed attempt has no current external evidence; it cannot justify a stop.",
                ))
            elif _norm_locator(manifest[evidence_id].get("source_locator")) != _norm_locator(attempt.get("locator")):
                errors.append(_err(
                    "V05_ATTEMPT_EVIDENCE_LOCATOR_MISMATCH",
                    f"{apath}.evidence_id",
                    "The manifest row for this evidence_id records a different locator; evidence is borrowed, not produced by this attempt.",
                ))

    graph = payload.get("material_process_graph")
    nodes = graph.get("nodes") if isinstance(graph, dict) and isinstance(graph.get("nodes"), list) else []
    for nidx, node in enumerate(nodes):
        if not isinstance(node, dict) or node.get("disposition") != "DESIGN_BLOCKING":
            continue
        npath = f"$.material_process_graph.nodes[{nidx}].blocking_uncertainty_id"
        ref = node.get("blocking_uncertainty_id")
        if not _nonempty(ref):
            errors.append(_err("V05_BLOCKED_NODE_WITHOUT_UNCERTAINTY_REF", npath))
        elif ref not in blocking_ids:
            errors.append(_err(
                "V05_BLOCKED_NODE_REF_NOT_DESIGN_BLOCKING",
                npath,
                "Reference must name a DESIGN_BLOCKING current_uncertainty.uncertainty_id.",
            ))
    return errors
