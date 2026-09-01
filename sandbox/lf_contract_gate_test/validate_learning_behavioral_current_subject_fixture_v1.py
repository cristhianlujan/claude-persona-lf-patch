#!/usr/bin/env python3
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'sandbox/lf_contract_gate_test/learning_behavioral_current_subject_fixture_v1.json'
d=json.loads(p.read_text())
assert d['schema']=='LF_LEARNING_BEHAVIORAL_CURRENT_SUBJECT_FIXTURE_V1'
assert d['mode']=='READ_ONLY_SANDBOX'
assert d['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
assert d['capability_id']=='NEGOCIACION_DEUDA'
g=d['input_governance']
assert g['current_run_id']==215 and g['pantalla_id']==5 and g['screen_code']=='HOME_002'
assert g['contract_revision']=='5.12' and g['status']=='COMPLETED' and g['invalidated_at'] is None
assert g['governance_consumer']=='CONTEXT_PACK'
assert d['binding_id']=='BIND-LF-PD-NEGOCIACION-DEUDA-v4'
assert 1 <= len(d['selected_evidence_refs']) <= 5
assert len(d['selected_evidence_refs'])==len(set(d['selected_evidence_refs']))
assert all(x.startswith('public.lf_knowledge_base/') for x in d['selected_evidence_refs'])
assert d['runtime_invoked'] is False and d['holdout_consumed'] is False and d['enqueue_performed'] is False
assert d['production_authorized'] is False and d['automatic_impact'] is False
assert d['next_gate']=='GOVERNED_PROFILE_RUNTIME_QUEUE_REQUEST'
print('LEARNING_BEHAVIORAL_CURRENT_SUBJECT_FIXTURE=PASS consumer=PERFIL-PRODUCT-DIRECTOR-LF pantalla=HOME_002 run=215 evidence=5 runtime_invoked=0 holdout_consumed=0')
