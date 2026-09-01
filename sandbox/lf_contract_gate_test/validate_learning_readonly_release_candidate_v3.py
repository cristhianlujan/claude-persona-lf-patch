#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_readonly_release_candidate_run037_v3.json'
WAIT=ROOT/'sandbox/lf_contract_gate_test/learning_source_parity_wait_run037.json'

def fail(msg: str): raise SystemExit('FAIL LEARNING_READONLY_RC_V3: '+msg)
def main() -> int:
 p=json.loads(PATH.read_text(encoding='utf-8')); w=json.loads(WAIT.read_text(encoding='utf-8'))
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
 if c.get('current_candidate_head')!='934027448b6b733af059407cc6291ac7463c3b6e': fail('CI head')
 if c.get('validate_lf_packs',{}).get('status')!='SUCCESS' or c.get('bootstrap',{}).get('status')!='SUCCESS': fail('CI auxiliary')
 if c.get('lf_contract_check',{}).get('first_bad_step')!='LF_MIGRATION_SOURCE_PARITY': fail('CI first bad step')
 if c.get('live_missing_source_version')!='20260901151435' or c.get('external_source_pr')!=408: fail('source parity ownership')
 if c.get('learning_contract_regression_proven') is not False: fail('regression classification')
 if w.get('classification')!='WAITING_SOURCE_PARITY_EXTERNAL_CARRIL' or w.get('forbidden_action')!='COPY_EXTERNAL_MIGRATION_INTO_LEARNING_PR_ONLY_TO_GREEN_CI': fail('wait contract')
 if p.get('promotion')!='BLOCKED_RUNTIME_AUTHORITY_AND_EXTERNAL_SOURCE_PARITY_AND_GLOBAL_EXACT_HEAD_CI': fail('promotion')
 if p.get('production_authorized') is not False or p.get('automatic_impact') is not False: fail('impact')
 print('LEARNING_READONLY_RC_V3=PASS kb=35/35 runtime=BLOCKED ci=WAITING_SOURCE_PARITY_20260901151435 no_cross_carril_copy=PASS')
 return 0
if __name__=='__main__': raise SystemExit(main())
