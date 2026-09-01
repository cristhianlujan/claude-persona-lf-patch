#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'sandbox/lf_contract_gate_test/act0058_missing_judges_v1.yaml'
RECON = ROOT / 'sandbox/lf_contract_gate_test/act0058_step_contract_reconciliation_v1.yaml'
EVIDENCE = ROOT / 'sandbox/lf_contract_gate_test/evidence/ACT0058_PENDING_SOURCE_INSPECTION_20260901.json'
CASE_VALIDATOR = ROOT / 'sandbox/lf_contract_gate_test/validate_act0058_judge_cases_v1.py'
LIVE_RECON_VALIDATOR = ROOT / 'sandbox/lf_contract_gate_test/validate_act0058_live_contract_reconciliation_v1.py'
READY = {
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
FORBIDDEN = {'production_authorized: true','automatic_impact: true','db_write: true'}

def fail(msg: str) -> None:
    raise SystemExit(f'FAIL ACT0058_JUDGE_SPEC: {msg}')

def run(path: Path) -> str:
    p=subprocess.run([sys.executable,str(path)],cwd=ROOT,capture_output=True,text=True)
    if p.returncode:
        fail(f'{path.name}: {p.stdout} {p.stderr}')
    return p.stdout.strip()

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

def validate_reconciliation() -> None:
    text = RECON.read_text(encoding='utf-8')
    for term in FORBIDDEN:
        if term in text:
            fail(f'reconciliation forbidden term: {term}')
    required = [
        'step_order: 105','step_id: restock_queue','zero_new_urls_is_controlled_noop_not_batch_failure',
        'RESTOCK_NOOP_WARN','step_order: 110','step_id: failed_retry',
        'retry_count_reaches_3_marks_FAILED_definitive_and_continue_next_url',
        'RETRY_TERMINAL_FAILED','SOURCE_FIRST_MIGRATION_OR_CANONICAL_CONTRACT_PATCH',
        'before: ACTIVE_JUDGE_BINDING','db_write: false',
        'blob_sha: 3e465ffb8fe2e6ab45ac95c813fd8da3e4c83495',
    ]
    missing=[x for x in required if x not in text]
    if missing:
        fail(f'reconciliation missing terms: {missing}')
    if text.count('live_conflict:') != 2 or text.count('canonical_source_rule:') != 2 or text.count('proposed_contract:') != 2:
        fail('reconciliation must cover exactly two source conflicts')

def main() -> int:
    text = SPEC.read_text(encoding='utf-8')
    if 'version: v3' not in text:
        fail('expected v3 spec')
    if 'operation_code: ORQUESTACION_PIPELINE_LF' not in text:
        fail('operation code mismatch')
    for term in FORBIDDEN:
        if term in text:
            fail(f'forbidden term: {term}')
    if 'contradictory_contract_fail_closed: true' not in text:
        fail('contradictory contracts must fail closed')
    if 'blob_sha: 3e465ffb8fe2e6ab45ac95c813fd8da3e4c83495' not in text:
        fail('canonical skill blob not pinned')
    ready_section = text.split('source_reconciliation_required:', 1)[0]
    ready_blocks = re.findall(r'  - step_order: (\d+)\n    step_id: ([^\n]+)\n    judge_code: ([^\n]+)', ready_section)
    observed_ready = {(int(a), b.strip(), c.strip()) for a,b,c in ready_blocks}
    if observed_ready != READY:
        fail(f'ready set mismatch: {sorted(observed_ready)}')
    if ready_section.count('pass_if:') != 10 or ready_section.count('fail_if:') != 10 or ready_section.count('result_values:') != 10:
        fail('each ready judge must define pass/fail/result')
    if 'no_op_if:' not in ready_section or 'RESTOCK_NOOP_WARN' not in ready_section:
        fail('restock no-op WARN semantics missing')
    if 'terminal_if:' not in ready_section or 'RETRY_TERMINAL_FAILED' not in ready_section:
        fail('retry terminal-at-3 semantics missing')
    if 'step_orders: [105, 110]' not in text or 'SOURCE_FIRST_NO_DB_WRITE' not in text:
        fail('source reconciliation scope missing')
    if 'ready_to_bind: 10' not in text or 'source_reconciliation_required: 2' not in text or 'missing_bindings: 10' not in text:
        fail('live inventory summary mismatch')
    if 'deterministic_first: true' not in text or 'llm_required: false' not in text:
        fail('deterministic-first boundary missing')
    validate_reconciliation()
    validate_source_evidence()
    print(run(CASE_VALIDATOR))
    print(run(LIVE_RECON_VALIDATOR))
    print('ACT0058_MISSING_JUDGES_SPEC=PASS ready=10 source_reconciliation=2 deterministic=10 llm=0')
    print('ACT0058_CONTRACT_RECONCILIATION=PASS steps=105,110 db_write=0')
    print('ACT0058_LIVE_INVENTORY=PASS active_steps=14 existing_bindings=4 missing=10')
    print('ACT0058_SOURCE_INSPECTION=PASS checked=6 direct=2 index_only=4')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
