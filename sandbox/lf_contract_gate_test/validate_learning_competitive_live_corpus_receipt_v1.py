#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_competitive_live_corpus_receipt_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_COMPETITIVE_LIVE_CORPUS_RECEIPT_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['source']=='public.lf_knowledge_base','SOURCE')
req(D['competencia_total']==43,'TOTAL')
req(D['eligible_grounded_consumer_ready']==35,'ELIGIBLE')
req(D['ineligible_or_not_ready']==D['competencia_total']-D['eligible_grounded_consumer_ready']==8,'INELIGIBLE')
p=D['eligibility_predicate']
req(p=={'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True},'PREDICATE')
req(D['new_eligible_since_current_learning_snapshot']==0,'NEW_ELIGIBLE')
req(D['automatic_binding'] is False and D['semantic_search'] is False,'NO_AUTH_EXPANSION')
req(D['reader_writes']==0 and D['production_authorized'] is False,'READ_ONLY')
print('LEARNING_COMPETITIVE_LIVE_CORPUS_RECEIPT=PASS competencia=43 eligible=35 ineligible=8 new_eligible=0 writes=0 semantic_search=false')
