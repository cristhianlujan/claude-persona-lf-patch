#!/usr/bin/env python3
from __future__ import annotations
import json,re,statistics,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_ui_consumer_50_cases_v1.yaml'
FIXTURE=ROOT/'sandbox/lf_contract_gate_test/learning_ui_consumer_input_fixture_v1.json'
CONSUMER='PERFIL-UI-ARCHITECT'
ALLOWED_TASKS={'UI_SELF_SERVICE_CREATE','UI_NO_ADEUDO_CREATE','UI_SELF_SERVICE_REMEDIATE','UI_NO_ADEUDO_REMEDIATE','UI_BOUNDED_PATTERN_REVIEW','UI_STATE_RECOVERY','UI_MULTI_DOMAIN_SPEC','UI_REGRESSION_REPAIR'}
ALLOWED_PRODUCT={'AUTHORIZED_CURRENT'}
ALLOWED_EVIDENCE={'GROUNDED_CURRENT'}
def parse_cases():
 raw=FIXTURE.read_text(encoding='utf-8')
 if 'expected' in raw.lower() or '"invoke"' in raw.lower(): raise SystemExit('UI fixture must not contain expected/invoke labels')
 stimuli=json.loads(raw).get('cases',{})
 out=[]
 for line in MATRIX.read_text(encoding='utf-8').splitlines():
  line=line.strip()
  if not line.startswith('- {id:'): continue
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: raise SystemExit(f'malformed UI case: {line}')
  cid,family,invoke,expect,prohibit=[x.strip() for x in m.groups()]
  s=stimuli.get(cid)
  if not isinstance(s,dict): raise SystemExit(f'missing UI stimulus: {cid}')
  out.append({'id':cid,'family':family,'expected':invoke=='true','task_kind':s.get('task_kind'),'product_direction_state':s.get('product_direction_state'),'evidence_state':s.get('evidence_state'),'expect':expect,'prohibit':prohibit})
 if set(stimuli)!=set(x['id'] for x in out): raise SystemExit('UI fixture/matrix universe mismatch')
 return out
def champion_selector(case): return None
def challenger_selector(case):
 return CONSUMER if case['task_kind'] in ALLOWED_TASKS and case['product_direction_state'] in ALLOWED_PRODUCT and case['evidence_state'] in ALLOWED_EVIDENCE else None
def metrics(cases,selector):
 tp=tn=fp=fn=0; lat=[]; fam={}
 for case in cases:
  t0=time.perf_counter_ns(); actual=selector(case) is not None; lat.append(time.perf_counter_ns()-t0); expected=case['expected']; f=fam.setdefault(case['family'],{'tp':0,'tn':0,'fp':0,'fn':0})
  if actual and expected: tp+=1;f['tp']+=1
  elif actual and not expected: fp+=1;f['fp']+=1
  elif not actual and expected: fn+=1;f['fn']+=1
  else: tn+=1;f['tn']+=1
 ordered=sorted(lat)
 return {'tp':tp,'tn':tn,'fp':fp,'fn':fn,'precision':round(tp/(tp+fp),4) if tp+fp else 0.0,'recall':round(tp/(tp+fn),4) if tp+fn else 0.0,'specificity':round(tn/(tn+fp),4) if tn+fp else 0.0,'runtime_ns_p50':int(statistics.median(lat)),'runtime_ns_p95':int(ordered[max(0,int(len(ordered)*.95)-1)]),'runtime_ns_max':max(lat),'llm_calls':0,'round_trips':0,'by_family':fam}
def main():
 cases=parse_cases()
 if len(cases)!=50: raise SystemExit(f'UI expected 50 cases, got {len(cases)}')
 champion=metrics(cases,champion_selector); challenger=metrics(cases,challenger_selector); positive=sum(c['expected'] for c in cases); negative=50-positive
 fail_family=any(v['fp'] or v['fn'] for v in challenger['by_family'].values())
 verdict='CHALLENGER_WINS' if challenger['fp']==0 and challenger['fn']==0 and not fail_family else 'NEEDS_REPAIR'
 result={'benchmark':'LEARNING_UI_CONSUMER_ROUTING_AB_V1_NON_TAUTOLOGICAL','fixture_independent_of_expected':True,'cases':50,'positive_cases':positive,'negative_cases':negative,'champion_id':'CHAMPION-UI-ARCHITECT-NO-COMPETITIVE-CONTEXT-v1','challenger_id':'CHALLENGER-UI-ARCHITECT-SELECTED-COMPETITIVE-UI-CONTEXT-v1','champion':champion,'challenger':challenger,'behavioral_quality_status':'BENCHMARK_REQUIRED_PROFILE_RUNTIME','provider_cost_status':'PROVIDER_COST_UNAVAILABLE_ZERO_LLM_CALL_ROUTING_LAYER','routing_verdict':verdict}
 print('LEARNING_UI_CONSUMER_ROUTING_BENCHMARK='+json.dumps(result,sort_keys=True)); return 0 if verdict=='CHALLENGER_WINS' else 1
if __name__=='__main__': raise SystemExit(main())
