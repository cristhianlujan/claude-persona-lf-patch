#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_additional_consumer_inventory_v1.json'

def fail(msg): raise SystemExit('FAIL learning-additional-consumer-inventory: '+msg)

def main():
 d=json.loads(P.read_text())
 if d.get('status')!='DISCOVERED_NOT_BOUND': fail('status')
 cs=d.get('consumers',[])
 ids={x.get('consumer_id') for x in cs}
 expected={'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531','PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531'}
 if ids!=expected: fail('consumer set')
 for x in cs:
  if x.get('consumer_type')!='PROFILE' or x.get('adapter_status')!='CANDIDATO_READ_ONLY_NO_HABILITADO': fail('adapter boundary')
  if x.get('router_bound_only') is not True: fail('router-first')
  if x.get('learning_binding_state')!='NO_EXACT_LEARNING_BINDING_YET': fail('implicit learning binding')
  req=set(x.get('required_before_binding',[]))
  if '50_CASE_10_FAMILY_ROUTING_BENCHMARK' not in req or 'MUST_NOT_INVOKE_CASES' not in req: fail('benchmark gate')
 if d.get('implicit_consumer_selection') is not False or d.get('direct_learning_injection') is not False or d.get('production_authorized') is not False: fail('impact boundary')
 print('LEARNING_ADDITIONAL_CONSUMER_INVENTORY=PASS discovered=2 bound=0 router_only=2 production=0')
if __name__=='__main__': main()
