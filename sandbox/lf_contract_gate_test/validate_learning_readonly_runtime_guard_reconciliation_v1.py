#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_readonly_runtime_guard_reconciliation_run037.json'

def fail(msg: str):
    raise SystemExit('FAIL LEARNING_RUNTIME_GUARD_RECONCILIATION: '+msg)

def main() -> int:
    p=json.loads(PATH.read_text(encoding='utf-8'))
    if p.get('schema')!='LF_LEARNING_READONLY_RUNTIME_GUARD_RECONCILIATION_V1': fail('schema')
    if p.get('mode')!='READ_ONLY': fail('mode')
    r=p.get('router') or {}
    if r.get('asset')!='ACT-0001' or r.get('state')!='ACTIVO' or r.get('runtime_state')!='RUNTIME_OPERATIVO': fail('router')
    if r.get('automatic_impact')!='BLOQUEADO': fail('router impact')
    consumers=p.get('consumers') or []
    if {c.get('consumer_id') for c in consumers}!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('consumers')
    if any(c.get('runtime_enabled') is not False for c in consumers): fail('runtime must be disabled')
    if any(c.get('input_governance_receipt_required') is not True for c in consumers): fail('governance receipt')
    k=p.get('knowledge_path') or {}
    if (k.get('eligible_competitive_kb'),k.get('classified_distinct'),k.get('unclassified'))!=(35,35,0): fail('knowledge coverage')
    if k.get('selector_llm_calls')!=0 or k.get('selector_round_trips')!=0: fail('selector efficiency')
    a=p.get('act0058') or {}
    if (a.get('active_steps'),a.get('active_judge_bindings'),a.get('missing_judge_bindings'))!=(14,4,10): fail('act0058 coverage')
    if p.get('result')!='READ_ONLY_CONTEXT_ARTIFACTS_VALID_TO_INSPECT_BUT_CONSUMER_RUNTIME_INVOCATION_BLOCKED': fail('result')
    if p.get('promotion_authorized') is not False or p.get('production_authorized') is not False or p.get('automatic_impact') is not False: fail('authority')
    print('LEARNING_RUNTIME_GUARD_RECONCILIATION=PASS kb=35/35 runtime=BLOCKED deterministic=PASS')
    return 0
if __name__=='__main__': raise SystemExit(main())
