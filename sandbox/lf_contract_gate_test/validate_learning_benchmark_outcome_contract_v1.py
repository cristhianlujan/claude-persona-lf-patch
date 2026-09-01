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
  consumer_id=d.get('consumer_id','UNKNOWN_CONSUMER')
  req(d.get('outcome')=='INSUFFICIENT_EVIDENCE','METRIC_OUTCOME_'+consumer_id)
  efficiency=d.get('efficiency',{})
  req(efficiency.get('selector_llm_calls')==0 and efficiency.get('selector_round_trips')==0 and efficiency.get('reader_writes')==0,'ZERO_SELECTOR_COST_'+consumer_id)
  performance=d.get('performance',{})
  req(performance.get('runtime_case_p50_ms')=='NOT_OBSERVED' and performance.get('runtime_case_p95_ms')=='NOT_OBSERVED' and performance.get('runtime_case_max_ms')=='NOT_OBSERVED','PERFORMANCE_NOT_OBSERVED_'+consumer_id)
  quality=d.get('quality',{})
  req(quality.get('critical_family_regression')=='NOT_OBSERVED_BEHAVIORALLY','QUALITY_RUNTIME_NOT_OBSERVED_'+consumer_id)
  stability=d.get('stability',{})
  req(stability.get('selector_repeatability')=='PASS_DETERMINISTIC','SELECTOR_STABILITY_'+consumer_id)
  req(stability.get('runtime_repeatability')=='NOT_OBSERVED_RUNTIME_NOT_EXECUTED','STABILITY_RUNTIME_NOT_OBSERVED_'+consumer_id)
 req(result['result']=='INSUFFICIENT_EVIDENCE','NO_PREMATURE_CHAMPION_OUTCOME')
 print('LEARNING_BENCHMARK_OUTCOME_CONTRACT=PASS consumers=2 routing_gate=PASS selector_repeatability=PASS_DETERMINISTIC runtime_metrics=NOT_OBSERVED behavioral_ab=NOT_EXECUTED outcome=INSUFFICIENT_EVIDENCE')
if __name__=='__main__': main()
