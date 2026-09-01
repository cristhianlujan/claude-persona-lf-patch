#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_specialized_consumer_authority_negative_cases_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_AUTHORITY_NEGATIVE_CASES_V1','SCHEMA')
req(D['mode']=='READ_ONLY_OFFLINE','MODE')
req(len(D['cases'])==12,'COUNT')
ids={c['id'] for c in D['cases']}
req(len(ids)==12,'UNIQUE')
req(all(c['expected'] in {'BLOCK','NO_COMPETITIVE_CONTEXT'} for c in D['cases']),'OUTCOMES')
req(sum(1 for c in D['cases'] if c['consumer']=='CX_TRUST')==6,'CX_COUNT')
req(sum(1 for c in D['cases'] if c['consumer']=='UX')==6,'UX_COUNT')
req(any(c['condition']=='direct_kb_injection_attempt' and c['expected']=='BLOCK' for c in D['cases'] if c['consumer']=='CX_TRUST'),'CX_DIRECT')
req(any(c['condition']=='direct_kb_injection_attempt' and c['expected']=='BLOCK' for c in D['cases'] if c['consumer']=='UX'),'UX_DIRECT')
req(D['critical_false_positive_budget']==0,'FP_BUDGET')
req(D['automatic_impact'] is False and D['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_SPECIALIZED_CONSUMER_AUTHORITY_NEGATIVE_CASES=PASS cases=12/12 cx=6 ux=6 critical_fp_budget=0')
