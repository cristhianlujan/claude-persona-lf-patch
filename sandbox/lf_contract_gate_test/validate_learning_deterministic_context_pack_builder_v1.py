#!/usr/bin/env python3
from learning_deterministic_context_pack_builder_v1 import build_context_pack

def kb(kid,cluster='NEGOCIACION_DEUDA',summary='s',q=8):
    return {'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':q,'topic':cluster,'summary':summary,'source_url':'https://example.invalid/'+kid}
def ev(kid,cluster='NEGOCIACION_DEUDA',eid=1):
    return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':cluster,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
def inv(p):
    assert p['mode']=='READ_ONLY' and p['llm_calls']==0 and p['round_trips']==0 and p['writes']==0 and p['semantic_search'] is False and p['recursive_expansion'] is False
# PD positive full structured pack.
p=build_context_pack([kb('a')],[ev('a')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',task_intent='scope',explicit_constraints=['NO_GUARANTEE'])
inv(p); assert p['fallback'] is None; assert p['facts'][0]['kb_id']=='a'; assert p['evidence_refs']==['public.lf_knowledge_base/a']; assert p['selected_learning_ids']==['a']; assert 'NO_GUARANTEE' in p['constraints']; assert p['policy_refs']==['POL-LF-OPERATION-LIFECYCLE']; assert p['context_bytes']<=p['context_budget_bytes']==6000
# UI must fail without product direction even when evidence+prerequisite exist.
u=build_context_pack([kb('u','AUTOGESTION_DIGITAL')],[ev('u','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',prerequisites=['PRODUCT_DIRECTION_AUTHORIZED_CURRENT'])
inv(u); assert u['fallback']=='NO_COMPETITIVE_CONTEXT' and u['fallback_reason']=='PRODUCT_DIRECTION_REF_REQUIRED'
# UI positive with exact product direction ref.
u2=build_context_pack([kb('u','AUTOGESTION_DIGITAL')],[ev('u','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',prerequisites=['PRODUCT_DIRECTION_AUTHORIZED_CURRENT'],product_direction_ref='product://decision/1')
inv(u2); assert u2['fallback'] is None and u2['product_direction_ref']=='product://decision/1'; assert u2['context_bytes']<=5000
# Prerequisite missing stays fail closed.
u3=build_context_pack([kb('u','AUTOGESTION_DIGITAL')],[ev('u','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',product_direction_ref='product://decision/1')
inv(u3); assert u3['fallback']=='NO_COMPETITIVE_CONTEXT'
# Unknown consumer/capability must never get context.
x=build_context_pack([kb('a')],[ev('a')],'UNKNOWN','UNKNOWN')
inv(x); assert x['fallback']=='NO_COMPETITIVE_CONTEXT' and x['selected_learning_ids']==[]
# Full pack byte budget trims evidence deterministically.
rows=[kb(str(i),summary='x'*2500,q=10-i) for i in range(5)]; events=[ev(str(i),eid=10+i) for i in range(5)]
b=build_context_pack(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',explicit_constraints=['C1'])
inv(b); assert b['context_bytes']<=6000 and 0<len(b['selected_learning_ids'])<5
print('LEARNING_DETERMINISTIC_CONTEXT_PACK_BUILDER=PASS pd=1 ui_positive=1 ui_failclosed=2 unknown=1 bounded_trim=PASS sections=facts,evidence,constraints,policies llm=0 rt=0 writes=0')
