#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_additional_consumer_context_pack_candidates_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_ADDITIONAL_CONSUMER_CONTEXT_PACK_CANDIDATES_V1','SCHEMA')
req(D['mode']=='READ_ONLY_CANDIDATE_ONLY','MODE')
req(D['selector']=='DETERMINISTIC_EXACT_BINDING_REQUIRED','SELECTOR')
req(D['authority_decision']=='NO_DIRECT_GENERIC_INJECTION' and D['authority_event_ref']=='public.lf_eventos/9872','AUTHORITY')
req(D['pack_count']==len(D['packs'])==4,'COUNT')
for i,p in enumerate(D['packs']):
    req(p['binding_state']=='READY_FOR_BINDING',f'STATE_{i}')
    req('SPECIALIZED_ADAPTER_RUNTIME_ENABLED' in p['prerequisites'],f'RUNTIME_PREREQ_{i}')
    req(p['selected_evidence_refs']==[] and p['source_learning_ids']==[],f'NO_EVIDENCE_{i}')
    req(p['context_bytes']==p['context_budget_bytes']==0,f'ZERO_CONTEXT_{i}')
    req(p['fallback']=='NO_COMPETITIVE_CONTEXT',f'FALLBACK_{i}')
    req(p['delivery_enabled'] is False,f'NO_DELIVERY_{i}')
req(D['selector_llm_calls']==D['selector_round_trips']==D['reader_writes']==0,'ZERO_CALLS_WRITES')
req(D['semantic_search'] is False and D['automatic_binding'] is False,'NO_AUTH_EXPANSION')
req(D['automatic_impact'] is False and D['production_authorized'] is False,'NO_PRODUCTION')
print('LEARNING_ADDITIONAL_CONSUMER_CONTEXT_PACK_CANDIDATES=PASS packs=4 authority=NO_DIRECT_GENERIC_INJECTION context=0 delivery=false')
