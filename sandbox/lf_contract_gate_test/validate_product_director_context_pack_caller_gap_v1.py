#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/product_director_context_pack_caller_gap_v1.yaml'

def fail(msg): raise SystemExit(f'FAIL context-pack-caller-gap: {msg}')

def main()->int:
    doc=yaml.safe_load(PATH.read_text(encoding='utf-8'))
    if doc.get('status')!='BLOCKED_EXTERNAL_AUTHORITY_CHANNEL': fail('status')
    if doc.get('consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF' or doc.get('governance_consumer')!='CONTEXT_PACK': fail('consumer')
    screen=doc.get('screen') or {}
    if screen.get('pantalla_id')!=21 or screen.get('screen_code')!='CHECKOUT_CUOTAS_MEDIO_PAGO': fail('screen')
    observed=doc.get('observed_secure_caller') or {}
    if observed.get('auth')!='GITHUB_ACTIONS_OIDC' or observed.get('current_consumer')!='STORY_CREATOR': fail('observed caller')
    if observed.get('supports_required_context_pack_scope') is not False: fail('current scope must remain blocked')
    ext=doc.get('required_authorized_extension_contract') or {}
    if ext.get('action')!='input_readiness_context_pack_v1' or ext.get('consumer')!='CONTEXT_PACK' or ext.get('pantalla_id')!=21: fail('extension exact scope')
    if ext.get('oidc_required') is not True or ext.get('service_role_stays_inside_edge_runtime') is not True: fail('authority transport')
    forbidden=set(ext.get('forbidden') or [])
    expected={'reuse_STORY_CREATOR_receipt','profile_asset_code_as_consumer','fabricated_service_role','direct_database_receipt_insert','broaden_allowed_screens_without_exact_contract'}
    if not expected<=forbidden: fail('forbidden bypasses')
    if doc.get('behavioral_next_gate',{}).get('current_status')!='BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED': fail('blocking code')
    if doc.get('production_impact') is not False: fail('production')
    print('PRODUCT_DIRECTOR_CONTEXT_PACK_CALLER_GAP=PASS exact_screen=21 exact_consumer=CONTEXT_PACK oidc=required story_creator_receipt=rejected production=0')
    return 0
if __name__=='__main__': raise SystemExit(main())
