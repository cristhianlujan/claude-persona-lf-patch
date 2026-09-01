#!/usr/bin/env python3
import statistics,time
from learning_dynamic_context_selector_clean_v1 import select_context

def kb(i):
    return {'kb_id':str(i),'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':10-(i%5),'topic':'t','summary':'s'*40,'source_url':'https://example.invalid/'+str(i)}
def ev(i):
    return {'event_id':100+i,'payload':{'kb_id':str(i),'cluster_code':'NEGOCIACION_DEUDA','taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':'ANALIZADO','eligibility':'PASS'}}
rows=[kb(i) for i in range(35)]
events=[ev(i) for i in range(35)]
# Warm-up excludes import/startup noise.
for _ in range(20): select_context(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
samples=[]
for _ in range(500):
    t=time.perf_counter_ns(); out=select_context(rows,events,'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'); samples.append((time.perf_counter_ns()-t)/1_000_000)
    assert len(out['selected'])<=5 and out['context_bytes']<=6000
    assert out['llm_calls']==0 and out['round_trips']==0 and out['writes']==0
ordered=sorted(samples)
p50=statistics.median(ordered)
p95=ordered[int(len(ordered)*0.95)-1]
mx=max(ordered)
# Very loose regression budget: catches pathological selector regressions without pretending to be a production SLA.
assert p95<50.0,(p50,p95,mx)
print(f'LEARNING_DYNAMIC_SELECTOR_PERFORMANCE=PASS cases=500 p50_ms={p50:.4f} p95_ms={p95:.4f} max_ms={mx:.4f} budget_p95_ms=50.0 selector_llm=0 round_trips=0 writes=0 scope=DETERMINISTIC_SELECTOR_ONLY')
