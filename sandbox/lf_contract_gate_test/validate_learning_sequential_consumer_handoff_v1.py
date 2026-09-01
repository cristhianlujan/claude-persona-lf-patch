#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_sequential_consumer_handoff_v1.yaml'

def fail(msg): raise SystemExit(f'FAIL learning-sequential-handoff: {msg}')

def main()->int:
    doc=yaml.safe_load(PATH.read_text(encoding='utf-8'))
    if doc.get('status')!='CANDIDATO_READ_ONLY': fail('status')
    chain=doc.get('chain') or []
    if len(chain)!=2: fail('chain length')
    product,ui=chain
    if product.get('stage')!='PRODUCT_DIRECTION' or product.get('consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF': fail('product first')
    required=set(product.get('required_before_next_stage') or [])
    expected={'governed_profile_runtime_receipt','semantic_obligation_manifest_sha256','product_direction_ref','product_direction_current','authority_pass'}
    if not expected<=required: fail('upstream receipt requirements')
    if ui.get('stage')!='UI_SPECIFICATION' or ui.get('consumer_id')!='PERFIL-UI-ARCHITECT': fail('ui second')
    if ui.get('upstream_required_consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF': fail('upstream owner')
    if ui.get('upstream_current_required') is not True or ui.get('exact_binding_required') is not True: fail('fresh exact binding')
    if ui.get('competitive_context_authority_type')!='UPSTREAM_CONSTRAINTS': fail('authority type')
    must_not=set(ui.get('must_not_invoke_when') or [])
    if 'product_direction_missing_or_stale' not in must_not or 'product_scope_decision_required' not in must_not: fail('ui negative routing')
    prohibitions=set(doc.get('prohibitions') or [])
    for required_prohibition in ('direct_learning_to_frontend_without_product_and_ui_authority','direct_learning_to_gamification_without_authorized_product_or_ux_objective','learning_context_as_product_truth','automatic_promotion','profile_source_mutation_for_context_injection'):
        if required_prohibition not in prohibitions: fail(required_prohibition)
    gate=doc.get('behavioral_gate') or {}
    if gate.get('required') is not True or gate.get('status')!='BENCHMARK_REQUIRED_PROFILE_RUNTIME': fail('behavioral gate')
    if gate.get('champion_preserved_until_pass') is not True: fail('champion preservation')
    if any(stage.get('production_impact') is not False for stage in chain): fail('production impact')
    print('LEARNING_SEQUENTIAL_CONSUMER_HANDOFF=PASS product_first=1 ui_second=1 current_upstream=1 exact_binding=1 direct_frontend=blocked direct_gamification=blocked production=0')
    return 0

if __name__=='__main__': raise SystemExit(main())
