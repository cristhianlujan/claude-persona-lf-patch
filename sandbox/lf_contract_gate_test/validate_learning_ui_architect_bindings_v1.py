#!/usr/bin/env python3
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_ui_architect_bindings_v1.yaml'
REQ={'version','consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','source_learning_ids','champion_id','challenger_id','provenance'}
def fail(x): raise SystemExit('FAIL learning-ui-bindings: '+x)
def main():
 d=yaml.safe_load(P.read_text()); c=d.get('consumer') or {}; b=d.get('bindings') or []
 if d.get('status')!='CANDIDATO_READ_ONLY': fail('status')
 if c.get('consumer_id')!='PERFIL-UI-ARCHITECT' or c.get('upstream_required_consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF': fail('authority chain')
 if c.get('upstream_current_required') is not True or c.get('competitive_context_authority_type')!='UPSTREAM_CONSTRAINTS': fail('upstream current')
 if len(b)!=3: fail('expected 3 bindings')
 seen=set()
 for x in b:
  miss=REQ-set(x); bid=x.get('binding_id');
  if miss: fail(f'{bid} missing {sorted(miss)}')
  if bid in seen: fail('duplicate binding'); seen.add(bid)
  if x['consumer_id']!='PERFIL-UI-ARCHITECT' or x['router_action']!='EJECUCION_PERFIL_LF': fail('consumer/router')
  if x['lifecycle_state']!='READY_FOR_BINDING': fail('lifecycle')
  if 'product_direction_missing_or_stale' not in x['must_not_invoke_when']: fail('stale product gate')
  if len(x['selected_evidence_refs'])<1 or len(x['selected_evidence_refs'])>5: fail('evidence cardinality')
  if int(x['context_budget']['max_bytes'])>5000 or x['context_budget']['selection']!='DETERMINISTIC_FIRST': fail('context budget')
  if x['provenance'].get('automatic_impact') is not False: fail('automatic impact')
 if (d.get('rollback') or {}).get('production_impact') is not False: fail('production impact')
 print('LEARNING_UI_ARCHITECT_BINDINGS=PASS exact=3 upstream_product_current=1 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
