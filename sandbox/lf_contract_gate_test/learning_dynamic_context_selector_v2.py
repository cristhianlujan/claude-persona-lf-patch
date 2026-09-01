#!/usr/bin/env python3
from __future__ import annotations
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any, Iterable

SCHEMA = "LF_LEARNING_DYNAMIC_CONTEXT_SELECTION_V2"
REQUIRED_KB_CATEGORY = "COMPETENCIA"
DEFAULT_MAX_EVIDENCE = 5
DEFAULT_TAXONOMY = "LF_LEARNING_CLUSTER_V1"
ALLOWED_LIFECYCLES = {"ANALIZADO", "CARD_CREADA"}
ALLOWED_ELIGIBILITIES = {"PASS", "CANONICAL_PASS", "CANONICAL_PASS_STALE_NOTE_FLAGGED"}

class DynamicLearningSelectionError(ValueError):
    pass

@dataclass(frozen=True)
class DynamicBindingSpec:
    consumer_id: str
    capability_id: str
    cluster_codes: tuple[str, ...]
    max_evidence_refs: int = DEFAULT_MAX_EVIDENCE
    taxonomy_version: str = DEFAULT_TAXONOMY


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _score(value: Any) -> Decimal:
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        return Decimal("-1")


def _current_kb_eligible(row: dict[str, Any]) -> bool:
    return (
        _text(row.get("kb_id")) != ""
        and _text(row.get("kb_category")) == REQUIRED_KB_CATEGORY
        and row.get("consumer_ready") is True
        and _text(row.get("grounding_status")) == "GROUNDED"
    )


def _event_clusters(payload: dict[str, Any]) -> set[str]:
    return {part.strip() for part in _text(payload.get("cluster_code")).split("|") if part.strip()}


def _classification_receipt_eligible(event: dict[str, Any], binding: DynamicBindingSpec) -> bool:
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    event_id = event.get("event_id", event.get("id"))
    try:
        event_id = int(event_id)
    except (TypeError, ValueError):
        return False
    if event_id <= 0:
        return False
    if _text(payload.get("taxonomy_version")) != binding.taxonomy_version:
        return False
    if _text(payload.get("lifecycle")) not in ALLOWED_LIFECYCLES:
        return False
    if _text(payload.get("eligibility")) not in ALLOWED_ELIGIBILITIES:
        return False
    if not (_event_clusters(payload) & set(binding.cluster_codes)):
        return False
    return _text(payload.get("kb_id")) != ""


def select_dynamic_read_only_context(
    kb_rows: Iterable[dict[str, Any]],
    classification_events: Iterable[dict[str, Any]],
    *,
    binding: DynamicBindingSpec,
) -> dict[str, Any]:
    if not binding.consumer_id or not binding.capability_id:
        raise DynamicLearningSelectionError("EXACT_CONSUMER_BINDING_REQUIRED")
    if not binding.cluster_codes or any(not _text(code) for code in binding.cluster_codes):
        raise DynamicLearningSelectionError("EXACT_CLUSTER_MAPPING_REQUIRED")
    if binding.max_evidence_refs < 1 or binding.max_evidence_refs > 5:
        raise DynamicLearningSelectionError("MAX_EVIDENCE_REFS_OUT_OF_BOUNDS")

    current_by_id: dict[str, dict[str, Any]] = {}
    for row in kb_rows:
        if isinstance(row, dict) and _current_kb_eligible(row):
            current_by_id[_text(row.get("kb_id"))] = row

    receipt_by_kb: dict[str, int] = {}
    for event in classification_events:
        if not isinstance(event, dict) or not _classification_receipt_eligible(event, binding):
            continue
        payload = event.get("payload")
        kb_id = _text(payload.get("kb_id"))
        if kb_id not in current_by_id:
            continue
        event_id = int(event.get("event_id", event.get("id")))
        receipt_by_kb[kb_id] = max(event_id, receipt_by_kb.get(kb_id, 0))

    candidates = []
    for kb_id, event_id in receipt_by_kb.items():
        row = current_by_id[kb_id]
        candidates.append((-
            _score(row.get("quality_score")), -event_id, kb_id, row, event_id
        ))
    candidates.sort(key=lambda item: (item[0], item[1], item[2]))

    selected = []
    for _, _, kb_id, row, event_id in candidates[: binding.max_evidence_refs]:
        selected.append({
            "kb_id": kb_id,
            "kb_category": REQUIRED_KB_CATEGORY,
            "topic": _text(row.get("topic")),
            "summary": _text(row.get("summary")),
            "source_url": _text(row.get("source_url")),
            "competitor": _text(row.get("competitor")),
            "quality_score": row.get("quality_score"),
            "classification_event_id": event_id,
            "evidence_ref": f"public.lf_knowledge_base/{kb_id}",
        })

    return {
        "schema": SCHEMA,
        "mode": "READ_ONLY",
        "selector": "DETERMINISTIC_CLASSIFIED_CLUSTER_CURRENT_KB",
        "taxonomy_version": binding.taxonomy_version,
        "cluster_codes": list(binding.cluster_codes),
        "required_kb_category": REQUIRED_KB_CATEGORY,
        "llm_calls": 0,
        "round_trips": 0,
        "consumer_id": binding.consumer_id,
        "capability_id": binding.capability_id,
        "selected_count": len(selected),
        "selected": selected,
        "fallback": "NO_COMPETITIVE_CONTEXT" if not selected else None,
    }
