#!/usr/bin/env python3
from __future__ import annotations
from typing import Any

class DownstreamHandoffBlocked(ValueError): pass

FORBIDDEN_KEYS={'competitive_kb_rows','source_learning_ids','selected_evidence_refs','learning_context','competitor_claims'}

def _scan_forbidden(value:Any,path:str='$')->None:
 if isinstance(value,dict):
  for k,v in value.items():
   if k in FORBIDDEN_KEYS: raise DownstreamHandoffBlocked(f'FORBIDDEN_LEARNING_FIELD:{path}.{k}')
   _scan_forbidden(v,f'{path}.{k}')
 elif isinstance(value,list):
  for i,v in enumerate(value): _scan_forbidden(v,f'{path}[{i}]')

def build_frontend_handoff(*,product_direction_ref:str,ui_spec_ref:str,approved_constraints:dict[str,Any],current:bool)->dict[str,Any]:
 if current is not True: raise DownstreamHandoffBlocked('UPSTREAM_NOT_CURRENT')
 if not product_direction_ref or not ui_spec_ref: raise DownstreamHandoffBlocked('PRODUCT_UI_REFS_REQUIRED')
 _scan_forbidden(approved_constraints)
 return {'schema':'LF_LEARNING_INDIRECT_FRONTEND_HANDOFF_V1','consumer_id':'ACT-0051','authority_refs':[{'role':'PRODUCT_DIRECTION','ref':product_direction_ref,'currentness':'CURRENT'},{'role':'UI_ARCHITECT','ref':ui_spec_ref,'currentness':'CURRENT'}],'approved_constraints':approved_constraints,'direct_learning_context':False,'learning_llm_calls':0,'production_impact':False}

def build_gamification_handoff(*,objective_ref:str,authorized_objective:dict[str,Any],current:bool)->dict[str,Any]:
 if current is not True: raise DownstreamHandoffBlocked('OBJECTIVE_NOT_CURRENT')
 if not objective_ref: raise DownstreamHandoffBlocked('OBJECTIVE_REF_REQUIRED')
 _scan_forbidden(authorized_objective)
 return {'schema':'LF_LEARNING_INDIRECT_GAMIFICATION_HANDOFF_V1','consumer_id':'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT','authority_refs':[{'role':'AUTHORIZED_PRODUCT_OR_UX_OBJECTIVE','ref':objective_ref,'currentness':'CURRENT'}],'authorized_objective':authorized_objective,'direct_learning_context':False,'learning_llm_calls':0,'production_impact':False}
