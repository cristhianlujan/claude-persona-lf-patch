#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,re
from typing import Any

SCHEMA='LF_LEARNING_PROFILE_AUTHORITY_BRIDGE_V1'
ENVELOPE_SCHEMA='LF_LEARNING_CONSUMER_REQUEST_ENVELOPE_V1'

def _canonical(value: Any) -> str:
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))

def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode('utf-8')).hexdigest()

def _safe_id(index: int) -> str:
    return f'LEARNING.CONTEXT.EVIDENCE.{index:02d}'

def build_profile_authority(envelope: dict[str,Any]) -> dict[str,Any]:
    if envelope.get('schema')!=ENVELOPE_SCHEMA: raise ValueError('LEARNING_ENVELOPE_SCHEMA_REQUIRED')
    if envelope.get('writes_allowed') is not False or envelope.get('automatic_promotion') is not False: raise ValueError('READ_ONLY_BOUNDARY_REQUIRED')
    if envelope.get('authority_boundary')!='COMPETITIVE_EVIDENCE_IS_CONTEXT_NOT_PRODUCT_TRUTH': raise ValueError('AUTHORITY_BOUNDARY_REQUIRED')
    refs=envelope.get('selected_evidence_refs') or []
    if not isinstance(refs,list) or len(refs)>5 or any(not isinstance(x,str) or not x.startswith('public.lf_knowledge_base/') for x in refs):
        raise ValueError('SELECTED_EVIDENCE_REFS_INVALID')
    source_sha=_sha(envelope)
    obligations=[{
      'obligation_id':'LEARNING.CONTEXT.AUTHORITY_BOUNDARY',
      'rule':'Competitive evidence is contextual evidence only and must not be represented as LF product truth, policy, legal authority, eligibility, approval or guarantee.',
      'check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['LEARNING_CONTEXT'],
      'question':'Does the complete output preserve the boundary that competitive evidence is context rather than LF product truth or authority?'
    }]
    for index,ref in enumerate(refs,1):
        obligations.append({
          'obligation_id':_safe_id(index),
          'rule':f'Any competitive claim derived from selected context must remain traceable to evidence reference {ref}; do not invent or substitute another source.',
          'check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['LEARNING_CONTEXT'],
          'question':f'If the output uses the selected competitive context, is the use traceable to {ref} without inventing or substituting evidence?'
        })
    required=[x['obligation_id'] for x in obligations]
    return {
      'schema':SCHEMA,
      'consumer_id':envelope.get('consumer_id'),
      'capability_id':envelope.get('capability_id'),
      'binding_id':envelope.get('binding_id'),
      'envelope_sha256':source_sha,
      'authority_source':{
        'authority_id':'LEARNING_CONTEXT','authority_type':'UPSTREAM_CONSTRAINTS',
        'source_ref':f'learning-consumer-envelope:{source_sha}',
        'source_sha256':source_sha,'required_obligation_ids':required,
      },
      'obligations':obligations,
      'max_obligations':6,
      'writes_allowed':False,
      'profile_source_mutation_required':False,
    }
