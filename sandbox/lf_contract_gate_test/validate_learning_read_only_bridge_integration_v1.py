#!/usr/bin/env python3
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_bridge_integration_v1.yaml'
def fail(x): raise SystemExit('FAIL learning-bridge-integration: '+x)
def main():
 d=yaml.safe_load(P.read_text()); u=d.get('upstream_bridge') or {}; s=d.get('service') or {}; b=d.get('boundaries') or {}
 if d.get('status')!='CANDIDATO_READ_ONLY': fail('status')
 if u.get('action_code')!='KNOWLEDGE_LEARNING_BRIDGE' or u.get('operation_code')!='LEARNING_BRIDGE_KB_CARD_LF' or u.get('router_asset')!='ACT-0001': fail('upstream identity')
 if u.get('status_observed')!='CANDIDATO_READ_ONLY' or u.get('step_count')!=25: fail('upstream state')
 for key in ('contract_ref','steps_ref','judge_ref'):
  if not (ROOT/u[key]).is_file(): fail('missing '+key)
 if s.get('role')!='DOWNSTREAM_READ_ONLY_CONSUMER_CONTEXT' or s.get('duplicate_learning_engine') is not False: fail('service role')
 if s.get('selection')!='DETERMINISTIC_EXACT_BINDING' or s.get('writes')!=0 or s.get('selector_llm_calls')!=0 or s.get('additional_round_trips')!=0: fail('efficiency')
 if set(s.get('direct_consumers') or [])!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('direct consumers')
 if set(s.get('indirect_consumers') or [])!={'ACT-0051','PERFIL-GAMIFICATION-SYSTEM-ARCHITECT'}: fail('indirect consumers')
 if any(b.get(k) is not True for k in ('card_factory_not_replaced','lifecycle_not_skipped','bridge_judge_not_replaced','behavioral_profile_ab_separate')): fail('governance boundary')
 if b.get('automatic_impact') is not False or b.get('production') is not False: fail('impact')
 print('LEARNING_BRIDGE_INTEGRATION=PASS upstream=LEARNING_BRIDGE_KB_CARD_LF steps=25 duplicate_engine=0 direct=2 indirect=2 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
