#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_readonly_release_candidate_run037_v4.json'
WAIT=ROOT/'sandbox/lf_contract_gate_test/learning_source_parity_wait_run037.json'
ELIG=ROOT/'sandbox/lf_contract_gate_test/learning_additional_consumer_eligibility_run037.json'

def fail(msg: str) -> None: raise SystemExit('FAIL LEARNING_READONLY_RC_V4: '+msg)
def main() -> int:
 p=json.loads(PATH.read_text(encoding='utf-8')); w=json.loads(WAIT.read_text(encoding='utf-8')); e=json.loads(ELIG.read_text(encoding='utf-8'))
 if p.get('schema')!='LF_LEARNING_READONLY_RELEASE_CANDIDATE_V4' or p.get('status')!='CANDIDATO_READ_ONLY': fail('header')
 cp=p.get('consumer_path') or {}
 for cid in ['product_director','ui_architect']:
  row=cp.get(cid) or {}
  if row.get('routing')!='50/50_PASS' or row.get('profile_registry_present') is not True or row.get('profile_state')!='READ_ONLY': fail(cid+' route')
  if row.get('profile_runtime_state')!='NO_HABILITADO' or row.get('adapter_runtime_enabled') is not True: fail(cid+' runtime boundary')
 if cp.get('downstream_no_bypass')!='40/40_PASS' or cp.get('additional_direct_consumers')!=0: fail('downstream/additional')
 d=p.get('dynamic_selector') or {}
 if (d.get('eligible_competitive_kb'),d.get('classified'),d.get('unclassified'))!=(35,35,0): fail('KB coverage')
 if d.get('llm_calls')!=0 or d.get('round_trips')!=0 or d.get('challenger_exact_cluster_match_pct')!=100.0: fail('selector')
 g=p.get('governance') or {}
 if g.get('router_asset')!='ACT-0001' or g.get('router_state')!='ACTIVO' or g.get('router_runtime')!='RUNTIME_OPERATIVO' or g.get('automatic_impact')!='BLOQUEADO': fail('router')
 b=p.get('behavioral') or {}
 if b.get('runtime_invoked') is not False or b.get('holdout_consumed') is not False or b.get('result')!='INSUFFICIENT_EVIDENCE_RUNTIME_DISABLED': fail('behavioral')
 s=p.get('source_pipeline') or {}
 if (s.get('act0058_active_steps'),s.get('act0058_required_steps'),s.get('act0058_active_judge_bindings'),s.get('act0058_missing_judge_bindings'),s.get('act0058_required_missing_judge_bindings'))!=(14,13,4,10,9): fail('act0058 inventory')
 if s.get('candidate_judges_source_resolved')!=10 or s.get('candidate_judge_cases')!=30 or s.get('candidate_judge_local_reexecution')!='30/30_PASS' or s.get('candidate_judge_exact_head_ci') is not False: fail('act0058 evidence boundary')
 sp=p.get('source_parity') or {}
 if sp.get('dedicated_pr')!=408 or sp.get('source_candidates_materialized') is not True: fail('parity owner')
 if sp.get('lf_migration_parity_step')!='SUCCESS' or sp.get('input_governance_parity_step')!='SUCCESS' or sp.get('main_materialized') is not False: fail('parity boundary')
 if w.get('schema')!='LF_LEARNING_SOURCE_PARITY_WAIT_V2' or w.get('classification')!='WAITING_SOURCE_PARITY_MAIN_MATERIALIZATION': fail('wait state')
 if e.get('schema')!='LF_LEARNING_ADDITIONAL_CONSUMER_ELIGIBILITY_V1': fail('eligibility evidence')
 if len(e.get('direct_read_only_consumers') or [])!=2 or len(e.get('not_eligible_for_new_direct_binding') or [])!=3: fail('eligibility cardinality')
 if p.get('production_authorized') is not False or p.get('automatic_impact') is not False: fail('impact')
 print('LEARNING_READONLY_RC_V4=PASS kb=35/35 direct_consumers=2 additional_direct=0 parity_source=REPAIRED_WAIT_MAIN act0058=30/30_LOCAL_WAIT_EXACT_CI')
 return 0
if __name__=='__main__': raise SystemExit(main())
