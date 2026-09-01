#!/usr/bin/env python3
from __future__ import annotations
from typing import Any
import yaml
from learning_read_only_consumer_resolver_v1 import resolve_consumer,ConsumerRouteBlocked
from learning_read_only_context_selector_v2 import BindingSpec,select_read_only_context

class LearningContextBlocked(ValueError): pass

def build_context(*,consumer_id:str,binding_id:str,rows:list[dict[str,Any]],upstream_current:bool|None=None,upstream_artifact_ref:str|None=None)->dict[str,Any]:
 route=resolve_consumer(consumer_id)
 if route['upstream_required']:
  if upstream_current is not True: raise LearningContextBlocked('UPSTREAM_AUTHORITY_NOT_CURRENT')
  if not upstream_artifact_ref: raise LearningContextBlocked('UPSTREAM_ARTIFACT_REQUIRED')
 doc=yaml.safe_load(route['binding_file'].read_text(encoding='utf-8'))
 item=next((x for x in (doc.get('bindings') or []) if x.get('binding_id')==binding_id),None)
 if item is None: raise LearningContextBlocked('EXACT_BINDING_NOT_FOUND')
 if item.get('consumer_id')!=consumer_id: raise LearningContextBlocked('BINDING_CONSUMER_MISMATCH')
 refs=item.get('selected_evidence_refs') or []
 budget=int((item.get('context_budget') or {}).get('max_bytes',6000))
 spec=BindingSpec(consumer_id=consumer_id,capability_id=item['capability_id'],source_learning_ids=tuple(item.get('source_learning_ids') or ()),max_evidence_refs=min(5,len(refs) or 5),max_context_bytes=min(6000,budget))
 out=select_read_only_context(rows,binding=spec)
 out.update({'router_asset':route['router_asset'],'router_action':route['router_action'],'binding_id':binding_id,'upstream_artifact_ref':upstream_artifact_ref,'read_only':True,'writes':0,'production_impact':False})
 return out
