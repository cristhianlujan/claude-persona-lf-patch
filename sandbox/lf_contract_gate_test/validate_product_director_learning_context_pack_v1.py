#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
P=json.loads((R/'product_director_learning_context_pack_v1.json').read_text(encoding='utf-8'))
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text(encoding='utf-8'))
C=json.loads((R/'product_director_learning_classification_readback_v1.json').read_text(encoding='utf-8'))
def main():
 assert P['schema']=='LF_PRODUCT_DIRECTOR_LEARNING_CONTEXT_PACK_V1' and P['mode']=='READ_ONLY'
 s=P['selection']; assert s['strategy']=='DETERMINISTIC_EXACT_IDS' and s['semantic_search'] is False and s['llm_calls']==0 and s['round_trips']==0 and s['reader_writes']==0 and s['recursive_expansion'] is False
 assert s['max_evidence_refs_per_capability']==5 and s['max_active_capabilities_per_request']==1 and s['max_context_bytes_per_request']==6000
 assert set(P['required_sections'])=={'facts','evidence_refs','constraints','policy_refs','observed_vs_proposed_boundary'}
 db={x['capability_id']:x for x in D['bindings'] if x['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'}
 assert set(P['capabilities'])==set(db) and len(db)==5
 ids=[]
 for cap,spec in P['capabilities'].items():
  assert len(spec['source_learning_ids'])<=5
  assert db[cap]['context_budget_bytes']==6000
  ids.extend(spec['source_learning_ids'])
 assert len(ids)==len(set(ids))==P['selected_learning_ids_total']==13
 receipts={x['kb_id'] for x in C['receipts']}; assert set(ids)==receipts and C['selected_receipts']==13
 assert P['fallback']=='NO_COMPETITIVE_CONTEXT' and P['automatic_impact'] is False and P['production_authorized'] is False
 print('PRODUCT_DIRECTOR_CONTEXT_PACK=PASS capabilities=5/5 learning_ids=13/13 max_active=1 max_bytes=6000 refs_per_capability<=5 llm=0 rt=0 writes=0 semantic_search=false')
if __name__=='__main__': main()
