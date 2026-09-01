#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_readonly_release_candidate_run037_v3.json'

def fail(msg: str): raise SystemExit('FAIL LEARNING_READONLY_RC_V3: '+msg)
def main() -> int:
 p=json.loads(PATH.read_text(encoding='utf-8'))
 if p.get('schema')!='LF_LEARNING_READONLY_RELEASE_CANDIDATE_V3': fail('schema')
 if p.get('status')!='CANDIDATO_READ_ONLY': fail('status')
 cp=p.get('consumer_path') or {}
 if cp.get('product_director',{}).get('routing')!='50/50_PASS': fail('product routing')
 if cp.get('ui_architect',{}).get('routing')!='50/50_PASS': fail('ui routing')
 if cp.get('downstream_no_bypass')!='40/40_PASS': fail('downstream')
 if cp.get('product_director',{}).get('runtime_enabled') is not False or cp.get('ui_architect',{}).get('runtime_enabled') is not False: fail('runtime fail-closed')
 d=p.get('dynamic_selector') or {}
 if (d.get('eligible_competitive_kb'),d.get('classified'),d.get('unclassified'))!=(35,35,0): fail('kb coverage')
 if d.get('llm_calls')!=0 or d.get('round_trips')!=0: fail('selector efficiency')
 if d.get('challenger_exact_cluster_match_pct')!=100.0 or d.get('champion_exact_cluster_match_pct')!=70.59: fail('selector A/B')
 g=p.get('governance') or {}
 if g.get('router_asset')!='ACT-0001' or g.get('router_state')!='ACTIVO' or g.get('router_runtime')!='RUNTIME_OPERATIVO': fail('router')
 if g.get('automatic_impact')!='BLOQUEADO' or g.get('profile_adapter_runtime_enabled') is not False: fail('authority')
 b=p.get('behavioral') or {}
 if b.get('runtime_invoked') is not False or b.get('holdout_consumed') is not False or b.get('result')!='INSUFFICIENT_EVIDENCE_RUNTIME_DISABLED': fail('behavioral')
 s=p.get('source_pipeline') or {}
 if (s.get('act0058_active_steps'),s.get('act0058_active_judge_bindings'),s.get('act0058_missing_judge_bindings'))!=(14,4,10): fail('act0058')
 if s.get('candidate_judges_source_resolved')!=10 or s.get('candidate_judge_cases')!=30 or s.get('pending_recovered_sources')!=6: fail('source candidate coverage')
 c=p.get('ci') or {}
 if c.get('lf_contract_check')!='FAIL_CI_E16_001' or c.get('contract_and_parity_steps_before_e16')!='PASS': fail('CI classification')
 if p.get('promotion')!='BLOCKED_RUNTIME_AUTHORITY_AND_GLOBAL_EXACT_HEAD_CI': fail('promotion')
 if p.get('production_authorized') is not False or p.get('automatic_impact') is not False: fail('impact')
 print('LEARNING_READONLY_RC_V3=PASS kb=35/35 routing=50+50 downstream=40 runtime=BLOCKED ci=CI-E16-001')
 return 0
if __name__=='__main__': raise SystemExit(main())
