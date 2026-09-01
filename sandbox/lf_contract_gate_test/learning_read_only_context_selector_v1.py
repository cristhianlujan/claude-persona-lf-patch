#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

SCHEMA = "LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V1"
DEFAULT_MAX_EVIDENCE = 5
DEFAULT_CONTEXT_BUDGET_BYTES = 6000
REQUIRED_KB_CATEGORY = "COMPETENCIA"
BINDINGS_PATH = Path(__file__).with_name("learning_consumer_bindings_v2.yaml")

class LearningSelectionError(ValueError):
    pass

@dataclass(frozen=True)
class BindingSpec:
    consumer_id: str
    capability_id: str
    source_learning_ids: tuple[str, ...]
    max_evidence_refs: int = DEFAULT_MAX_EVIDENCE
    context_budget_bytes: int = DEFAULT_CONTEXT_BUDGET_BYTES

def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""

def _selected_bytes(selected: list[dict[str, Any]]) -> int:
    return len(json.dumps(selected,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode("utf-8"))

def _binding_blocks(text: str) -> list[str]:
    starts=[m.start() for m in re.finditer(r'^  - binding_id:',text,re.M)]
    if not starts: return []
    end=text.find('\nrollback:',starts[-1])
    if end<0: end=len(text)
    starts.append(end)
    return [text[starts[i]:starts[i+1]] for i in range(len(starts)-1)]

def _assert_governed_binding(binding: BindingSpec) -> None:
    try: text=BINDINGS_PATH.read_text(encoding="utf-8")
    except OSError as exc: raise LearningSelectionError(f"GOVERNED_BINDING_CATALOG_UNAVAILABLE:{type(exc).__name__}") from exc
    match=None
    for block in _binding_blocks(text):
        consumer=re.search(r'^    consumer_id:\s*(\S+)\s*$',block,re.M)
        capability=re.search(r'^    capability_id:\s*(\S+)\s*$',block,re.M)
        if consumer and capability and consumer.group(1)==binding.consumer_id and capability.group(1)==binding.capability_id:
            match=block; break
    if match is None: raise LearningSelectionError("EXACT_GOVERNED_CONSUMER_BINDING_REQUIRED")
    ids_match=re.search(r'^    source_learning_ids:\s*\[([^\]]+)\]\s*$',match,re.M)
    budget_match=re.search(r'^    context_budget:\s*\{max_bytes:\s*(\d+),',match,re.M)
    if not ids_match or not budget_match: raise LearningSelectionError("GOVERNED_BINDING_CONTRACT_INCOMPLETE")
    ids=tuple(part.strip() for part in ids_match.group(1).split(',') if part.strip())
    if ids!=binding.source_learning_ids: raise LearningSelectionError("SOURCE_LEARNING_IDS_NOT_EXACT_GOVERNED_BINDING")
    if int(budget_match.group(1))!=binding.context_budget_bytes: raise LearningSelectionError("BINDING_CONTEXT_BUDGET_MISMATCH")

def _eligible(row: dict[str, Any]) -> bool:
    return (
        _text(row.get("kb_id")) != ""
        and _text(row.get("kb_category")) == REQUIRED_KB_CATEGORY
        and row.get("consumer_ready") is True
        and _text(row.get("grounding_status")) == "GROUNDED"
    )

def select_read_only_context(rows: Iterable[dict[str, Any]], *, binding: BindingSpec) -> dict[str, Any]:
    if not binding.consumer_id or not binding.capability_id:
        raise LearningSelectionError("EXACT_CONSUMER_BINDING_REQUIRED")
    if not binding.source_learning_ids:
        raise LearningSelectionError("SOURCE_LEARNING_IDS_REQUIRED")
    if binding.max_evidence_refs < 1 or binding.max_evidence_refs > 5:
        raise LearningSelectionError("MAX_EVIDENCE_REFS_OUT_OF_BOUNDS")
    if binding.context_budget_bytes < 256 or binding.context_budget_bytes > 65536:
        raise LearningSelectionError("CONTEXT_BUDGET_BYTES_OUT_OF_BOUNDS")
    _assert_governed_binding(binding)
    allowed=set(binding.source_learning_ids); by_id={}
    for row in rows:
        if not isinstance(row,dict) or not _eligible(row): continue
        kb_id=_text(row.get("kb_id"))
        if kb_id in allowed: by_id[kb_id]=row
    selected=[]; skipped_oversize_count=0
    for kb_id in binding.source_learning_ids:
        row=by_id.get(kb_id)
        if row is None: continue
        item={"kb_id":kb_id,"kb_category":REQUIRED_KB_CATEGORY,"topic":_text(row.get("topic")),"summary":_text(row.get("summary")),"source_url":_text(row.get("source_url")),"competitor":_text(row.get("competitor")),"quality_score":row.get("quality_score"),"evidence_ref":f"public.lf_knowledge_base/{kb_id}"}
        if _selected_bytes(selected+[item])>binding.context_budget_bytes:
            skipped_oversize_count+=1; continue
        selected.append(item)
        if len(selected)>=binding.max_evidence_refs: break
    context_bytes=_selected_bytes(selected)
    return {"schema":SCHEMA,"mode":"READ_ONLY","selector":"DETERMINISTIC_EXACT_ID","required_kb_category":REQUIRED_KB_CATEGORY,"llm_calls":0,"round_trips":0,"consumer_id":binding.consumer_id,"capability_id":binding.capability_id,"context_budget_bytes":binding.context_budget_bytes,"context_bytes":context_bytes,"context_budget_pass":context_bytes<=binding.context_budget_bytes,"skipped_oversize_count":skipped_oversize_count,"selected_count":len(selected),"selected":selected,"fallback":"NO_COMPETITIVE_CONTEXT" if not selected else None}
