#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_additional_consumer_binding_candidates_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
required={'consumer_id','consumer_type','capability_id','card_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','token/context_budget','lifecycle_state','version','source_learning_ids','champion_id','challenger_id','provenance'}
req(D['schema']=='LF_LEARNING_ADDITIONAL_CONSUMER_BINDING_CANDIDATES_V1','SCHEMA')
req(D['mode']=='READ_ONLY_CANDIDATE_ONLY','MODE')
req(D['authority_decision']=='NO_DIRECT_GENERIC_INJECTION','AUTH_DECISION')
req(D['authority_event_ref']=='public.lf_eventos/9872','AUTH_EVENT')
req(D['ekb_ref']=='LEARNING-DIRECT-CONSUMER-AUTHORITY-001','EKB')
req(D['candidate_count']==len(D['bindings'])==4,'COUNT')
for i,b in enumerate(D['bindings']):
    req(required <= set(b),f'FIELDS_{i}')
    req(b['consumer_type']=='PROFILE' and b['router_action']=='EJECUCION_PERFIL_LF',f'ROUTER_{i}')
    req(b['lifecycle_state']=='READY_FOR_BINDING',f'LIFECYCLE_{i}')
    req(b['fallback']=='NO_COMPETITIVE_CONTEXT',f'FALLBACK_{i}')
    req(b['selected_evidence_refs']==[] and b['source_learning_ids']==[],f'NO_EVIDENCE_INJECTION_{i}')
    req(b['token/context_budget']['learning_context_max_bytes']==0,f'ZERO_LEARNING_CONTEXT_{i}')
    req(b['provenance']['exact_binding_created'] is False,f'NO_EXACT_BINDING_{i}')
    req(b['champion_id'] is None and b['challenger_id'] is None,f'NO_BENCHMARK_ID_{i}')
req(D['active_exact_binding_count']==0,'ACTIVE_BINDINGS')
req(D['selector_context_delivery_enabled'] is False and D['automatic_binding'] is False,'NO_DELIVERY')
req(D['production_authorized'] is False,'NO_PRODUCTION')
print('LEARNING_ADDITIONAL_CONSUMER_BINDING_CANDIDATES=PASS candidates=4 authority=NO_DIRECT_GENERIC_INJECTION active_exact_bindings=0 context_delivery=false')
