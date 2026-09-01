#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'sandbox/lf_contract_gate_test/act0058_missing_judges_v1.yaml'
EVIDENCE = ROOT / 'sandbox/lf_contract_gate_test/evidence/ACT0058_PENDING_SOURCE_INSPECTION_20260901.json'
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
FORBIDDEN = {'production_authorized: true','automatic_impact: true'}

def fail(msg: str) -> None:
    raise SystemExit(f'FAIL ACT0058_JUDGE_SPEC: {msg}')

def validate_source_evidence() -> None:
    data = json.loads(EVIDENCE.read_text(encoding='utf-8'))
    if data.get('kb_write_performed') is not False:
        fail('source inspection must remain no-write')
    sources = data.get('sources') or []
    if len(sources) != 6:
        fail(f'expected 6 inspected sources, got {len(sources)}')
    direct = [s for s in sources if s.get('source_read') == 'DIRECT_PAGE_OK']
    index_only = [s for s in sources if 'INDEX_CONFIRMED' in str(s.get('source_read'))]
    if len(direct) != 2 or len(index_only) != 4:
        fail(f'source boundary mismatch direct={len(direct)} index_only={len(index_only)}')
    if any(s.get('eligible_for_capture') is not True for s in direct):
        fail('direct sources must be eligible for governed capture')
    if any(s.get('eligible_for_capture') is not False for s in index_only):
        fail('index-only sources must remain ineligible before reopen')
    summary = data.get('summary') or {}
    expected = {
        'queue_sources_checked': 6,
        'direct_page_ok': 2,
        'index_only_confirmed': 4,
        'eligible_for_governed_capture_now': 2,
        'requires_reopen_before_capture': 4,
        'existing_kb_rows_for_exact_urls': 0,
    }
    if any(summary.get(k) != v for k,v in expected.items()):
        fail(f'source summary mismatch: {summary}')

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
    validate_source_evidence()
    print('ACT0058_MISSING_JUDGES_SPEC=PASS judges=10 deterministic=10 llm=0')
    print('ACT0058_SOURCE_INSPECTION=PASS checked=6 direct=2 index_only=4 kb_existing=0')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
