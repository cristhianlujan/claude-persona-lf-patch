#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_additional_consumer_capability_map_v1.json'

def fail(msg): raise SystemExit('FAIL learning-additional-consumer-capability-map: '+msg)

def main():
 d=json.loads(P.read_text())
 if d.get('status')!='CANDIDATE_MAPPING_NOT_BOUND': fail('status')
 rows=d.get('mappings',[])
 expected={
  ('PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531','DIGITAL_SELF_SERVICE','AUTOGESTION_DIGITAL'),
  ('PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','PAYMENT_NO_ADEUDO','PAGOS_Y_NO_ADEUDO'),
  ('PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','NEGOCIACION_DEUDA','NEGOCIACION_DEUDA'),
 }
 got={(x.get('consumer_id'),x.get('capability_id'),x.get('cluster_code')) for x in rows}
 if got!=expected: fail('mapping set')
 for x in rows:
  if x.get('state')!='CANDIDATE_REQUIRES_BENCHMARK': fail('active mapping detected')
  if not x.get('required_prerequisites') or not x.get('must_not_authorize'): fail('authority boundary incomplete')
 b=d.get('binding_requirements',{})
 if b.get('routing_benchmark_cases')!=50 or b.get('routing_benchmark_families')!=10: fail('benchmark shape')
 if b.get('authority_pass_pct')!=100 or b.get('critical_false_positives')!=0 or b.get('must_not_invoke_required') is not True: fail('promotion gates')
 if d.get('active_learning_bindings_created')!=0 or d.get('implicit_binding') is not False or d.get('production_authorized') is not False: fail('binding/impact boundary')
 print('LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_MAP=PASS candidates=3 active_bindings=0 consumers=2 benchmark=50x10 authority=100 fp_critical=0')
if __name__=='__main__': main()
