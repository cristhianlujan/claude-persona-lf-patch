#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
ART=HERE/'gate_f_exact_materialized_output.json'; MODEL=HERE/'gate_f_exact_model_output.json'
EVID=HERE/'gate_f_exact_runtime_evidence.json'; FOUT=HERE/'gate_f_output.json'; GOUT=HERE/'gate_g_output.json'; HOUT=HERE/'gate_h_output.json'; REQ=HERE/'expected_requirements.json'
UI=ROOT/'profiles/ui_architect/validators/validate_ui_architect_output.py'; BOUND=ROOT/'profiles/ui_architect/validators/validate_composer_payload_boundary.py'
def load(p):
 x=json.loads(p.read_text(encoding='utf-8'))
 if not isinstance(x,dict): raise RuntimeError('NOT_OBJECT:'+p.name)
 return x
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def mod(p,n):
 s=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def cmap(x): return {str(n['component_id']):n for n in (x.get('deliverable_created') or {}).get('component_tree',[]) if isinstance(n,dict) and n.get('component_id')}
def material_errors(x):
 e=[]; d=x.get('deliverable_created') or {}; screen=d.get('screen_definition') or {}; req=load(REQ); c=cmap(x)
 if screen.get('task_mode')!='CREATE_NEW': e.append('TASK_MODE_NOT_CREATE_NEW')
 if not set(req['required_sections']).issubset(set(screen.get('required_sections') or [])): e.append('REQUIRED_SECTIONS_MISSING')
 if set(screen.get('design_intent') or [])!=set(req['required_design_intents']): e.append('DESIGN_INTENT_INCOMPLETE')
 if screen.get('implementation_readiness')!='STRUCTURED_SPEC_READY_FOR_NEXT_AGENT': e.append('IMPLEMENTATION_HANDOFF_NOT_READY')
 required={'header_search','category_navigation','featured_services','service_cards','service_card_template','service_title','service_provider','service_price','service_cta'}
 miss=sorted(required-set(c))
 if miss: e.append('MATERIAL_COMPONENTS_MISSING:'+','.join(miss))
 fields=((c.get('service_card_template') or {}).get('content') or {}).get('fields') or []
 if set(fields)!=set(req['required_service_card_fields']): e.append('SERVICE_CARD_FIELDS_INCOMPLETE')
 if 'remediation_actions' in d: e.append('CREATE_NEW_REMEDIATION_FORBIDDEN')
 if (x.get('handoff_to_next') or {}).get('payload_ref')!='composer_payload': e.append('COMPOSER_HANDOFF_NOT_BOUND')
 if 'prompt_constraints' in (x.get('composer_payload') or {}): e.append('PROMPT_CONSTRAINTS_LEAKED_TO_COMPOSER')
 return e
def main():
 x=load(ART); ev=load(EVID); f=load(FOUT); g=load(GOUT); h=load(HOUT)
 if ev.get('candidate_source_sha')!='d8c10954d5a6058ffdde7f4b520efcbabf50d180': raise RuntimeError('SOURCE_SHA_INVALID')
 if ev.get('outputs',{}).get('materialized_raw_output_sha256')!=sha(ART) or ev.get('outputs',{}).get('model_raw_output_sha256')!=sha(MODEL): raise RuntimeError('EXACT_ARTIFACT_BINDING_INVALID')
 if f.get('status')!='PASS' or f.get('next_gate')!='G_STRUCTURED_OUTPUT' or f.get('decision',{}).get('next_gate_authorized') is not True: raise RuntimeError('GATE_F_NOT_AUTHORIZING_G')
 ui=mod(UI,'s26_ui_g_exact'); bound=mod(BOUND,'s26_bound_g_exact')
 if ui.validate(x): raise RuntimeError('G_UI_VALIDATOR_FAILED')
 if bound.validate(x): raise RuntimeError('G_COMPOSER_BOUNDARY_FAILED')
 if material_errors(x): raise RuntimeError('H_MATERIAL_REQUIREMENTS_FAILED:'+','.join(material_errors(x)))
 if g.get('status')!='PASS' or g.get('next_gate')!='H_MATERIAL_REQUIREMENTS' or g.get('upstream',{}).get('source_sha256')!=sha(FOUT) or g.get('artifact',{}).get('sha256')!=sha(ART): raise RuntimeError('G_PERSISTED_BINDING_INVALID')
 if h.get('status')!='PASS' or h.get('next_gate')!='I_EVIDENCE' or h.get('upstream',{}).get('source_sha256')!=sha(GOUT) or h.get('artifact',{}).get('sha256')!=sha(ART): raise RuntimeError('H_PERSISTED_BINDING_INVALID')
 neg={}
 y=copy.deepcopy(x); y['deliverable_created']['component_tree']=[n for n in y['deliverable_created']['component_tree'] if n.get('component_id')!='header_search']; neg['missing_search']=bool(material_errors(y))
 y=copy.deepcopy(x); [n['content'].__setitem__('fields',['title','provider','call_to_action']) for n in y['deliverable_created']['component_tree'] if n.get('component_id')=='service_card_template']; neg['missing_price']=bool(material_errors(y))
 y=copy.deepcopy(x); y['deliverable_created']['screen_definition']['design_intent']=['clear','easy_to_navigate']; neg['missing_professional_intent']=bool(material_errors(y))
 y=copy.deepcopy(x); y['deliverable_created']['remediation_actions']=[{'x':1}]; neg['create_new_remediation']=bool(material_errors(y))
 y=copy.deepcopy(x); y['composer_payload']['execution_id']='forbidden'; neg['composer_metadata_leak']=bool(bound.validate(y))
 if not all(neg.values()): raise RuntimeError('G_H_NEGATIVE_FALSE_PASS')
 print(json.dumps({'gate':'S26_HP001_EXACT_G_H_V1','result':'PASS','candidate_source_sha':ev['candidate_source_sha'],'materialized_output_sha256':sha(ART),'gate_g_sha256':sha(GOUT),'gate_h_sha256':sha(HOUT),'negative_controls':neg,'independent_semantic_review_performed':False,'production_effect':False,'next_stage':'I_EVIDENCE','claim_ceiling':'G_H_EXACT_RUNTIME_VALIDATED_PENDING_INDEPENDENT_REVIEW_NOT_GOLDEN'},sort_keys=True))
 return 0
if __name__=='__main__': raise SystemExit(main())
