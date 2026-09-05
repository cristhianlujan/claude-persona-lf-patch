#!/usr/bin/env python3
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/act0058_judge_cases_v1.json'
EXPECTED_STEPS={5,20,30,50,60,70,90,100,105,110}
EXPECTED_JUDGES={
 'MINI_JUDGE_ACT0058_INIT_EXECUTION','MINI_JUDGE_ACT0058_INIT','MINI_JUDGE_ACT0058_SCOPE',
 'MINI_JUDGE_ACT0058_CAPTURA','MINI_JUDGE_ACT0058_HOMOLOG','MINI_JUDGE_ACT0058_ANALISIS',
 'MINI_JUDGE_ACT0058_KB_WRITE','MINI_JUDGE_ACT0058_COMPLETED','MINI_JUDGE_ACT0058_RESTOCK',
 'MINI_JUDGE_ACT0058_RETRY'
}

def fail(msg): raise SystemExit('FAIL ACT0058_JUDGE_CASES: '+msg)
def main():
 p=json.loads(PATH.read_text(encoding='utf-8'))
 if p.get('schema')!='ACT0058_MINI_JUDGE_CASE_MATRIX_V2': fail('schema must be V2 material-evidence matrix')
 if p.get('operation_code')!='ORQUESTACION_PIPELINE_LF' or p.get('status')!='CANDIDATE_READ_ONLY' or p.get('production_impact') is not False: fail('unsafe header')
 cases=p.get('cases') or []
 if len(cases)!=30 or len({c['id'] for c in cases})!=30: fail('case cardinality')
 if {c['step_order'] for c in cases}!=EXPECTED_STEPS: fail('step coverage')
 if {c['judge'] for c in cases}!=EXPECTED_JUDGES: fail('judge coverage')
 counts=Counter(c['judge'] for c in cases)
 if any(v!=3 for v in counts.values()): fail(f'expected 3 per judge: {dict(counts)}')
 expected_values={c['expected'] for c in cases}
 for required in ['RESTOCK_COMPLETED','RESTOCK_NOOP_WARN','RESTOCK_BLOCKED','RETRY_ALLOWED','RETRY_TERMINAL_FAILED','RETRY_BLOCKED']:
  if required not in expected_values: fail('missing edge result '+required)
 if not any(c['id']=='RESTOCK_NOOP' and c['input'].get('urls_insertadas')==0 and c['input'].get('warn_event_recorded') is True for c in cases): fail('restock noop boundary')
 retry=[c for c in cases if c['judge']=='MINI_JUDGE_ACT0058_RETRY']
 if any('next_action' in c['input'] for c in retry): fail('synthetic next_action forbidden')
 if any(not {'retry_count','stage_status','error_detail'} <= set(c['input']) for c in retry): fail('retry cases must use material UPDATE evidence')
 if not any(c['id']=='RETRY_TERMINAL' and c['input'].get('retry_count')==3 and c['input'].get('stage_status')=='FAILED' for c in retry): fail('retry terminal boundary')
 if not any(c['id']=='RETRY_BLOCK_OVER' and c['input'].get('retry_count')==3 and c['input'].get('stage_status')!='FAILED' for c in retry): fail('retry over-limit negative boundary')
 print('ACT0058_JUDGE_CASES=PASS cases=30 judges=10 per_judge=3 restock_noop=PASS retry_runtime_evidence=PASS')
 return 0
if __name__=='__main__': raise SystemExit(main())
