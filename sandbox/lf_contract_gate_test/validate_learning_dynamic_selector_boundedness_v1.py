#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context

def kb(kid,summary='s',q=8):
    return {'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':q,'topic':'t','summary':summary,'source_url':'https://example.invalid/'+kid}
def ev(kid,eid):
    return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':'NEGOCIACION_DEUDA','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
def run(rows,events):
    out=select_context(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    assert out['context_bytes']<=out['context_budget_bytes']==6000
    assert len(out['selected'])<=5
    assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False
    return out
rows=[kb(str(i),q=10-i) for i in range(10)]
events=[ev(str(i),i+1) for i in range(10)]
out=run(rows,events)
assert len(out['selected'])==5
assert [x['kb_id'] for x in out['selected']]==['0','1','2','3','4']
# Oversized high-priority item must not consume budget or block later fitting evidence.
rows=[kb('big','x'*7000,q=100),kb('small','ok',q=10)]
events=[ev('big',10),ev('small',9)]
out=run(rows,events)
assert [x['kb_id'] for x in out['selected']]==['small']
# UTF-8 byte budget, not character count.
rows=[kb('unicode','á'*4000,q=10)]
events=[ev('unicode',10)]
out=run(rows,events)
assert out['selected']==[] and out['fallback']=='NO_COMPETITIVE_CONTEXT'
# Empty input remains bounded fallback.
out=run([],[])
assert out['selected']==[] and out['fallback']=='NO_COMPETITIVE_CONTEXT'
print('LEARNING_DYNAMIC_SELECTOR_BOUNDEDNESS=PASS max_refs=5 byte_budget=6000 oversized_skip=PASS utf8_bytes=PASS fallback=PASS')
