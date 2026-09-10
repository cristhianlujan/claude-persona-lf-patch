#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context
consumers=(
 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531',
)
capabilities=('DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO','NEGOCIACION_DEUDA','EDUCACION_CREDITICIA','UNKNOWN_CAPABILITY')
kb=[{'kb_id':'kb-1','kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':10,'topic':'x','summary':'should never be delivered','source_url':'https://example.invalid'}]
events=[{'event_id':999999,'payload':{'kb_id':'kb-1','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS','cluster_code':'AUTOGESTION_DIGITAL|PAGOS_Y_NO_ADEUDO|NEGOCIACION_DEUDA|EDUCACION_CREDITICIA'}}]
count=0
for consumer in consumers:
    for capability in capabilities:
        out=select_context(kb,events,consumer,capability,prerequisites=('PRODUCT_DIRECTION_AUTHORIZED_CURRENT',))
        assert out['selected']==[]
        assert out['fallback']=='NO_COMPETITIVE_CONTEXT'
        assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False
        assert out['nonbinding_reason']=='READY_FOR_BINDING_REVIEW_ONLY_RUNTIME_DISABLED'
        count+=1
print(f'LEARNING_SPECIALIZED_SELECTOR_NONBINDING=PASS cases={count}/10 selected=0 fallback=NO_COMPETITIVE_CONTEXT')
