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


def _catalog_receipt_errors(casc, manifest, uid, path, err):
    """Require actual N1/N2 source-first readback, not catalog labels."""
    import hashlib
    import json
    errors = []
    entries = casc.get("catalog_queries")
    if not isinstance(entries, list):
        return [err("GAP_CATALOG_QUERIES_REQUIRED", f"{path}.catalog_queries")]
    found = {}
    for i, entry in enumerate(entries):
        at = f"{path}.catalog_queries[{i}]"
        if not isinstance(entry, dict):
            errors.append(err("GAP_CATALOG_QUERY_INVALID", at))
            continue
        level = entry.get("level")
        if level not in ("N1", "N2") or level in found:
            errors.append(err("GAP_CATALOG_LEVEL_INVALID_OR_DUPLICATE", at))
            continue
        found[level] = entry
        if entry.get("datum_id") != uid:
            errors.append(err("GAP_CATALOG_DATUM_MISMATCH", at))
        data = entry.get("readback")
        if not isinstance(data, dict) or any(k not in data for k in ("source", "source_kind", "query", "result_kind", "row_count", "sample_records", "observed_at", "snapshot")):
            errors.append(err("GAP_CATALOG_READBACK_INCOMPLETE", at))
            continue
        source, query, kind, count, rows = (data.get(k) for k in ("source", "query", "result_kind", "row_count", "sample_records"))
        if not all(isinstance(data.get(k), str) and data[k].strip() for k in ("source", "query", "observed_at", "snapshot")):
            errors.append(err("GAP_CATALOG_READBACK_INCOMPLETE", at))
        if not isinstance(count, int) or isinstance(count, bool) or count < 0 or not isinstance(rows, list) or any(not isinstance(row, dict) or not row for row in rows):
            errors.append(err("GAP_CATALOG_ROW_SHAPE_INVALID", at))
        elif not ((kind == "EMPTY" and count == 0 and not rows) or (kind == "ROWS" and count > 0 and 0 < len(rows) <= count)):
            errors.append(err("GAP_CATALOG_RESULT_INCONSISTENT", at))
        if not isinstance(query, str) or not query.lstrip().lower().startswith(("select ", "with ")):
            errors.append(err("GAP_CATALOG_NON_SELECT_QUERY", at))
        kind_expected = "VIEW" if level == "N1" else "BASE_TABLE"
        if not isinstance(source, str) or not source.strip() or data.get("source_kind") != kind_expected:
            errors.append(err("GAP_CATALOG_SOURCE_LEVEL_MISMATCH", at))
        eid = entry.get("evidence_id")
        if not isinstance(eid, str) or not isinstance(manifest, dict) or eid not in manifest:
            errors.append(err("GAP_CATALOG_MANIFEST_EVIDENCE_MISSING", at))
            continue
        proof = manifest[eid]
        digest = "sha256:" + hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
        if proof.get("digest") != digest or proof.get("source_locator") != query:
            errors.append(err("GAP_CATALOG_READBACK_DIGEST_MISMATCH", at))
    if not {"N1", "N2"}.issubset(found):
        errors.append(err("GAP_CATALOG_N1_N2_MISSING", f"{path}.catalog_queries"))
    if len({v.get("evidence_id") for v in found.values()}) != len(found):
        errors.append(err("GAP_CATALOG_EVIDENCE_REUSED", f"{path}.catalog_queries"))
    return errors



