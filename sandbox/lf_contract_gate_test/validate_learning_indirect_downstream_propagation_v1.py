#!/usr/bin/env python3
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_indirect_downstream_propagation_v1.yaml'
def fail(x): raise SystemExit('FAIL learning-downstream-propagation: '+x)
def main():
 d=yaml.safe_load(P.read_text()); chain=d.get('chain') or []
 if d.get('status')!='CANDIDATO_READ_ONLY' or len(chain)!=4: fail('root')
 product,ui,front,game=chain
 if product.get('direct_learning_context') is not True or ui.get('direct_learning_context') is not True: fail('direct owners')
 if ui.get('upstream_required')!='product_direction_ref': fail('ui upstream')
 if front.get('consumer_id')!='ACT-0051' or front.get('direct_learning_context') is not False: fail('frontend')
 if set(front.get('upstream_required') or [])!={'product_direction_ref','ui_spec_ref'}: fail('frontend authority')
 if 'competitive_kb_rows' not in (front.get('must_not_receive') or []): fail('frontend KB leak')
 if game.get('direct_learning_context') is not False or game.get('upstream_required')!=['authorized_product_or_ux_objective']: fail('gamification')
 r=d.get('rules') or {}
 if r.get('learning_influence_must_be_materialized_upstream') is not True or r.get('direct_frontend_learning_binding') is not False or r.get('direct_gamification_learning_binding') is not False: fail('rules')
 if r.get('no_extra_learning_llm_call_downstream') is not True or r.get('production_impact') is not False: fail('efficiency/impact')
 print('LEARNING_DOWNSTREAM_PROPAGATION=PASS direct_consumers=2 indirect_frontend=1 indirect_gamification=1 extra_learning_llm=0 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
