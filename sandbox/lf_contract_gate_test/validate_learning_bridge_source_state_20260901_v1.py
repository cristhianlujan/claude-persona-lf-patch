#!/usr/bin/env python3
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_bridge_source_state_20260901_v1.json'
def fail(x): raise SystemExit('FAIL learning-bridge-source-state: '+x)
def main():
 d=json.loads(P.read_text()); r=d.get('router_source') or {}; p=d.get('promotion_source') or {}; s=d.get('step_contracts') or {}
 if d.get('operation')!='LEARNING_BRIDGE_KB_CARD_LF' or d.get('router_action')!='KNOWLEDGE_LEARNING_BRIDGE': fail('identity')
 if r.get('declares_status')!='ACTIVE' or r.get('write_allowed') is not False: fail('router source')
 if p.get('declares_operation_status')!='PRODUCCION_CONTROLADA_READ_ONLY': fail('promotion source')
 if any(p.get(k) is not True for k in ('runtime_disabled','production_disabled','automatic_impact_disabled')): fail('boundaries')
 if s.get('count')!=25 or s.get('status')!='ACTIVE_ENFORCEMENT': fail('steps')
 if d.get('evidence_level')!='SOURCE_DECLARED_DB_UNVERIFIED_THIS_RUN': fail('evidence level')
 if 'do not claim live DB activation' not in d.get('safe_interpretation',''): fail('safe interpretation')
 print('LEARNING_BRIDGE_SOURCE_STATE=PASS source_active=1 write_allowed=0 source_controlled_read_only=1 live_db=UNVERIFIED production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
