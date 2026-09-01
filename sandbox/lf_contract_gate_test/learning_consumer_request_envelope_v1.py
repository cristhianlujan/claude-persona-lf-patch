#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json
from typing import Any

SCHEMA='LF_LEARNING_CONSUMER_REQUEST_ENVELOPE_V1'
ALLOWED_CONTEXT_SCHEMA='LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2'

def _sha(payload: Any) -> str:
    raw=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')
    return hashlib.sha256(raw).hexdigest()

def build_envelope(*, task_intent: str, explicit_constraints: list[str], context_pack: dict[str,Any], binding_id: str) -> dict[str,Any]:
    if not task_intent.strip(): raise ValueError('TASK_INTENT_REQUIRED')
    if not binding_id.strip(): raise ValueError('EXACT_BINDING_ID_REQUIRED')
    if context_pack.get('schema')!=ALLOWED_CONTEXT_SCHEMA: raise ValueError('READ_ONLY_CONTEXT_SCHEMA_REQUIRED')
    if context_pack.get('mode')!='READ_ONLY' or context_pack.get('selector')!='DETERMINISTIC_EXACT_ID': raise ValueError('READ_ONLY_DETERMINISTIC_CONTEXT_REQUIRED')
    if context_pack.get('llm_calls')!=0 or context_pack.get('round_trips')!=0 or context_pack.get('tool_calls')!=0: raise ValueError('SELECTOR_SIDE_EFFECT_BUDGET_VIOLATION')
    if int(context_pack.get('context_bytes',0))>int(context_pack.get('max_context_bytes',0)): raise ValueError('CONTEXT_BUDGET_VIOLATION')
    selected=context_pack.get('selected') or []
    refs=[x.get('evidence_ref') for x in selected if isinstance(x,dict) and x.get('evidence_ref')]
    return {
      'schema':SCHEMA,
      'consumer_id':context_pack.get('consumer_id'),
      'capability_id':context_pack.get('capability_id'),
      'binding_id':binding_id,
      'task_intent':task_intent.strip(),
      'explicit_constraints':[str(x).strip() for x in explicit_constraints if str(x).strip()],
      'competitive_context':selected,
      'selected_evidence_refs':refs,
      'context_fallback':context_pack.get('fallback'),
      'authority_boundary':'COMPETITIVE_EVIDENCE_IS_CONTEXT_NOT_PRODUCT_TRUTH',
      'writes_allowed':False,
      'automatic_promotion':False,
      'context_pack_sha256':_sha(context_pack),
    }
