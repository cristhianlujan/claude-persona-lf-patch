#!/usr/bin/env python3
"""PG-01_C7 source-only material sufficiency gate before technical strategy.

Reuses C3's canonical A9 scope/front validator. Returns MISSING back to
Analysis on any absent or unresolved material value. No guessing, discovery,
write, human authorization, PG-03 strategy or runtime execution.
"""
from collections.abc import Mapping

from pg01_c3_scope_front_clean_v1 import assess_scope_front_clean

MATERIAL_CLASSES = (
    "message_texts",
    "error_codes",
    "navigation_events",
    "history_response",
    "applicable_consents",
)

def _missing(code, fields=()):
    return {
        "status": "MISSING", "route": "ANALYSIS",
        "reason": code, "missing_classes": sorted(set(fields)),
        "authority": "NONE", "pg01_runtime_verified": False,
        "strategy_allowed": False,
    }

def assess_pg01_c7(*, snapshot, receipt, requested_scope_ids, obligations):
    """The five mandatory categories must be exhaustively accounted for per READY scope.

    Each category is either PRESENT (source+canonical exact resolved value with
    currentness) or NOT_APPLICABLE (source-backed evidence and rationale).
    A caller assertion is not independent provenance; no permission is granted.
    """
    gate = assess_scope_front_clean(snapshot, receipt, requested_scope_ids)
    if not gate["admissible"]:
        return _missing("PG01_C7_C3_NOT_CLEAN")
    if not isinstance(obligations, list):
        return _missing("PG01_C7_OBLIGATIONS_INVALID", MATERIAL_CLASSES)
    expected = {(sid, category) for sid in requested_scope_ids for category in MATERIAL_CLASSES}
    seen = set()
    missing = set()
    if len(obligations) != len(expected):
        return _missing("PG01_C7_MATERIAL_MATRIX_INCOMPLETE", MATERIAL_CLASSES)
    for row in obligations:
        if not isinstance(row, Mapping):
            return _missing("PG01_C7_OBLIGATION_ROW_INVALID", MATERIAL_CLASSES)
        sid = row.get("scope_id")
        category = row.get("category")
        key = (sid, category)
        if not isinstance(sid, str) or not isinstance(category, str) or key not in expected:
            return _missing("PG01_C7_OBLIGATION_SCOPE_OR_CATEGORY_INVALID", MATERIAL_CLASSES)
        if key in seen:
            return _missing("PG01_C7_OBLIGATION_DUPLICATE", [category])
        seen.add(key)
        if row.get("status") not in {"PRESENT", "NOT_APPLICABLE"}:
            missing.add(category)
            continue
        for field in ("canonical_ref", "source_ref", "currentness_ref", "evidence_ref"):
            if not isinstance(row.get(field), str) or not row[field].strip():
                missing.add(category)
        if row.get("status") == "PRESENT":
            # Empty strings and caller placeholders are not acceptable values.
            if ("resolved_value" not in row or row["resolved_value"] is None
                or (isinstance(row["resolved_value"], str) and not row["resolved_value"].strip())
                or row.get("currentness") != "CURRENT"):
                missing.add(category)
        else:
            if not isinstance(row.get("reason"), str) or not row["reason"].strip():
                missing.add(category)
            # No purported value for a material category declared inapplicable.
            if "resolved_value" in row:
                missing.add(category)
    if seen != expected:
        return _missing("PG01_C7_MATERIAL_MATRIX_INCOMPLETE", {cat for _, cat in expected - seen})
    if missing:
        return _missing("PG01_C7_MATERIAL_EVIDENCE_MISSING", missing)
    return {
        "status": "CANDIDATE_SUFFICIENT_NOT_ADMITTED",
        "route": "PG01_C6_PENDING",
        "reason": "PG01_C7_SYNTHETIC_COMPLETE",
        "checked_scopes": sorted(requested_scope_ids),
        "checked_categories": list(MATERIAL_CLASSES),
        "authority": "NONE", "pg01_runtime_verified": False,
        "strategy_allowed": False,
    }
