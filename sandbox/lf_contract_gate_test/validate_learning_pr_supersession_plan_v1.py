#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_pr_supersession_plan_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_PR_SUPERSESSION_PLAN_V1','SCHEMA')
req(D['current_candidate']['pr']==410 and D['current_candidate']['state']=='OPEN_DRAFT','CURRENT')
req([x['pr'] for x in D['superseded_candidates']]==[369,391,401],'SUPERSEDED_SET')
req(all(x['close_only_after_current_exact_head_ci'] for x in D['superseded_candidates']),'CI_PRECONDITION')
req('PR410_EXACT_HEAD_CANONICAL_CI_3_OF_3_PASS' in D['closure_preconditions'],'CI_GATE')
req('PR410_BEHAVIORAL_REMAINS_INSUFFICIENT_EVIDENCE' in D['closure_preconditions'],'BEHAVIORAL_BOUNDARY')
req(D['closure_action']=='CLOSE_SUPERSEDED_PRS_ONLY','ACTION')
req(D['delete_branches'] is False and D['merge_any_pr'] is False and D['production_authorized'] is False,'NO_IRREVERSIBLE_PROMOTION')
print('LEARNING_PR_SUPERSESSION_PLAN=PASS current=410 superseded=3 close_after_ci=true delete_branches=false merge=false production=false')
