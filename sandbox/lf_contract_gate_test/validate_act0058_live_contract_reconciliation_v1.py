#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/evidence/ACT0058_LIVE_CONTRACT_RECONCILIATION_20260901.json'

def fail(msg: str):
    raise SystemExit('FAIL ACT0058_LIVE_RECONCILIATION: '+msg)

def main() -> int:
    p=json.loads(PATH.read_text(encoding='utf-8'))
    if p.get('schema')!='ACT0058_LIVE_CONTRACT_RECONCILIATION_EVIDENCE_V1': fail('schema')
    if p.get('operation_code')!='ORQUESTACION_PIPELINE_LF': fail('operation')
    if p.get('db_judge_writes')!=0 or p.get('db_binding_writes')!=0: fail('db writes')
    if p.get('production_authorized') is not False or p.get('automatic_impact') is not False: fail('impact')
    c=p.get('coverage') or {}
    if c.get('active_steps')!=14 or c.get('active_bindings')!=4 or c.get('missing_bindings')!=10: fail('coverage')
    if c.get('candidate_judges_source_resolved')!=10 or c.get('candidate_cases')!=30: fail('candidate coverage')
    rows={r.get('step_order'):r for r in p.get('live_contracts') or []}
    if set(rows)!={105,110}: fail('step set')
    if rows[105].get('reconciliation')!='ZERO_NEW_URLS_IS_CONTROLLED_NOOP_WARN_AFTER_ATTEMPT_AND_DEDUP': fail('restock boundary')
    if rows[110].get('reconciliation')!='RETRY_AT_3_IS_TERMINAL_FAILED_AND_CONTINUE_NEXT_URL; DO_NOT_RETRY': fail('retry boundary')
    if rows[105].get('active_binding_exists') is not False or rows[110].get('active_binding_exists') is not False: fail('binding status')
    print('ACT0058_LIVE_RECONCILIATION=PASS active=14 bound=4 missing=10 cases=30 source_only=PASS')
    return 0
if __name__=='__main__': raise SystemExit(main())
