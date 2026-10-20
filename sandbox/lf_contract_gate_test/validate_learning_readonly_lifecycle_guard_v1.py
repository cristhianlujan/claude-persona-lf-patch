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
tech=set(D['requirements_for_technical_verification'])
req(tech=={'CURRENT_HEAD_EXACT_CI_3_OF_3','FRESH_SOURCE_READBACK_FOR_BOUND_EVIDENCE','ACTIVE_BINDING_CONTRACT_COMPLETE','DYNAMIC_EXACT_JOIN_PASS','SELECTOR_ROBUSTNESS_STABILITY_BOUNDEDNESS_PASS','SPECIALIZED_CONSUMERS_FAIL_CLOSED'},'TECHNICAL_REQUIREMENTS')
req(len(D['requirements_for_behavioral_transition'])==5,'BEHAVIORAL_REQUIREMENTS')
for c in D['additional_consumers']:
    req(c['state']=='READY_FOR_BINDING_REVIEW','ADDITIONAL_STATE')
    req(c['exact_binding_created'] is False,'NO_EXACT_BINDING')
    req(c['automatic_binding'] is False,'NO_AUTO_BINDING')
for k in ('automatic_promotion','automatic_impact','production_authorized','merge_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
print('LEARNING_READONLY_LIFECYCLE_GUARD=PASS technical_requirements=6 fresh_source_required=true behavioral=INSUFFICIENT_EVIDENCE additional_consumers=2/2 forbidden_terminal_states=6 production_authorized=false')
