#!/usr/bin/env python3
from collections import Counter
from learning_deterministic_context_pack_builder_v1 import build_context_pack

def kb(kid='k',cluster='NEGOCIACION_DEUDA',**kw):
    x={'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':8,'topic':cluster,'summary':'s','source_url':'https://example.invalid/'+kid}; x.update(kw); return x
def ev(kid='k',cluster='NEGOCIACION_DEUDA',eid=1,**kw):
    p={'kb_id':kid,'cluster_code':cluster,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}; p.update(kw); return {'event_id':eid,'payload':p}
def safe(p):
    assert p['llm_calls']==0 and p['round_trips']==0 and p['writes']==0 and p['semantic_search'] is False and p['recursive_expansion'] is False
    assert p['context_bytes']<=p['context_budget_bytes'] if p['context_budget_bytes'] else p['context_bytes']==0
    return p
families={}
# Each family returns expected boolean: context delivered or fail-closed.
families['PD_POSITIVE']=lambda i:safe(build_context_pack([kb(str(i))],[ev(str(i),eid=i+1)],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',explicit_constraints=['C']))['fallback'] is None
families['MISSING_RECEIPT']=lambda i:safe(build_context_pack([kb(str(i))],[],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'))['fallback'] is not None
families['UNGROUNDED']=lambda i:safe(build_context_pack([kb(str(i),grounding_status='UNGROUNDED')],[ev(str(i),eid=i+1)],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'))['fallback'] is not None
families['NOT_CONSUMER_READY']=lambda i:safe(build_context_pack([kb(str(i),consumer_ready=False)],[ev(str(i),eid=i+1)],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'))['fallback'] is not None
families['WRONG_CLUSTER']=lambda i:safe(build_context_pack([kb(str(i),'CAMPANAS_Y_OFERTAS')],[ev(str(i),'CAMPANAS_Y_OFERTAS',i+1)],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'))['fallback'] is not None
families['UI_MISSING_PREREQUISITE']=lambda i:safe(build_context_pack([kb(str(i),'AUTOGESTION_DIGITAL')],[ev(str(i),'AUTOGESTION_DIGITAL',i+1)],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',product_direction_ref='product://d'))['fallback'] is not None
families['UI_MISSING_PRODUCT_DIRECTION_REF']=lambda i:safe(build_context_pack([kb(str(i),'AUTOGESTION_DIGITAL')],[ev(str(i),'AUTOGESTION_DIGITAL',i+1)],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',prerequisites=['PRODUCT_DIRECTION_AUTHORIZED_CURRENT']))['fallback'] is not None
families['UI_POSITIVE']=lambda i:safe(build_context_pack([kb(str(i),'AUTOGESTION_DIGITAL')],[ev(str(i),'AUTOGESTION_DIGITAL',i+1)],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',prerequisites=['PRODUCT_DIRECTION_AUTHORIZED_CURRENT'],product_direction_ref='product://d',explicit_constraints=['C']))['fallback'] is None
families['UNKNOWN_BINDING']=lambda i:safe(build_context_pack([kb(str(i))],[ev(str(i),eid=i+1)],'UNKNOWN','UNKNOWN'))['fallback'] is not None
def oversized(i):
    rows=[kb(f'{i}-{j}',summary='x'*2500,quality_score=10-j) for j in range(5)]; events=[ev(f'{i}-{j}',eid=100+j) for j in range(5)]
    p=safe(build_context_pack(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',explicit_constraints=['C']))
    return p['fallback'] is None and 0<len(p['selected_learning_ids'])<5 and p['context_bytes']<=6000
families['OVERSIZED_DETERMINISTIC_TRIM']=oversized
results=[]
for fam,fn in families.items():
    for i in range(5): results.append((fam,bool(fn(i))))
assert len(results)==50
assert Counter(f for f,_ in results)==Counter({f:5 for f in families})
assert all(ok for _,ok in results)
print('LEARNING_CONTEXT_PACK_BUILDER_BENCHMARK=PASS cases=50/50 families=10x5 positive=10 failclosed=35 bounded_trim=5 llm=0 rt=0 writes=0')
