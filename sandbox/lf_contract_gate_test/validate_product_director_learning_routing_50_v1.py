#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context, SelectionError

FAMILIES=[
 ('NEGOCIACION_DEUDA','NEGOCIACION_DEUDA',True),
 ('ALTERNATIVAS_FINANCIERAS','ALTERNATIVAS_FINANCIERAS',True),
 ('EDUCACION_CREDITICIA','EDUCACION_CREDITICIA',True),
 ('DIGITAL_SELF_SERVICE','AUTOGESTION_DIGITAL',True),
 ('PAYMENT_NO_ADEUDO','PAGOS_Y_NO_ADEUDO',True),
 ('NEGOCIACION_DEUDA','BENCHMARK_PERIFERICO',False),
 ('ALTERNATIVAS_FINANCIERAS','NEGOCIACION_DEUDA',False),
 ('EDUCACION_CREDITICIA','CAMPANAS_Y_OFERTAS',False),
 ('DIGITAL_SELF_SERVICE','PAGOS_Y_NO_ADEUDO',False),
 ('PAYMENT_NO_ADEUDO','AUTOGESTION_DIGITAL',False),
]
def row(k): return {'kb_id':k,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':1.0,'topic':'bounded','summary':'bounded','source_url':'https://example.invalid'}
def event(k,cluster,eid): return {'event_id':eid,'payload':{'kb_id':k,'cluster_code':cluster,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
def main():
 tp=tn=fp=fn=passed=0
 for fi,(cap,cluster,expected_positive) in enumerate(FAMILIES):
  for i in range(5):
   kid=f'pd-{fi}-{i}'
   try:
    out=select_context([row(kid)],[event(kid,cluster,fi*5+i+1)],'PERFIL-PRODUCT-DIRECTOR-LF',cap)
    predicted=bool(out['selected'])
    assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0 and out['semantic_search'] is False
   except SelectionError:
    predicted=False
   passed+=predicted==expected_positive
   if expected_positive and predicted: tp+=1
   elif expected_positive: fn+=1
   elif predicted: fp+=1
   else: tn+=1
 assert passed==50 and fp==0 and fn==0
 precision=tp/(tp+fp); recall=tp/(tp+fn); specificity=tn/(tn+fp)
 print(f'PRODUCT_DIRECTOR_ROUTING_GOLD50=PASS cases={passed}/50 families=10x5 TP={tp} TN={tn} FP={fp} FN={fn} precision={precision:.3f} recall={recall:.3f} specificity={specificity:.3f} selector_llm_calls=0 selector_round_trips=0 reader_writes=0 semantic_search=false outcome=INSUFFICIENT_EVIDENCE')
if __name__=='__main__': main()
