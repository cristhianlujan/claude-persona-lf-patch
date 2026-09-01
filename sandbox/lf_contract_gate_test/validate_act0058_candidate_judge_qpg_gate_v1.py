#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/act0058_candidate_judge_qpg_gate_v1.json'
BENCH=ROOT/'sandbox/lf_contract_gate_test/benchmark_act0058_candidate_judges_v1.py'

def fail(msg: str): raise SystemExit('FAIL ACT0058_QPG_GATE: '+msg)
def main() -> int:
 p=json.loads(PATH.read_text(encoding='utf-8'))
 if p.get('schema')!='ACT0058_CANDIDATE_JUDGE_QPG_GATE_V2' or p.get('status')!='BENCHMARK_REQUIRED': fail('header')
 s=p.get('candidate_scope') or {}
 if (s.get('judges'),s.get('cases'),s.get('cases_per_judge'))!=(10,30,3): fail('scope')
 if s.get('active_bindings_before')!=4 or s.get('candidate_bindings_to_activate')!=0 or s.get('required_missing_bindings')!=9: fail('binding boundary')
 q=p.get('quality_gate') or {}
 if q.get('required_accuracy_pct')!=100.0 or q.get('required_critical_false_positives')!=0 or q.get('required_case_pass')!='30/30': fail('quality')
 if q.get('restock_noop_boundary_required') is not True or q.get('retry_terminal_at_3_required') is not True: fail('edge gates')
 if q.get('retry_material_evidence_required')!=['retry_count','stage_status','error_detail'] or q.get('synthetic_next_action_forbidden') is not True: fail('retry material evidence')
 perf=p.get('performance_gate') or {}
 if perf.get('selector_llm_calls_required')!=0 or perf.get('round_trips_required')!=0 or perf.get('deterministic_share_pct_required')!=100.0: fail('performance')
 if perf.get('no_network_or_tool_call_per_case') is not True: fail('network')
 gov=p.get('governance_gate') or {}
 for k in ['router_first','source_migration_exact_head_ci_required','real_execution_provenance_required','contract_105_110_apply_before_binding','candidate_judges_apply_before_binding','live_readback_required_before_activation','no_active_binding_in_candidate_migration']:
  if gov.get(k) is not True: fail('governance '+k)
 if gov.get('production_authorized') is not False or gov.get('automatic_impact') is not False: fail('impact')
 if p.get('current_outcome')!='INSUFFICIENT_EVIDENCE': fail('must fail closed before benchmark')
 if not BENCH.exists(): fail('benchmark missing')
 print('ACT0058_QPG_GATE=PASS state=BENCHMARK_REQUIRED quality=30/30_required deterministic=100% activation=0 retry_material_evidence=REQUIRED')
 return 0
if __name__=='__main__': raise SystemExit(main())
