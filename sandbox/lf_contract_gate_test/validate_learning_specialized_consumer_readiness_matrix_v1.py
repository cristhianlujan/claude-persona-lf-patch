#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_specialized_consumer_readiness_matrix_v1.json').read_text())
B=json.loads((R/'learning_additional_consumer_binding_candidates_v1.json').read_text())
C=json.loads((R/'learning_additional_consumer_context_pack_candidates_v1.json').read_text())
A=json.loads((R/'learning_additional_consumer_applicability_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_READINESS_MATRIX_V1','SCHEMA')
req(D['mode']=='READ_ONLY' and D['source_scope']=='GITHUB_CANDIDATE_TREE_PLUS_LIVE_ROUTER_READBACK','MODE')
req(D.get('fresh_router_readback_event_ref')==A.get('fresh_readback_event_ref') and bool(D.get('fresh_router_readback_event_ref')),'FRESH_ROUTER_READBACK')
rows={(x['consumer_id'],x['capability_id']):x for x in D['rows']}
bind={(x['consumer_id'],x['capability_id']):x for x in B['bindings']}
pack={(x['consumer_id'],x['capability_id']):x for x in C['packs']}
apps={x['consumer_id']:x for x in A['consumers']}
req(set(rows)==set(bind)==set(pack),'PAIR_PARITY')
for k,r in rows.items():
    b=bind[k]; p=pack[k]; a=apps[k[0]]
    req(r['exact_binding_created']==b['provenance']['exact_binding_created']==False,'NO_BINDING_'+k[0])
    req(r['evidence_refs_materialized']==bool(b['selected_evidence_refs'])==False,'NO_EVIDENCE_'+k[0])
    req(r['source_learning_ids_materialized']==bool(b['source_learning_ids'])==False,'NO_LEARNING_IDS_'+k[0])
    req(r['runtime_enabled']==a['runtime_enabled']==False,'RUNTIME_'+k[0])
    req(r['context_budget_bytes']==p['context_budget_bytes']==0,'ZERO_BUDGET_'+k[0])
    req(r['delivery_enabled']==p['delivery_enabled']==False,'NO_DELIVERY_'+k[0])
    req(r['readiness']=='READY_FOR_BINDING' and r['outcome']=='NO_COMPETITIVE_CONTEXT','OUTCOME_'+k[0])
req(D['row_count']==4 and D['ready_for_binding_count']==4 and D['active_binding_count']==0 and D['delivery_enabled_count']==0,'COUNTS')
req(D['automatic_promotion'] is False and D['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_SPECIALIZED_CONSUMER_READINESS_MATRIX=PASS rows=4/4 ready_for_binding=4 active=0 delivery=0 fresh_router_readback=PASS')
