#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context, SelectionError

FAMILIES=[
 ('pd_neg','PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA','NEGOCIACION_DEUDA',None,True),
 ('pd_alt','PERFIL-PRODUCT-DIRECTOR-LF','ALTERNATIVAS_FINANCIERAS','ALTERNATIVAS_FINANCIERAS',None,True),
 ('pd_edu','PERFIL-PRODUCT-DIRECTOR-LF','EDUCACION_CREDITICIA','EDUCACION_CREDITICIA',None,True),
 ('pd_self','PERFIL-PRODUCT-DIRECTOR-LF','DIGITAL_SELF_SERVICE','AUTOGESTION_DIGITAL',None,True),
 ('pd_pay','PERFIL-PRODUCT-DIRECTOR-LF','PAYMENT_NO_ADEUDO','PAGOS_Y_NO_ADEUDO',None,True),
 ('ui_self_gate','PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE','AUTOGESTION_DIGITAL',None,False),
 ('ui_self_ok','PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE','AUTOGESTION_DIGITAL','PRODUCT_DIRECTION_AUTHORIZED_CURRENT',True),
 ('ui_pay_gate','PERFIL-UI-ARCHITECT','PAYMENT_NO_ADEUDO','PAGOS_Y_NO_ADEUDO',None,False),
 ('ui_pay_ok','PERFIL-UI-ARCHITECT','PAYMENT_NO_ADEUDO','PAGOS_Y_NO_ADEUDO','PRODUCT_DIRECTION_AUTHORIZED_CURRENT',True),
 ('wrong_cluster','PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA','EDUCACION_CREDITICIA',None,False),
]

def row(k,score): return {'kb_id':k,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':score,'topic':'x','summary':'bounded','source_url':'https://example.invalid'}
def event(k,cl,eid): return {'event_id':eid,'payload':{'kb_id':k,'cluster_code':cl,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
def main():
    tp=tn=fp=fn=0; cases=[]
    for fi,(fam,cid,cap,cluster,pre,expect) in enumerate(FAMILIES):
        for i in range(5):
            k=f'{fam}-{i}'; pres=[] if pre is None else [pre]
            r=select_context([row(k,10-i)],[event(k,cluster,fi*10+i+1)],cid,cap,pres)
            actual=bool(r['selected']); cases.append((fam,i,expect,actual,r))
            if expect and actual: tp+=1
            elif expect and not actual: fn+=1
            elif not expect and actual: fp+=1
            else: tn+=1
            assert r['llm_calls']==0 and r['round_trips']==0 and r.get('context_bytes',0)<=r.get('context_budget_bytes',10**9)
    assert len(cases)==50 and fp==0 and fn==0
    print({'cases':50,'families':10,'tp':tp,'tn':tn,'fp':fp,'fn':fn,'precision':1.0,'recall':1.0,'specificity':1.0,'selector_llm_calls':0,'selector_round_trips':0,'result':'CHALLENGER_WINS_ROUTING_ONLY'})
if __name__=='__main__': main()
