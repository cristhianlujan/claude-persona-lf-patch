#!/usr/bin/env python3
"""Deterministic incremental-value proof floor for SRCR V0.3.

This module validates binding/coherence only. It never decides whether a claimed
delta is actually useful; canonical independent semantic review owns materiality.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

V03_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
V04_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4"
V05_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5"
INCREMENTAL_VALUE_PACK_IDS = {V03_PACK_ID, V04_PACK_ID, V05_PACK_ID}
BASELINE_VERSION = "SRCR_BASELINE_SOLUTION_V1"
BASELINE_CAPTURE_STAGE = "PRE_RESEARCH_CHALLENGER"
OUTCOMES = {"MATERIAL_UPLIFT", "NO_MATERIAL_UPLIFT", "UNPROVEN"}
DELTA_DISPOSITIONS = {"ADOPTED", "REJECTED"}
DELTA_CATEGORIES = {
    "EXISTING_CAPABILITY_REUSE",
    "DELETION_SIMPLIFICATION",
    "HIDDEN_RISK",
    "CONTEXT_PERFORMANCE",
    "OPERABILITY",
    "SECOND_ORDER_EFFECT",
    "OTHER_MATERIAL",
}
SOFT_LIMIT_TOKENS = 1200
HARD_LIMIT_TOKENS = 2400


def _err(code: str, path: str, message: str = "") -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any, *, allow_empty: bool = True) -> bool:
    return isinstance(value, list) and (allow_empty or bool(value)) and all(_nonempty(x) for x in value)


def canonical_baseline_digest(snapshot: dict[str, Any]) -> str:
    raw = json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def incremental_value_applicable(payload: dict[str, Any]) -> bool:
    if not isinstance(payload, dict) or payload.get("profile_pack_id") not in INCREMENTAL_VALUE_PACK_IDS:
        return False
    depth = payload.get("solution_depth") if isinstance(payload.get("solution_depth"), dict) else {}
    research = payload.get("research_assurance") if isinstance(payload.get("research_assurance"), dict) else {}
    mode = depth.get("mode")
    if mode == "DEEP_ARCHITECTURE_RESEARCH":
        return True
    return mode == "BOUNDED" and research.get("current_practice_research_required") is True


def _packet(payload: dict[str, Any]) -> dict[str, Any]:
    research = payload.get("research_assurance")
    if not isinstance(research, dict):
        return {}
    return {
        "baseline_solution_snapshot": research.get("baseline_solution_snapshot"),
        "baseline_digest": research.get("baseline_digest"),
        "discovery_deltas": research.get("discovery_deltas"),
        "incremental_value_outcome": research.get("incremental_value_outcome"),
        "incremental_value_rationale": research.get("incremental_value_rationale"),
    }


def estimate_packet_tokens(payload: dict[str, Any]) -> int:
    raw = json.dumps(_packet(payload), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return (len(raw) + 3) // 4


def validate_incremental_value(payload: dict[str, Any], *, require_ready: bool) -> tuple[list[dict[str, str]], dict[str, Any]]:
    errors: list[dict[str, str]] = []
    applies = incremental_value_applicable(payload)
    research = payload.get("research_assurance") if isinstance(payload.get("research_assurance"), dict) else {}
    fields = (
        "baseline_solution_snapshot",
        "baseline_digest",
        "discovery_deltas",
        "incremental_value_outcome",
        "incremental_value_rationale",
    )
    present = any(key in research for key in fields)

    summary = {
        "applies": applies,
        "required_for_ready": bool(applies and require_ready),
        "outcome": research.get("incremental_value_outcome") if present else None,
        "adopted_delta_ids": [],
        "packet_estimated_tokens": estimate_packet_tokens(payload) if present else 0,
        "soft_limit_tokens": SOFT_LIMIT_TOKENS,
        "hard_limit_tokens": HARD_LIMIT_TOKENS,
        "semantic_materiality_authority": "INDEPENDENT_SEMANTIC_JUDGE",
    }

    if not applies and not present:
        return errors, summary
    if require_ready and applies:
        missing = [key for key in fields if key not in research]
        if missing:
            errors.append(_err("SRCR_INCREMENTAL_VALUE_PROOF_REQUIRED", "$.research_assurance", ",".join(missing)))
            return errors, summary
    if not present:
        return errors, summary

    baseline = research.get("baseline_solution_snapshot")
    path = "$.research_assurance.baseline_solution_snapshot"
    if not isinstance(baseline, dict):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_INVALID", path))
        return errors, summary

    required_baseline = (
        "snapshot_version",
        "capture_stage",
        "input_digest",
        "profile_source_digest",
        "evidence_refs",
        "leading_solution_summary",
        "known_gaps",
        "assumptions",
    )
    if any(key not in baseline for key in required_baseline):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_INCOMPLETE", path))
    if baseline.get("snapshot_version") != BASELINE_VERSION:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_VERSION_INVALID", f"{path}.snapshot_version"))
    if baseline.get("capture_stage") != BASELINE_CAPTURE_STAGE:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_STAGE_INVALID", f"{path}.capture_stage"))
    for key in ("input_digest", "profile_source_digest"):
        value = baseline.get(key)
        if not isinstance(value, str) or len(value) != 71 or not value.startswith("sha256:"):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_BINDING_INVALID", f"{path}.{key}"))
        else:
            try:
                int(value[7:], 16)
            except ValueError:
                errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_BINDING_INVALID", f"{path}.{key}"))
    if not _string_list(baseline.get("evidence_refs"), allow_empty=False):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_EVIDENCE_INVALID", f"{path}.evidence_refs"))
    if not _nonempty(baseline.get("leading_solution_summary")):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_SOLUTION_REQUIRED", f"{path}.leading_solution_summary"))
    for key in ("known_gaps", "assumptions"):
        if not _string_list(baseline.get(key)):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_BASELINE_LIST_INVALID", f"{path}.{key}"))

    expected_digest = canonical_baseline_digest(baseline)
    supplied_digest = research.get("baseline_digest")
    if supplied_digest != expected_digest:
        errors.append(_err(
            "SRCR_INCREMENTAL_VALUE_BASELINE_DIGEST_MISMATCH",
            "$.research_assurance.baseline_digest",
            f"expected={expected_digest}",
        ))

    baseline_refs = set(baseline.get("evidence_refs") or [])
    external_refs = set(research.get("external_evidence_refs") or [])
    leaked = sorted(baseline_refs & external_refs)
    if leaked:
        errors.append(_err(
            "SRCR_INCREMENTAL_VALUE_BASELINE_EXTERNAL_RESEARCH_LEAK",
            f"{path}.evidence_refs",
            ",".join(leaked),
        ))

    deltas = research.get("discovery_deltas")
    if not isinstance(deltas, list):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTAS_INVALID", "$.research_assurance.discovery_deltas"))
        deltas = []
    elif len(deltas) > 12:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_COUNT_EXCEEDED", "$.research_assurance.discovery_deltas"))

    seen: set[str] = set()
    adopted: list[str] = []
    for idx, delta in enumerate(deltas):
        dpath = f"$.research_assurance.discovery_deltas[{idx}]"
        if not isinstance(delta, dict):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_INVALID", dpath))
            continue
        delta_id = delta.get("delta_id")
        if not _nonempty(delta_id):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_ID_REQUIRED", f"{dpath}.delta_id"))
        elif delta_id in seen:
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_ID_DUPLICATED", f"{dpath}.delta_id", delta_id))
        else:
            seen.add(delta_id)
        if delta.get("category") not in DELTA_CATEGORIES:
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_CATEGORY_INVALID", f"{dpath}.category"))
        disposition = delta.get("disposition")
        if disposition not in DELTA_DISPOSITIONS:
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_DISPOSITION_INVALID", f"{dpath}.disposition"))
        trigger_refs = delta.get("trigger_evidence_refs")
        if not _string_list(trigger_refs, allow_empty=False):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_TRIGGER_REQUIRED", f"{dpath}.trigger_evidence_refs"))
            trigger_refs = []
        for key in ("baseline_gap", "material_effect", "tradeoff"):
            if not _nonempty(delta.get(key)):
                errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_FIELD_REQUIRED", f"{dpath}.{key}"))
        final_refs = delta.get("final_design_refs")
        if not _string_list(final_refs, allow_empty=False) or any(not x.startswith("$.") for x in (final_refs or [])):
            errors.append(_err("SRCR_INCREMENTAL_VALUE_DELTA_FINAL_REF_INVALID", f"{dpath}.final_design_refs"))
        if disposition == "ADOPTED":
            if _nonempty(delta_id):
                adopted.append(delta_id)
            if not (set(trigger_refs) - baseline_refs):
                errors.append(_err(
                    "SRCR_INCREMENTAL_VALUE_DELTA_NOT_POST_BASELINE",
                    f"{dpath}.trigger_evidence_refs",
                    "adopted delta requires at least one trigger not already in baseline evidence",
                ))

    outcome = research.get("incremental_value_outcome")
    if outcome not in OUTCOMES:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_OUTCOME_INVALID", "$.research_assurance.incremental_value_outcome"))
    if not _nonempty(research.get("incremental_value_rationale")):
        errors.append(_err("SRCR_INCREMENTAL_VALUE_RATIONALE_REQUIRED", "$.research_assurance.incremental_value_rationale"))
    if outcome == "MATERIAL_UPLIFT" and not adopted:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_UPLIFT_WITHOUT_ADOPTED_DELTA", "$.research_assurance.incremental_value_outcome"))
    if outcome == "NO_MATERIAL_UPLIFT" and adopted:
        errors.append(_err("SRCR_INCREMENTAL_VALUE_NO_UPLIFT_WITH_ADOPTED_DELTA", "$.research_assurance.incremental_value_outcome"))
    if require_ready and applies and outcome == "UNPROVEN":
        errors.append(_err("SRCR_INCREMENTAL_VALUE_UNPROVEN", "$.research_assurance.incremental_value_outcome"))

    tokens = estimate_packet_tokens(payload)
    summary["adopted_delta_ids"] = adopted
    summary["packet_estimated_tokens"] = tokens
    if tokens > HARD_LIMIT_TOKENS:
        errors.append(_err(
            "SRCR_INCREMENTAL_VALUE_CONTEXT_BUDGET_EXCEEDED",
            "$.research_assurance",
            f"{tokens}>{HARD_LIMIT_TOKENS}",
        ))

    return errors, summary
