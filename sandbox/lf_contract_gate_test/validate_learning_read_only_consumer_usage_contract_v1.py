#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_consumer_usage_contract_v1.yaml'

def fail(msg): raise SystemExit(f'FAIL learning-read-only-usage-contract: {msg}')

def main() -> int:
    doc=yaml.safe_load(PATH.read_text(encoding='utf-8'))
    if doc.get('status')!='CANDIDATO_READ_ONLY': fail('status')
    router=doc.get('router_first') or {}
    if router.get('required') is not True or router.get('router_asset')!='ACT-0001': fail('router')
    if router.get('no_direct_consumer_bypass') is not True: fail('bypass')
    consumer=doc.get('consumer') or {}
    if consumer.get('consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF' or consumer.get('consumer_type')!='PROFILE': fail('consumer')
    pack=doc.get('context_pack') or {}
    if pack.get('schema')!='LF_LEARNING_CONSUMER_CONTEXT_PACK_V2': fail('pack schema')
    if pack.get('selector')!='DETERMINISTIC_EXACT_ID': fail('selector')
    if pack.get('max_evidence_refs')!=5 or pack.get('max_context_bytes')!=6000: fail('budget')
    if pack.get('llm_selector_allowed') is not False or pack.get('semantic_scope_expansion_allowed') is not False: fail('selector authority')
    reader=doc.get('runtime_reader') or {}
    if reader.get('writes_allowed') is not False: fail('writes')
    if any(reader.get(k)!=0 for k in ('llm_calls','round_trips','tool_calls_inside_selector')): fail('extra calls')
    eligibility=doc.get('eligibility') or {}
    if eligibility.get('grounding_status')!='GROUNDED' or eligibility.get('consumer_ready') is not True or eligibility.get('source_learning_id_must_be_bound') is not True: fail('eligibility')
    if doc.get('fallback')!='NO_COMPETITIVE_CONTEXT': fail('fallback')
    boundary=doc.get('promotion_boundary') or {}
    if boundary.get('production_impact') is not False or boundary.get('automatic_promotion') is not False: fail('promotion boundary')
    if boundary.get('runtime_behavioral_required_before_profile_promotion') is not True: fail('behavioral gate')
    print('LEARNING_READ_ONLY_CONSUMER_USAGE_CONTRACT=PASS router_first=1 exact_binding=1 writes=0 llm_selector=0 production=0')
    return 0

if __name__=='__main__': raise SystemExit(main())
