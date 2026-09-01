#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable

SCHEMA = 'LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2'
DEFAULT_MAX_EVIDENCE = 5
DEFAULT_MAX_CONTEXT_BYTES = 6000
ALLOWED_OUTPUT_FIELDS = ('kb_id','topic','summary','source_url','competitor','quality_score','evidence_ref')

class LearningSelectionError(ValueError):
    pass

@dataclass(frozen=True)
class BindingSpec:
    consumer_id: str
    capability_id: str
    source_learning_ids: tuple[str, ...]
    max_evidence_refs: int = DEFAULT_MAX_EVIDENCE
    max_context_bytes: int = DEFAULT_MAX_CONTEXT_BYTES


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ''


def _eligible(row: dict[str, Any]) -> bool:
    return bool(_text(row.get('kb_id'))) and row.get('consumer_ready') is True and _text(row.get('grounding_status')) == 'GROUNDED'


def _project(row: dict[str, Any], kb_id: str) -> dict[str, Any]:
    return {
        'kb_id': kb_id,
        'topic': _text(row.get('topic')),
        'summary': _text(row.get('summary')),
        'source_url': _text(row.get('source_url')),
        'competitor': _text(row.get('competitor')),
        'quality_score': row.get('quality_score'),
        'evidence_ref': f'public.lf_knowledge_base/{kb_id}',
    }


def _encoded_bytes(payload: Any) -> int:
    return len(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',',':')).encode('utf-8'))


def select_read_only_context(rows: Iterable[dict[str, Any]], *, binding: BindingSpec) -> dict[str, Any]:
    if not binding.consumer_id or not binding.capability_id:
        raise LearningSelectionError('EXACT_CONSUMER_BINDING_REQUIRED')
    if not binding.source_learning_ids:
        raise LearningSelectionError('SOURCE_LEARNING_IDS_REQUIRED')
    if binding.max_evidence_refs < 1 or binding.max_evidence_refs > 5:
        raise LearningSelectionError('MAX_EVIDENCE_REFS_OUT_OF_BOUNDS')
    if binding.max_context_bytes < 512 or binding.max_context_bytes > 6000:
        raise LearningSelectionError('MAX_CONTEXT_BYTES_OUT_OF_BOUNDS')

    allowed=set(binding.source_learning_ids)
    by_id={}
    for row in rows:
        if isinstance(row,dict) and _eligible(row):
            kb_id=_text(row.get('kb_id'))
            if kb_id in allowed:
                by_id[kb_id]=row

    selected=[]
    base={
        'schema':SCHEMA,'mode':'READ_ONLY','selector':'DETERMINISTIC_EXACT_ID',
        'llm_calls':0,'round_trips':0,'tool_calls':0,
        'consumer_id':binding.consumer_id,'capability_id':binding.capability_id,
        'max_context_bytes':binding.max_context_bytes,
    }
    budget_blocked=[]
    for kb_id in binding.source_learning_ids:
        row=by_id.get(kb_id)
        if row is None: continue
        candidate=_project(row,kb_id)
        trial={**base,'selected_count':len(selected)+1,'selected':selected+[candidate],'fallback':None}
        if _encoded_bytes(trial)>binding.max_context_bytes:
            budget_blocked.append(kb_id)
            continue
        selected.append(candidate)
        if len(selected)>=binding.max_evidence_refs: break

    out={**base,'selected_count':len(selected),'selected':selected,
         'fallback':'NO_COMPETITIVE_CONTEXT' if not selected else None,
         'budget_blocked_learning_ids':budget_blocked}
    out['context_bytes']=_encoded_bytes(out)
    if out['context_bytes']>binding.max_context_bytes:
        raise LearningSelectionError('CONTEXT_BUDGET_POSTCONDITION_FAILED')
    return out
