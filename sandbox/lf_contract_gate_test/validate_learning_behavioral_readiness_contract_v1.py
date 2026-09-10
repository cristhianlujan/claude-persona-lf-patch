#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'learning_behavioral_readiness_v1.json'
def main():
 d=json.loads(P.read_text(encoding='utf-8'))
 assert d['schema']=='LF_LEARNING_BEHAVIORAL_READINESS_V1' and d['mode']=='READ_ONLY' and d['input_governance_contract_revision']=='5.12'
 c=d['input_governance_router_contract']
 assert c['governance_consumer']=='CONTEXT_PACK' and c['profile_identity_in_readiness_scope_required'] is False
 assert set(c['receipt_binding'])=={'pantalla_id','screen_code','run_id','source_snapshot_sha256','contract_revision','contract_snapshot_sha256','currentness'}
 r=d['observed_input_readiness']
 assert r['latest_run_id']==218 and r['latest_run_status']=='COMPLETED' and r['latest_run_family_count']==47
 assert r['latest_run_invalidated'] is False and r['latest_run_current'] is True and r['latest_run_scope_production_authorized'] is False
 for row in d['consumer_targets']:
  assert row['required_governance_consumer']=='CONTEXT_PACK'
  assert row['behavioral_target_screen_declared'] is False
  assert row['reusable_exact_screen_receipt_observed'] is False
  assert row['exact_target_bound_readiness_receipt_observed'] is False
  assert row['behavioral_ab_status']=='INSUFFICIENT_EVIDENCE'
 assert d['automatic_promotion'] is False and d['production_authorized'] is False
 print('LEARNING_BEHAVIORAL_READINESS_CONTRACT=PASS governance_consumer=CONTEXT_PACK latest_run=218_current receipt_binding=screen_bound profile_scope_required=false target_screen_declared=0/2 behavioral=INSUFFICIENT_EVIDENCE')
