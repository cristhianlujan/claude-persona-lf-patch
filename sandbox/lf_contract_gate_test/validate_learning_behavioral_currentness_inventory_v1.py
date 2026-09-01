#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_behavioral_currentness_inventory_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_BEHAVIORAL_CURRENTNESS_INVENTORY_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(len(D['runs'])==6,'RUN_COUNT')
req(sum(1 for r in D['runs'] if r['is_current'])==D['current_runs']==5,'CURRENT_COUNT')
req(sum(1 for r in D['runs'] if not r['is_current'])==D['stale_runs']==1,'STALE_COUNT')
run210=next(r for r in D['runs'] if r['run_id']==210)
req(run210['is_current'] is False,'RUN210_STALE')
req(D['consumer_count']==2 and D['consumer_behavioral_targets_declared']==0,'NO_TARGETS')
req(D['reusable_as_learning_behavioral_authority']==0,'NO_REUSE')
req(D['rule']=='CURRENT_SCREEN_RUN_IS_NOT_CONSUMER_AUTHORITY_WITHOUT_EXACT_DECLARED_BEHAVIORAL_TARGET','RULE')
req(D['behavioral_ab']=='NOT_EXECUTED' and D['outcome']=='INSUFFICIENT_EVIDENCE','FAIL_CLOSED')
req(D['production_authorized'] is False,'NO_PRODUCTION')
print('LEARNING_BEHAVIORAL_CURRENTNESS_INVENTORY=PASS current=5 stale=1 declared_targets=0 reusable_authority=0 behavioral=INSUFFICIENT_EVIDENCE')
