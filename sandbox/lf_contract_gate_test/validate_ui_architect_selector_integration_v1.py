#!/usr/bin/env python3
from learning_dynamic_context_selector_clean_v1 import select_context

KB=[
 {'kb_id':'35cfab0c-1d91-4aa4-9761-f8af91181e17','kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':0.96,'topic':'REGISTRO_AUTOGESTION_BENEFICIOS','summary':'observed self-service registration pattern','source_url':'https://mi.finanty.com/registro'},
 {'kb_id':'7d55562e-9266-478b-b071-dca7ba1ade1a','kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':0.94,'topic':'PORTAL_AUTOGESTION_DEUDA','summary':'observed self-service debt portal pattern','source_url':'https://mi.finanty.com/'},
]
EV=[
 {'event_id':1,'payload':{'kb_id':'35cfab0c-1d91-4aa4-9761-f8af91181e17','cluster_code':'AUTOGESTION_DIGITAL','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}},
 {'event_id':2,'payload':{'kb_id':'7d55562e-9266-478b-b071-dca7ba1ade1a','cluster_code':'AUTOGESTION_DIGITAL','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}},
]
def main():
 blocked=select_context(KB,EV,'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE')
 assert blocked['selected']==[] and blocked['fallback']=='NO_COMPETITIVE_CONTEXT'
 assert blocked['blocked_by_prerequisite']=='PRODUCT_DIRECTION_AUTHORIZED_CURRENT'
 allowed=select_context(KB,EV,'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',{'PRODUCT_DIRECTION_AUTHORIZED_CURRENT'})
 assert len(allowed['selected'])==2 and allowed['fallback'] is None
 assert allowed['llm_calls']==0 and allowed['round_trips']==0 and allowed['context_bytes']<=allowed['context_budget_bytes']<=5000
 print('UI_ARCHITECT_SELECTOR_INTEGRATION=PASS blocked_without_prerequisite=1 allowed_with_prerequisite=1 selected=2/2 llm_calls=0 round_trips=0')
if __name__=='__main__': main()
