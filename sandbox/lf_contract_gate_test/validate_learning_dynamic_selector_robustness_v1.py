#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context,SelectionError

def kb(kid='k',**kw):
    x={'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':8,'topic':'t','summary':'s','source_url':'https://example.invalid'}; x.update(kw); return x
def ev(kid='k',**kw):
    p={'kb_id':kid,'cluster_code':'NEGOCIACION_DEUDA','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}; p.update(kw); return {'event_id':1,'payload':p}
def assert_zero(out):
    assert out['selected']==[] and out['fallback']=='NO_COMPETITIVE_CONTEXT'
    assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False
blocked_cases=[
 ([kb('a')],[None]),
 ([kb('a')],['bad']),
 ([kb('a')],[{'event_id':1,'payload':None}]),
 ([kb('a')],[{'event_id':'bad','payload':ev('a')['payload']}]),
 ([kb('a')],[{'payload':ev('a')['payload']}]),
 ([kb('a')],[ev('',cluster_code='NEGOCIACION_DEUDA')]),
 ([kb('a')],[ev('a',cluster_code='')]),
 ([kb('a')],[ev('a',cluster_code='|')]),
 ([None],[ev('a')]),
 (['bad'],[ev('a')]),
 ([{}],[ev('a')]),
 ([kb('',quality_score=8)],[ev('')]),
]
count=0
for rows,events in blocked_cases:
    out=select_context(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'); assert_zero(out); count+=1
for bad in (None,{},'x',1):
    try: select_context(bad,[],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    except SelectionError as e: assert str(e)=='INPUT_COLLECTIONS_REQUIRED'
    else: raise AssertionError('kb collection must fail closed')
    count+=1
for bad in (None,{},'x',1):
    try: select_context([],bad,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    except SelectionError as e: assert str(e)=='INPUT_COLLECTIONS_REQUIRED'
    else: raise AssertionError('event collection must fail closed')
    count+=1
for bad in (None,{},'x',1):
    try: select_context([],[],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',bad)
    except SelectionError as e: assert str(e)=='PREREQUISITES_COLLECTION_REQUIRED'
    else: raise AssertionError('prerequisites must fail closed')
    count+=1
out=select_context([kb('q',quality_score='not-a-number')],[ev('q')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
assert [x['kb_id'] for x in out['selected']]==['q']; assert out['llm_calls']==0 and out['writes']==0; count+=1
print(f'LEARNING_DYNAMIC_SELECTOR_ROBUSTNESS=PASS cases={count}/25 malformed_inputs_fail_closed=true invalid_quality_safe=true')
