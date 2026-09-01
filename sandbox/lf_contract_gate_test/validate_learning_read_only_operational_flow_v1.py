#!/usr/bin/env python3
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_operational_flow_v1.json'
def fail(x): raise SystemExit('FAIL learning-operational-flow: '+x)
def main():
 d=json.loads(P.read_text()); f=d.get('flow') or []
 if d.get('status')!='CANDIDATO_READ_ONLY' or [x.get('order') for x in f]!=list(range(1,12)): fail('order')
 by={x['stage']:x for x in f}
 if by['ROUTER'].get('asset')!='ACT-0001': fail('router')
 if by['CONSUMER_RESOLUTION'].get('mode')!='DETERMINISTIC_EXACT_BINDING': fail('resolver')
 if set(by['KB_ELIGIBILITY'].get('requirements') or [])!={'GROUNDED','consumer_ready=true','exact_source_learning_id'}: fail('eligibility')
 cp=by['CONTEXT_PACK'];
 if cp.get('mode')!='DETERMINISTIC_EXACT_ID' or cp.get('llm_calls')!=0 or cp.get('writes')!=0: fail('context pack')
 if set(by['DIRECT_CONSUMER'].get('allowed') or [])!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('direct')
 ind=by['INDIRECT_DOWNSTREAM'];
 if set(ind.get('allowed') or [])!={'ACT-0051','PERFIL-GAMIFICATION-SYSTEM-ARCHITECT'} or ind.get('raw_learning_context') is not False: fail('downstream')
 if by['ROUTING_CONTEXT_BENCHMARK'].get('cases')!=50 or by['ROUTING_CONTEXT_BENCHMARK'].get('families')!=10: fail('benchmark')
 if by['BEHAVIORAL_PROFILE_AB'].get('state')!='BENCHMARK_REQUIRED_PROFILE_RUNTIME' or by['PRODUCTION'].get('state')!='BLOCKED': fail('boundary')
 if d.get('production_impact') is not False: fail('impact')
 print('LEARNING_OPERATIONAL_FLOW=PASS direct=2 indirect=2 routing=50x10 behavioral=pending production=blocked')
 return 0
if __name__=='__main__': raise SystemExit(main())
