#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / 'sandbox/lf_contract_gate_test/learning_consumer_context_pack_v2.json'
BINDINGS = ROOT / 'sandbox/lf_contract_gate_test/learning_consumer_bindings_v1.yaml'


def fail(msg: str) -> None:
    raise SystemExit(f'FAIL learning-context-pack-v2: {msg}')


def main() -> int:
    pack = json.loads(PACK.read_text(encoding='utf-8'))
    bindings_doc = yaml.safe_load(BINDINGS.read_text(encoding='utf-8'))
    if pack.get('schema') != 'LF_LEARNING_CONSUMER_CONTEXT_PACK_V2': fail('schema')
    if pack.get('status') != 'CANDIDATO_READ_ONLY': fail('status')
    if pack.get('consumer_id') != 'PERFIL-PRODUCT-DIRECTOR-LF': fail('consumer')
    selection = pack.get('selection') or {}
    if selection.get('mode') != 'DETERMINISTIC_EXACT_ID': fail('selector')
    if selection.get('llm_selector_allowed') is not False: fail('llm selector must be false')
    if selection.get('semantic_scope_expansion_allowed') is not False: fail('semantic expansion must be false')
    if selection.get('max_evidence_refs_per_binding') != 5: fail('max evidence')
    if selection.get('context_budget_bytes') != 6000: fail('context budget')
    if selection.get('fallback') != 'NO_COMPETITIVE_CONTEXT': fail('fallback')
    if pack.get('authority', {}).get('production_impact') is not False: fail('production impact')
    if pack.get('authority', {}).get('automatic_promotion') is not False: fail('automatic promotion')

    canonical = {b['binding_id']: b for b in bindings_doc.get('bindings', [])}
    declared = pack.get('bindings') or []
    if len(declared) != 3: fail(f'expected 3 bindings, got {len(declared)}')
    seen = set()
    for item in declared:
        bid = item.get('binding_id')
        if bid in seen: fail(f'duplicate {bid}')
        seen.add(bid)
        source = canonical.get(bid)
        if source is None: fail(f'unknown binding {bid}')
        if item.get('capability_id') != source.get('capability_id'): fail(f'capability mismatch {bid}')
        pack_ids = item.get('source_learning_ids') or []
        canonical_ids = source.get('source_learning_ids') or []
        if not pack_ids or len(pack_ids) > 5: fail(f'bounded ids {bid}')
        if pack_ids != canonical_ids[:5]: fail(f'source ids not exact ordered subset {bid}')
        if item.get('must_not_invoke_when') != source.get('must_not_invoke_when'): fail(f'must_not mismatch {bid}')
    if set(canonical) != seen: fail('binding set mismatch')
    if pack.get('lifecycle_state') != 'READY_FOR_BINDING': fail('lifecycle')
    if pack.get('rollback') != 'NO_COMPETITIVE_CONTEXT': fail('rollback')
    print('LEARNING_CONSUMER_CONTEXT_PACK_V2=PASS bindings=3 max_refs=5 llm_selector=0 production_impact=0')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
