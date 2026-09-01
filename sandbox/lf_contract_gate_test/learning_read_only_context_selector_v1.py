#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

SCHEMA = "LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V1"
DEFAULT_MAX_EVIDENCE = 5


class LearningSelectionError(ValueError):
    pass


@dataclass(frozen=True)
class BindingSpec:
    consumer_id: str
    capability_id: str
    source_learning_ids: tuple[str, ...]
    max_evidence_refs: int = DEFAULT_MAX_EVIDENCE


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _eligible(row: dict[str, Any]) -> bool:
    return (
        _text(row.get("kb_id")) != ""
        and row.get("consumer_ready") is True
        and _text(row.get("grounding_status")) == "GROUNDED"
    )


def select_read_only_context(
    rows: Iterable[dict[str, Any]],
    *,
    binding: BindingSpec,
) -> dict[str, Any]:
    if not binding.consumer_id or not binding.capability_id:
        raise LearningSelectionError("EXACT_CONSUMER_BINDING_REQUIRED")
    if not binding.source_learning_ids:
        raise LearningSelectionError("SOURCE_LEARNING_IDS_REQUIRED")
    if binding.max_evidence_refs < 1 or binding.max_evidence_refs > 5:
        raise LearningSelectionError("MAX_EVIDENCE_REFS_OUT_OF_BOUNDS")

    allowed = set(binding.source_learning_ids)
    by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not _eligible(row):
            continue
        kb_id = _text(row.get("kb_id"))
        if kb_id in allowed:
            by_id[kb_id] = row

    selected: list[dict[str, Any]] = []
    for kb_id in binding.source_learning_ids:
        row = by_id.get(kb_id)
        if row is None:
            continue
        selected.append({
            "kb_id": kb_id,
            "topic": _text(row.get("topic")),
            "summary": _text(row.get("summary")),
            "source_url": _text(row.get("source_url")),
            "competitor": _text(row.get("competitor")),
            "quality_score": row.get("quality_score"),
            "evidence_ref": f"public.lf_knowledge_base/{kb_id}",
        })
        if len(selected) >= binding.max_evidence_refs:
            break

    return {
        "schema": SCHEMA,
        "mode": "READ_ONLY",
        "selector": "DETERMINISTIC_EXACT_ID",
        "llm_calls": 0,
        "round_trips": 0,
        "consumer_id": binding.consumer_id,
        "capability_id": binding.capability_id,
        "selected_count": len(selected),
        "selected": selected,
        "fallback": "NO_COMPETITIVE_CONTEXT" if not selected else None,
    }
