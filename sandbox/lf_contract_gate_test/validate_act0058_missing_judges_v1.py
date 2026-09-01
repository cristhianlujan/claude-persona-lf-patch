#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'sandbox/lf_contract_gate_test/act0058_missing_judges_v1.yaml'
EXPECTED = {
    (5,'init_execution','MINI_JUDGE_ACT0058_INIT_EXECUTION'),
    (20,'init_run','MINI_JUDGE_ACT0058_INIT'),
    (30,'scope_filter','MINI_JUDGE_ACT0058_SCOPE'),
    (50,'stage_captura','MINI_JUDGE_ACT0058_CAPTURA'),
    (60,'stage_homolog','MINI_JUDGE_ACT0058_HOMOLOG'),
    (70,'stage_analisis','MINI_JUDGE_ACT0058_ANALISIS'),
    (90,'stage_kb_write','MINI_JUDGE_ACT0058_KB_WRITE'),
    (100,'completed','MINI_JUDGE_ACT0058_COMPLETED'),
    (105,'restock_queue','MINI_JUDGE_ACT0058_RESTOCK'),
    (110,'failed_retry','MINI_JUDGE_ACT0058_RETRY'),
}
FORBIDDEN = {'LLM','production_authorized: true','automatic_impact: true'}

def fail(msg: str) -> None:
    raise SystemExit(f'FAIL ACT0058_JUDGE_SPEC: {msg}')

def main() -> int:
    text = SPEC.read_text(encoding='utf-8')
    if 'operation_code: ORQUESTACION_PIPELINE_LF' not in text:
        fail('operation code mismatch')
    for term in FORBIDDEN:
        if term in text:
            fail(f'forbidden term: {term}')
    blocks = re.findall(r'  - step_order: (\d+)\n    step_id: ([^\n]+)\n    judge_code: ([^\n]+)', text)
    observed = {(int(a), b.strip(), c.strip()) for a,b,c in blocks}
    if observed != EXPECTED:
        fail(f'expected {sorted(EXPECTED)}, observed {sorted(observed)}')
    if text.count('pass_if:') != 10 or text.count('fail_if:') != 10 or text.count('result_values:') != 10:
        fail('each judge must define pass/fail/result')
    if 'deterministic_first: true' not in text or 'llm_required: false' not in text:
        fail('deterministic-first boundary missing')
    if 'exact_contract_binding_required: true' not in text:
        fail('exact contract binding guard missing')
    print('ACT0058_MISSING_JUDGES_SPEC=PASS judges=10 deterministic=10 llm=0')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
