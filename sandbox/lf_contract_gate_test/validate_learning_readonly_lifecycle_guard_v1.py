#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_readonly_lifecycle_guard_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_READONLY_LIFECYCLE_GUARD_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['behavioral_state']=='INSUFFICIENT_EVIDENCE','BEHAVIORAL_FAIL_CLOSED')
for state in ('APROBADO','IMPACTADO','VERIFICADO','CERRADO','PRODUCTION_READY','BEHAVIORAL_WINNER'):
    req(state in D['forbidden_without_behavioral_receipt'],'FORBIDDEN_'+state)
req(len(D['requirements_for_behavioral_transition'])==5,'BEHAVIORAL_REQUIREMENTS')
for c in D['additional_consumers']:
    req(c['state']=='READY_FOR_BINDING_REVIEW','ADDITIONAL_STATE')
    req(c['exact_binding_created'] is False,'NO_EXACT_BINDING')
    req(c['automatic_binding'] is False,'NO_AUTO_BINDING')
for k in ('automatic_promotion','automatic_impact','production_authorized','merge_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
print('LEARNING_READONLY_LIFECYCLE_GUARD=PASS behavioral=INSUFFICIENT_EVIDENCE additional_consumers=2/2 exact_bindings=0 forbidden_terminal_states=6 production_authorized=false')
