#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_additional_consumer_eligibility_run037.json'

def fail(msg: str) -> None:
    raise SystemExit('FAIL LEARNING_ADDITIONAL_CONSUMER_ELIGIBILITY: '+msg)

def main() -> int:
    p=json.loads(PATH.read_text(encoding='utf-8'))
    if p.get('schema')!='LF_LEARNING_ADDITIONAL_CONSUMER_ELIGIBILITY_V1': fail('schema')
    if p.get('automatic_impact') is not False or p.get('production_authorized') is not False: fail('impact boundary')
    direct={x.get('consumer_id'):x for x in p.get('direct_read_only_consumers') or []}
    if set(direct)!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail('direct consumer set')
    for cid,row in direct.items():
        if row.get('profile_registry_present') is not True: fail(cid+' registry')
        if row.get('profile_state')!='READ_ONLY': fail(cid+' state')
        if row.get('profile_runtime_state')!='NO_HABILITADO': fail(cid+' profile runtime boundary')
        if row.get('adapter_state')!='READ_ONLY' or row.get('adapter_runtime_enabled') is not True: fail(cid+' adapter boundary')
        if row.get('input_governance_receipt_required') is not True: fail(cid+' input governance')
    blocked={x.get('requested_identity') or x.get('consumer_id'):x for x in p.get('not_eligible_for_new_direct_binding') or []}
    for cid in ['PERFIL-UX-RESEARCHER-LF','PERFIL-UX-WRITER-LF']:
        if blocked.get(cid,{}).get('decision')!='NO_EXACT_CONSUMER': fail(cid+' must fail closed')
    ux=blocked.get('PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531') or {}
    if ux.get('adapter_runtime_enabled') is not False or ux.get('decision')!='NO_DIRECT_COMPETITIVE_INJECTION': fail('UX architect direct-injection boundary')
    print('LEARNING_ADDITIONAL_CONSUMER_ELIGIBILITY=PASS direct=2 no_exact=2 ux_direct_injection=BLOCKED')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
