#!/usr/bin/env python3
import json
from collections import Counter
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_specialized_consumer_failclosed_benchmark_50_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_FAILCLOSED_BENCHMARK_50_V1','SCHEMA')
req(D['mode']=='READ_ONLY_DETERMINISTIC','MODE')
req(D['case_count']==50 and D['family_count']==10,'COUNTS')
req(D['generation']['cases_per_family']==5,'FAMILY_SIZE')
req(len(D['families'])==10 and len(D['consumer_capability_pairs'])==4,'DIMENSIONS')
base={
 'exact_binding_current':True,'selected_evidence_current':True,'source_learning_current':True,
 'context_budget_positive':True,'specialized_adapter_runtime_enabled':True,
 'product_direction_authorized_current':True,'canonical_receipt_current':True,
 'authority_conflict_free':True,'router_resolved':True,'production_authorized':False}
def deliver(s):
    return all([s['exact_binding_current'],s['selected_evidence_current'],s['source_learning_current'],s['context_budget_positive'],s['specialized_adapter_runtime_enabled'],s['product_direction_authorized_current'],s['canonical_receipt_current'],s['authority_conflict_free'],s['router_resolved'],not s['production_authorized']])
results=[]
for fam,mutation in D['families'].items():
    key,val=mutation.split('='); val=True if val=='true' else False
    for i,pi in enumerate(D['generation']['pair_rotation']):
        s=dict(base); s[key]=val
        actual=deliver(s)
        results.append((fam,pi,actual))
req(len(results)==50,'GENERATED_50')
req(Counter(x[0] for x in results)==Counter({k:5 for k in D['families']}),'TEN_BY_FIVE')
req(all(x[2] is False for x in results),'UNSAFE_DELIVERY')
req(D['generation']['expected_outcome']=='NO_COMPETITIVE_CONTEXT' and D['generation']['expected_delivery_enabled'] is False,'EXPECTED')
req(D['generation']['selector_llm_calls']==0 and D['generation']['reader_writes']==0,'ZERO_COST')
req(D['automatic_promotion'] is False and D['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_SPECIALIZED_CONSUMER_FAILCLOSED_BENCHMARK=PASS cases=50/50 families=10x5 unsafe_delivery=0 selector_llm=0 reader_writes=0')
