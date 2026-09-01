#!/usr/bin/env python3
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_readiness_matrix_v1.json'
def fail(x): raise SystemExit('FAIL learning-readiness: '+x)
def main():
 d=json.loads(P.read_text()); c=d.get('consumers') or []
 if d.get('status')!='CANDIDATO_READ_ONLY' or len(c)!=2: fail('scope')
 ids={x['consumer_id'] for x in c}
 if ids!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('consumers')
 for x in c:
  if not all(x.get(k) is True for k in ('exact_binding_contract','deterministic_context_pack','reader_supported')): fail('read path')
  if x.get('routing_context_benchmark_cases')!=50 or x.get('routing_context_benchmark_families')!=10: fail('benchmark')
  if x.get('behavioral_profile_ab')!='BENCHMARK_REQUIRED_PROFILE_RUNTIME': fail('behavioral boundary')
  if x.get('lifecycle')!='READY_FOR_BINDING' or x.get('production') is not False: fail('lifecycle/production')
 r=d.get('shared_reader') or {}
 if r.get('selection')!='DETERMINISTIC_EXACT_ID' or r.get('selector_llm_calls')!=0 or r.get('selector_round_trips')!=0 or r.get('writes')!=0: fail('reader')
 if r.get('semantic_scope_expansion') is not False: fail('semantic expansion')
 p=d.get('promotion_boundary') or {}
 if any(p.get(k) is not False for k in ('automatic','production','champion_replacement')): fail('promotion')
 if set(d.get('blocked_consumers') or [])!={'FRONTEND_IMPLEMENTATION','GAMIFICATION','GENERIC_PROFILE'}: fail('blocked')
 print('LEARNING_READ_ONLY_READINESS=PASS consumers=2 routing=50x10 behavioral=pending production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
