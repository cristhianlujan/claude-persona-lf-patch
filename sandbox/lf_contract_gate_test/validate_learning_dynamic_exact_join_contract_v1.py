#!/usr/bin/env python3
import json
from collections import Counter
from pathlib import Path
from learning_dynamic_context_selector_clean_v1 import select_context,SelectionError
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_dynamic_exact_join_contract_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
def kb(kid='k',**kw):
    x={'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':8,'topic':'t','summary':'s','source_url':'https://example.invalid'}; x.update(kw); return x
def ev(kid='k',**kw):
    p={'kb_id':kid,'cluster_code':'NEGOCIACION_DEUDA','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}; p.update(kw); return {'event_id':1,'payload':p}
def blocked(rows,events,consumer='PERFIL-PRODUCT-DIRECTOR-LF',cap='NEGOCIACION_DEUDA'):
    try:
        out=select_context(rows,events,consumer,cap)
        return out.get('selected')==[] and out.get('fallback')=='NO_COMPETITIVE_CONTEXT'
    except SelectionError:
        return True
req(D['schema']=='LF_LEARNING_DYNAMIC_EXACT_JOIN_CONTRACT_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['rule']=='NEW_LEARNING_REQUIRES_EXACT_KB_CLASSIFICATION_RECEIPT_AND_EXACT_CONSUMER_CLUSTER_BINDING','RULE')
mutations={
 'MISSING_RECEIPT':lambda i:([kb(f'k{i}')],[],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'WRONG_KB_ID':lambda i:([kb(f'k{i}')],[ev(f'other{i}')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'WRONG_TAXONOMY':lambda i:([kb(f'k{i}')],[ev(f'k{i}',taxonomy_version='OLD')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'BAD_LIFECYCLE':lambda i:([kb(f'k{i}')],[ev(f'k{i}',lifecycle='PENDIENTE')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'BAD_ELIGIBILITY':lambda i:([kb(f'k{i}')],[ev(f'k{i}',eligibility='FAIL')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'WRONG_CLUSTER':lambda i:([kb(f'k{i}')],[ev(f'k{i}',cluster_code='CAMPANAS_Y_OFERTAS')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'WRONG_CATEGORY':lambda i:([kb(f'k{i}',kb_category='EDUCACION_FINANCIERA')],[ev(f'k{i}')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'UNGROUNDED':lambda i:([kb(f'k{i}',grounding_status='UNGROUNDED')],[ev(f'k{i}')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'CONSUMER_NOT_READY':lambda i:([kb(f'k{i}',consumer_ready=False)],[ev(f'k{i}')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'),
 'NO_EXACT_CONSUMER_BINDING':lambda i:([kb(f'k{i}')],[ev(f'k{i}')],'UNKNOWN-CONSUMER','NEGOCIACION_DEUDA'),
}
results=[]
for fam,make in mutations.items():
    for i in range(5):
        rows,events,consumer,cap=make(i); results.append((fam,blocked(rows,events,consumer,cap)))
req(len(results)==50,'CASE_COUNT')
req(Counter(x[0] for x in results)==Counter({k:5 for k in mutations}),'TEN_BY_FIVE')
req(all(x[1] for x in results),'NEGATIVE_BLOCKING')
for i in range(5):
    out=select_context([kb(f'p{i}')],[ev(f'p{i}')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    req([x['kb_id'] for x in out['selected']]==[f'p{i}'],f'POSITIVE_{i}')
    req(out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False,f'ZERO_COST_{i}')
req(D['selector_llm_calls']==0 and D['selector_round_trips']==0 and D['reader_writes']==0 and D['semantic_search'] is False,'CONTRACT_ZERO_COST')
req(D['automatic_binding'] is False and D['automatic_impact'] is False and D['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_DYNAMIC_EXACT_JOIN=PASS adversarial=50/50 families=10x5 positive=5/5 selector_llm=0 round_trips=0 writes=0')
