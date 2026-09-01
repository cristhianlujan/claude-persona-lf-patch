#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context, SelectionError

def ev(kid, cluster, eid=1, lifecycle='ANALIZADO', eligibility='PASS'):
    return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':cluster,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':lifecycle,'eligibility':eligibility}}

def kb(kid, **kw):
    x={'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':8,'topic':'t','summary':'s','source_url':'https://example.invalid'}; x.update(kw); return x

def assert_reader_invariants(result):
    assert result['llm_calls']==0
    assert result['round_trips']==0
    assert result['writes']==0
    assert result['semantic_search'] is False

def main():
    r=select_context([kb('a'),kb('b',grounding_status='UNGROUNDED'),kb('c',consumer_ready=False)],[ev('a','NEGOCIACION_DEUDA'),ev('b','NEGOCIACION_DEUDA'),ev('c','NEGOCIACION_DEUDA')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    assert [x['kb_id'] for x in r['selected']]==['a']; assert_reader_invariants(r); assert r['context_bytes']<=r['context_budget_bytes']
    f=select_context([],[],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'); assert f['fallback']=='NO_COMPETITIVE_CONTEXT'; assert_reader_invariants(f)
    u=select_context([kb('a')],[ev('a','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE'); assert u['selected']==[] and u['blocked_by_prerequisite']=='PRODUCT_DIRECTION_AUTHORIZED_CURRENT'; assert_reader_invariants(u)
    u2=select_context([kb('a')],[ev('a','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',['PRODUCT_DIRECTION_AUTHORIZED_CURRENT']); assert len(u2['selected'])==1; assert_reader_invariants(u2)
    try: select_context([],[],'UNKNOWN','UNKNOWN')
    except SelectionError as e: assert str(e)=='EXACT_BINDING_REQUIRED'
    else: raise AssertionError('must fail closed')
    print('PASS learning_dynamic_context_selector_clean_v1 writes=0 semantic_search=false llm_calls=0 round_trips=0')
if __name__=='__main__': main()