def _level_trace_errors(casc, manifest, uid, path, err):
    """Prove that an exhausted five-class search reached N3/N4/N5 too.

    N1/N2 are validated separately with typed SELECT readbacks. These higher
    levels reuse the CURRENT external manifest; they do not discover evidence,
    issue queries or grant authority. An inaccessible source is a result only
    when its failed attempt is itself recorded with evidence and error detail.
    """
    import re
    errors = []
    records = casc.get("level_trace")
    levels = ("N3", "N4", "N5")
    if not isinstance(records, list):
        return [err("GAP_LEVEL_TRACE_REQUIRED", f"{path}.level_trace")]
    observed = [x.get("level") if isinstance(x, dict) else None for x in records]
    if observed != list(levels):
        errors.append(err("GAP_LEVEL_TRACE_ORDER_OR_COVERAGE", f"{path}.level_trace"))
    if not isinstance(manifest, dict):
        return errors + [err("GAP_LEVEL_TRACE_MANIFEST_REQUIRED", f"{path}.level_trace")]
    for i, item in enumerate(records):
        at = f"{path}.level_trace[{i}]"
        if not isinstance(item, dict):
            errors.append(err("GAP_LEVEL_TRACE_INVALID", at))
            continue
        level = item.get("level")
        if level not in levels:
            errors.append(err("GAP_LEVEL_TRACE_INVALID", at))
            continue
        source = item.get("source")
        locator = item.get("locator")
        evidence_id = item.get("evidence_id")
        state = item.get("result_kind")
        observed_at = item.get("observed_at")
        revision = item.get("source_revision")
        digest = item.get("digest")
        if item.get("datum_id") != uid:
            errors.append(err("GAP_LEVEL_TRACE_DATUM_MISMATCH", at))
        if any(not isinstance(x, str) or not x.strip() for x in
               (source, locator, evidence_id, observed_at, revision, digest)):
            errors.append(err("GAP_LEVEL_TRACE_REQUIRED_FIELDS", at))
            continue
        if level == "N4" and not re.fullmatch(r"[0-9a-f]{40}", revision):
            errors.append(err("GAP_LEVEL_TRACE_GITHUB_REVISION_UNPINNED", at))
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            errors.append(err("GAP_LEVEL_TRACE_DIGEST_INVALID", at))
        if state not in ("FOUND_INSUFFICIENT", "NO_EVIDENCE", "NO_SOURCE_ACCESSIBLE"):
            errors.append(err("GAP_LEVEL_TRACE_RESULT_INVALID", at))
        if state == "NO_SOURCE_ACCESSIBLE" and (
            not isinstance(item.get("error_detail"), str) or
            not item["error_detail"].strip()
        ):
            errors.append(err("GAP_LEVEL_TRACE_ACCESS_ERROR_MISSING", at))
        proof = manifest.get(evidence_id)
        if not isinstance(proof, dict):
            errors.append(err("GAP_LEVEL_TRACE_EVIDENCE_MISSING", at))
        elif proof.get("source_locator") != locator or proof.get("digest") != digest:
            errors.append(err("GAP_LEVEL_TRACE_PROVENANCE_MISMATCH", at))
    if len({x.get("evidence_id") for x in records if isinstance(x, dict)}) != len(records):
        errors.append(err("GAP_LEVEL_TRACE_EVIDENCE_REUSED", f"{path}.level_trace"))
    return errors


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
        casc = row.get("cascade")
        ALL = {"DIRECT", "DECLARED", "ANALOGY", "RELATED", "HISTORY"}
        if not isinstance(casc, dict):
            errors.append(_err("GAP_CASCADE_RECORD_REQUIRED", f"{path}.cascade", "A design-blocking gap must show the gap-resolution cascade."))
        else:
            tried = set(casc.get("classes_tried") or [])
            nosrc = set(casc.get("classes_without_source") or [])
            if not tried:
                errors.append(_err("GAP_CASCADE_NOTHING_TRIED", f"{path}.cascade.classes_tried"))
            if (tried | nosrc) != ALL or (tried & nosrc):
                errors.append(_err("GAP_CASCADE_NOT_EXHAUSTED", f"{path}.cascade", "Every evidence class must be tried or declared without a source."))
            else:
                cc = [str(x) for x in (casc.get("catalog_checked") or []) if _nonempty(x)] if isinstance(casc.get("catalog_checked"), list) else []
                if nosrc and not all(any(x.startswith(lv + ":") for x in cc) for lv in ("N1", "N2", "N3", "N4")):
                    errors.append(_err("GAP_CASCADE_NO_SOURCE_NEEDS_CATALOG", f"{path}.cascade.catalog_checked",
                                       "A class may be declared without a source only after consulting levels N1 (ready-made views), N2 (canonical tables), N3 (other tables found by description) and N4 (GitHub). Record each as N<level>:<source>."))
                rec = casc.get("search_record")
                got = set()
                if isinstance(rec, list):
                    for c in rec:
                        if isinstance(c, dict) and _nonempty(c.get("source")) and _nonempty(c.get("locator")) and _nonempty(c.get("result")):
                            got.add(c.get("class"))
                if got != ALL:
                    errors.append(_err("GAP_CASCADE_EXHAUSTED_NEEDS_SEARCH_RECORD", f"{path}.cascade.search_record",
                                       "Every class was searched: state what was explored. List, for each of the five classes, the exact source, locator and result (NO_SOURCE_ACCESSIBLE where applicable), then close saying that everything reachable was explored and no evidence was found."))
                else:
                    errors.extend(_catalog_receipt_errors(casc, manifest, uid, f"{path}.cascade", _err))
                    errors.extend(_level_trace_errors(casc, manifest, uid, f"{path}.cascade", _err))
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
