#!/usr/bin/env python3
import ast,json,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parent
ALLOWED={'CHALLENGER_WINS','CHAMPION_RETAINS','NEEDS_REPAIR','INSUFFICIENT_EVIDENCE'}
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
def main():
 p=subprocess.run([sys.executable,str(R/'validate_learning_readonly_benchmark_50_v1.py')],capture_output=True,text=True)
 req(p.returncode==0,'ROUTING_VALIDATOR:'+p.stdout+p.stderr)
 result=ast.literal_eval(p.stdout.strip().splitlines()[-1])
 req(result['result'] in ALLOWED,'ALLOWED_OUTCOME')
 req(result['routing_gate']=='PASS','ROUTING_GATE')
 req(result['behavioral_ab']=='NOT_EXECUTED','BEHAVIORAL_NOT_EXECUTED')
 metrics=[]
 for name in ('product_director_learning_efficiency_metrics_v1.json','ui_architect_learning_efficiency_metrics_v1.json'):
  d=json.loads((R/name).read_text()); metrics.append(d)
  req(d['outcome']=='INSUFFICIENT_EVIDENCE','METRIC_OUTCOME_'+d['consumer_id'])
  req(d['efficiency']['selector_llm_calls']==0 and d['efficiency']['selector_round_trips']==0 and d['efficiency']['reader_writes']==0,'ZERO_SELECTOR_COST_'+d['consumer_id'])
  req(d['performance']['runtime_case_p50_ms']=='NOT_OBSERVED' and d['performance']['runtime_case_p95_ms']=='NOT_OBSERVED' and d['performance']['runtime_case_max_ms']=='NOT_OBSERVED','PERFORMANCE_NOT_OBSERVED_'+d['consumer_id'])
  req(d['quality']['critical_family_regression']=='NOT_OBSERVED_BEHAVIORALLY','QUALITY_RUNTIME_NOT_OBSERVED_'+d['consumer_id'])
  req(d['stability']['repeatability']=='DETERMINISTIC_SOURCE_TEST_ONLY_RUNTIME_NOT_EXECUTED','STABILITY_RUNTIME_NOT_OBSERVED_'+d['consumer_id'])
 req(result['result']=='INSUFFICIENT_EVIDENCE','NO_PREMATURE_CHAMPION_OUTCOME')
 print('LEARNING_BENCHMARK_OUTCOME_CONTRACT=PASS consumers=2 routing_gate=PASS runtime_metrics=NOT_OBSERVED behavioral_ab=NOT_EXECUTED outcome=INSUFFICIENT_EVIDENCE')
if __name__=='__main__': main()
