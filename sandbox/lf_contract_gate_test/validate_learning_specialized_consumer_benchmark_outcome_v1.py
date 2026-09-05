#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_specialized_consumer_benchmark_outcome_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_BENCHMARK_OUTCOME_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
N=D['negative_benchmark']; P=D['positive_activation_benchmark']
req(N['cases']=='50/50' and N['families']=='10x5' and N['unsafe_delivery']==0,'NEGATIVE_BENCHMARK')
req(N['selector_llm_calls']==0 and N['reader_writes']==0 and N['result']=='PASS_FAIL_CLOSED','NEGATIVE_ZERO_COST')
req(P['executed'] is False and P['result']=='INSUFFICIENT_EVIDENCE','POSITIVE_NOT_EXECUTED')
req(D['champion_id'] is None and D['challenger_id'] is None,'NO_FAKE_BENCHMARK_IDS')
req(D['champion_challenger_outcome']=='INSUFFICIENT_EVIDENCE','OUTCOME')
req(D['quality_gate']=='PASS_FAIL_CLOSED_ONLY','QUALITY')
req(D['performance_gate']=='NOT_APPLICABLE_ZERO_CONTEXT','PERFORMANCE')
req(D['governance_gate']=='BLOCKED_READY_FOR_BINDING','GOVERNANCE')
for k in ('behavioral_promotion_authorized','automatic_promotion','production_authorized'):
    req(D[k] is False,'NO_'+k.upper())
print('LEARNING_SPECIALIZED_CONSUMER_BENCHMARK_OUTCOME=PASS negative=50/50 positive=NOT_EXECUTED outcome=INSUFFICIENT_EVIDENCE')
