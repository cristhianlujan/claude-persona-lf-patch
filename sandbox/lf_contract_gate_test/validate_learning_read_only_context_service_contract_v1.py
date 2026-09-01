#!/usr/bin/env python3
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_service_contract_v1.json'
def fail(x): raise SystemExit('FAIL learning-service-contract: '+x)
def main():
 d=json.loads(P.read_text());
 if d.get('status')!='CANDIDATO_READ_ONLY': fail('status')
 if d.get('route')!=['ACT-0001','EJECUCION_PERFIL_LF','CONSUMER_REGISTRY','EXACT_BINDING','DETERMINISTIC_CONTEXT_PACK','CONSUMER']: fail('route')
 e=d.get('eligibility') or {}; s=d.get('selection') or {}; ui=d.get('ui_authority') or {}
 if e.get('grounding_status')!='GROUNDED' or e.get('consumer_ready') is not True or e.get('exact_source_learning_id') is not True: fail('eligibility')
 if s.get('mode')!='DETERMINISTIC_EXACT_ID' or s.get('semantic_scope_expansion') is not False or s.get('llm_selector_calls')!=0 or s.get('additional_round_trips')!=0 or s.get('writes')!=0: fail('selection')
 if set(d.get('enabled_candidate_consumers') or [])!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('enabled')
 if set(d.get('blocked_consumers') or [])!={'FRONTEND_IMPLEMENTATION','GAMIFICATION','GENERIC_PROFILE'}: fail('blocked')
 if ui.get('product_direction_first') is not True or ui.get('current_required') is not True or ui.get('competitive_context_authority')!='UPSTREAM_CONSTRAINTS': fail('ui authority')
 if d.get('lifecycle')!='READY_FOR_BINDING' or d.get('behavioral_profile_ab')!='BENCHMARK_REQUIRED_PROFILE_RUNTIME': fail('lifecycle')
 if d.get('production_impact') is not False or d.get('automatic_promotion') is not False: fail('production')
 print('LEARNING_CONTEXT_SERVICE_CONTRACT=PASS consumers=2 router_first=1 deterministic=1 writes=0 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
