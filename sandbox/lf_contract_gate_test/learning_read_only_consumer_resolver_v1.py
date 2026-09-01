#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
from typing import Any
import yaml
ROOT=Path(__file__).resolve().parents[2]
S=ROOT/'sandbox/lf_contract_gate_test'
REG=S/'learning_read_only_consumer_registry_v1.yaml'
class ConsumerRouteBlocked(ValueError): pass

def resolve_consumer(consumer_id:str)->dict[str,Any]:
 d=yaml.safe_load(REG.read_text(encoding='utf-8'))
 for blocked in d.get('blocked_consumers') or []:
  if blocked.get('consumer_id')==consumer_id:
   raise ConsumerRouteBlocked(blocked.get('state','BLOCKED_NO_EXACT_BINDING'))
 for item in d.get('consumers') or []:
  if item.get('consumer_id')==consumer_id:
   if item.get('read_only_enabled_candidate') is not True: raise ConsumerRouteBlocked('READ_ONLY_NOT_ENABLED')
   bp=(S/item['binding_file']).resolve(); cp=(S/item['context_pack_file']).resolve()
   if bp.parent!=S.resolve() or cp.parent!=S.resolve() or not bp.is_file() or not cp.is_file(): raise ConsumerRouteBlocked('CONSUMER_CONTRACT_PATH_INVALID')
   return {'consumer_id':consumer_id,'router_asset':d['router_asset'],'router_action':d['router_action'],'binding_file':bp,'context_pack_file':cp,'upstream_required':bool(item.get('upstream_required')),'upstream_consumer_id':item.get('upstream_consumer_id'),'upstream_artifact':item.get('upstream_artifact'),'upstream_current_required':bool(item.get('upstream_current_required')),'production_impact':False}
 raise ConsumerRouteBlocked('BLOCKED_NO_EXACT_BINDING')
