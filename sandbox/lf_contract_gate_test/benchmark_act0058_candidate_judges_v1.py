#!/usr/bin/env python3
from __future__ import annotations
import json
import statistics
import time
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=ROOT/'sandbox/lf_contract_gate_test/act0058_judge_cases_v1.json'

def eval_case(c):
 i=c['input']; j=c['judge']
 if j=='MINI_JUDGE_ACT0058_INIT_EXECUTION':
  return 'EXECUTION_INITIALIZED' if all(i.get(k) is True for k in ['operation_execution_exists','operation_code_matches','status_in_progress']) else 'BLOCKED'
 if j=='MINI_JUDGE_ACT0058_INIT':
  if i.get('dedup_24h_clear') is False: return 'DEDUP_BLOCKED'
  return 'RUN_INITIALIZED' if all(i.get(k) is True for k in ['pipeline_run_created','source_url_nonempty','stage_current_captura']) else 'BLOCKED'
 if j=='MINI_JUDGE_ACT0058_SCOPE': return 'SCOPE_ALLOWED' if i.get('source_domain_allowed') is True else 'OUT_OF_SCOPE'
 if j=='MINI_JUDGE_ACT0058_CAPTURA': return 'CAPTURE_COMPLETED' if i.get('capture_run_id_present') is True and i.get('capture_status_completed') is True else 'CAPTURE_BLOCKED'
 if j=='MINI_JUDGE_ACT0058_HOMOLOG': return 'HOMOLOG_APPROVED' if i.get('homolog_record_id_present') is True and i.get('homolog_status_aprobado') is True else 'HOMOLOG_BLOCKED'
 if j=='MINI_JUDGE_ACT0058_ANALISIS': return 'ANALYSIS_ALLOWED' if i.get('decision_id_present') is True and i.get('consumer_gate_passed_true') is True else 'ANALYSIS_BLOCKED'
 if j=='MINI_JUDGE_ACT0058_KB_WRITE': return 'KB_WRITE_CONFIRMED' if i.get('kb_id_present') is True and i.get('consumer_gate_passed_true') is True and i.get('hitl_triggered_false') is True else 'KB_WRITE_BLOCKED'
 if j=='MINI_JUDGE_ACT0058_COMPLETED': return 'COMPLETED_CONFIRMED' if i.get('stage_completed') is True and i.get('closing_event_present') is True else 'COMPLETION_BLOCKED'
 if j=='MINI_JUDGE_ACT0058_RESTOCK':
  if i.get('restock_attempt_recorded') is not True or i.get('dedup_performed') is not True: return 'RESTOCK_BLOCKED'
  if i.get('urls_insertadas',0)==0: return 'RESTOCK_NOOP_WARN' if i.get('warn_event_recorded') is True else 'RESTOCK_BLOCKED'
  return 'RESTOCK_COMPLETED'
 if j=='MINI_JUDGE_ACT0058_RETRY':
  rc=i.get('retry_count'); stage=i.get('stage_status')
  if rc is None or stage not in {'PENDING','FAILED'}: return 'RETRY_BLOCKED'
  if rc>=3: return 'RETRY_TERMINAL_FAILED' if stage=='FAILED' else 'RETRY_BLOCKED'
  return 'RETRY_ALLOWED' if stage=='PENDING' else 'RETRY_BLOCKED'
 raise ValueError(j)

def pct(values,q):
 values=sorted(values); idx=max(0,min(len(values)-1,int(round((len(values)-1)*q))))
 return values[idx]

def main():
 p=json.loads(CASES.read_text(encoding='utf-8')); cases=p['cases']
 outcomes=[]; lat=[]
 for c in cases:
  t=time.perf_counter_ns(); got=eval_case(c); lat.append((time.perf_counter_ns()-t)/1000.0)
  outcomes.append((c,got))
 failures=[(c['id'],c['expected'],got) for c,got in outcomes if got!=c['expected']]
 counts=Counter(c['judge'] for c,_ in outcomes)
 blocked_values={'BLOCKED','DEDUP_BLOCKED','OUT_OF_SCOPE','CAPTURE_BLOCKED','HOMOLOG_BLOCKED','ANALYSIS_BLOCKED','KB_WRITE_BLOCKED','COMPLETION_BLOCKED','RESTOCK_BLOCKED','RETRY_BLOCKED'}
 critical_fp=sum(1 for c,got in outcomes if c['expected'] in blocked_values and got not in blocked_values)
 report={
  'schema':'ACT0058_CANDIDATE_JUDGE_BENCHMARK_V2','cases':len(cases),'judges':len(counts),'cases_per_judge':dict(counts),
  'pass_count':len(cases)-len(failures),'fail_count':len(failures),'accuracy_pct':round(100*(len(cases)-len(failures))/len(cases),2),
  'critical_false_positives':critical_fp,'llm_calls':0,'round_trips':0,'tool_calls':0,'deterministic_share_pct':100.0,
  'runtime_us':{'p50':round(statistics.median(lat),3),'p95':round(pct(lat,.95),3),'max':round(max(lat),3)},
  'retry_evidence_contract':'retry_count+stage_status+error_detail','synthetic_next_action_used':False,
  'failures':failures,'production_impact':False
 }
 print(json.dumps(report,sort_keys=True))
 if failures or critical_fp: raise SystemExit(1)
 return 0
if __name__=='__main__': raise SystemExit(main())
