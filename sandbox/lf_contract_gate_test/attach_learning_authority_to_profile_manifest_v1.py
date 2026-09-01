#!/usr/bin/env python3
from __future__ import annotations
import copy,sys
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[2]
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime'
sys.path.insert(0,str(RUNTIME))
from semantic_obligation_manifest import validate_obligation_manifest


def attach_learning_authority(existing_manifest: dict[str,Any], bridge: dict[str,Any]) -> dict[str,Any]:
    base=validate_obligation_manifest(existing_manifest)
    authority=bridge.get('authority_source') if isinstance(bridge,dict) else None
    obligations=bridge.get('obligations') if isinstance(bridge,dict) else None
    if not isinstance(authority,dict) or authority.get('authority_type')!='UPSTREAM_CONSTRAINTS':
        raise ValueError('UPSTREAM_CONSTRAINTS_AUTHORITY_REQUIRED')
    if authority.get('authority_id')!='LEARNING_CONTEXT':
        raise ValueError('LEARNING_CONTEXT_AUTHORITY_ID_REQUIRED')
    if not isinstance(obligations,list) or not obligations:
        raise ValueError('LEARNING_OBLIGATIONS_REQUIRED')
    existing_authority_ids={x['authority_id'] for x in base['authority_sources']}
    existing_obligation_ids={x['obligation_id'] for x in base['obligations']}
    if authority['authority_id'] in existing_authority_ids:
        raise ValueError('LEARNING_AUTHORITY_DUPLICATE')
    incoming_ids=[x.get('obligation_id') for x in obligations if isinstance(x,dict)]
    if len(incoming_ids)!=len(set(incoming_ids)) or any(not x for x in incoming_ids):
        raise ValueError('LEARNING_OBLIGATION_IDS_INVALID')
    if existing_obligation_ids.intersection(incoming_ids):
        raise ValueError('LEARNING_OBLIGATION_ID_COLLISION')
    out=copy.deepcopy(base)
    out['authority_sources'].append(copy.deepcopy(authority))
    out['obligations'].extend(copy.deepcopy(obligations))
    return validate_obligation_manifest(out)
