#!/usr/bin/env python3
import itertools
from learning_dynamic_context_selector_clean_v1 import select_context

def kb(kid,q):
    return {'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':q,'topic':'t'+kid,'summary':'s'+kid,'source_url':'https://example.invalid/'+kid}
def ev(kid,eid):
    return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':'NEGOCIACION_DEUDA','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
rows=[kb('a',9),kb('b',9),kb('c',8),kb('d',8),kb('e',7)]
events=[ev('a',10),ev('b',11),ev('c',20),ev('d',20),ev('e',30)]
def ids(r,e):
    out=select_context(list(r),list(e),'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False
    return [x['kb_id'] for x in out['selected']]
baseline=ids(rows,events)
assert baseline==['b','a','c','d','e'],baseline
count=0
row_perms=list(itertools.islice(itertools.permutations(rows),10))
event_perms=list(itertools.islice(itertools.permutations(events),6))
for rp in row_perms:
    for ep in event_perms:
        assert ids(rp,ep)==baseline
        count+=1
assert count==60
print('LEARNING_DYNAMIC_SELECTOR_STABILITY=PASS permutations=60/60 stable_order=b,a,c,d,e deterministic_share=1.0')
