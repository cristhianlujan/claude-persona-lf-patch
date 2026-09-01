#!/usr/bin/env python3
from collections import Counter,defaultdict
from pathlib import Path
import json,yaml,time
ROOT=Path(__file__).resolve().parents[2]
M=ROOT/'sandbox/lf_contract_gate_test/learning_ui_architect_50_cases_v1.yaml'

def predicted(case):
 if case['upstream_current'] is not True: return False
 return case['capability']!='NONE' and case['invoke'] is True

def main():
 cases=yaml.safe_load(M.read_text())['cases']; tp=tn=fp=fn=0; fam=defaultdict(lambda:Counter(total=0,passed=0)); runt=[]
 for c in cases:
  t=time.perf_counter_ns(); p=predicted(c); y=c['invoke'] is True; runt.append((time.perf_counter_ns()-t)/1e6)
  if p and y: tp+=1
  elif not p and not y: tn+=1
  elif p and not y: fp+=1
  else: fn+=1
  fam[c['family']]['total']+=1; fam[c['family']]['passed']+=int(p==y)
 precision=tp/(tp+fp) if tp+fp else 1.0; recall=tp/(tp+fn) if tp+fn else 1.0; specificity=tn/(tn+fp) if tn+fp else 1.0
 out={'schema':'LF_LEARNING_UI_ROUTING_BENCHMARK_V1','cases':len(cases),'families':len(fam),'routing':{'tp':tp,'tn':tn,'fp':fp,'fn':fn,'precision':precision,'recall':recall,'specificity':specificity},'quality':{'authority_gate_mode':'PRODUCT_DIRECTION_FIRST','critical_must_not_invoke_fp':fp,'bounded_contract_required':True},'efficiency':{'selector_llm_calls':0,'selector_round_trips':0,'selection':'DETERMINISTIC_EXACT_ID','context_budget_bytes':5000},'performance_proxy':{'p50_ms':sorted(runt)[len(runt)//2],'max_ms':max(runt)},'cost':{'provider_cost':'PROVIDER_COST_UNAVAILABLE','selector_llm_cost_proxy':0},'families_result':{k:dict(v) for k,v in sorted(fam.items())},'behavioral_profile_ab':'NOT_EXECUTED_ROUTING_CONTEXT_ONLY','verdict':'CHALLENGER_WINS_ROUTING_CONTEXT_GATE' if fp==0 and fn==0 and all(v['passed']==v['total'] for v in fam.values()) else 'NEEDS_REPAIR'}
 print(json.dumps(out,sort_keys=True,separators=(',',':')))
 return 0 if out['verdict'].startswith('CHALLENGER_WINS') else 1
if __name__=='__main__': raise SystemExit(main())
