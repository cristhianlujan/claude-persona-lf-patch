#!/usr/bin/env python3
from __future__ import annotations
import json,re,statistics,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_50_cases_v1.yaml'
FIXTURE=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_input_fixture_v2.json'
CONSUMER='PERFIL-PRODUCT-DIRECTOR-LF'
ALLOWED_TASKS={'PRODUCT_OFFER_SCOPE_DECISION','PRODUCT_EDUCATION_DECISION','PRODUCT_PAYMENT_JOURNEY_DECISION','PRODUCT_SELF_SERVICE_DECISION','PRODUCT_ALTERNATIVE_TRADEOFF','PRODUCT_NEGOTIATION_DECISION','PRODUCT_SOURCE_PRECEDENCE_DECISION','PRODUCT_SOURCE_FRESHNESS_DECISION','PRODUCT_MULTI_DOMAIN_DECISION'}
ALLOWED_EVIDENCE={'GROUNDED_CURRENT'}
def parse_cases():
 fixture=json.loads(FIXTURE.read_text(encoding='utf-8'))
 if 'expected' in FIXTURE.read_text(encoding='utf-8').lower() or '"invoke"' in FIXTURE.read_text(encoding='utf-8').lower():
  raise SystemExit('fixture must not contain expected/invoke labels')
 stimuli=fixture.get('cases',{})
 out=[]
 for line in MATRIX.read_text(encoding='utf-8').splitlines():
  line=line.strip()
  if not line.startswith('- {id:'): continue
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: raise SystemExit(f'malformed case: {line}')
  cid,family,invoke,expect,prohibit=[x.strip() for x in m.groups()]
  stimulus=stimuli.get(cid)
  if not isinstance(stimulus,dict): raise SystemExit(f'missing stimulus: {cid}')
  out.append({'id':cid,'family':family,'expected':invoke=='true','task_kind':stimulus.get('task_kind'),'evidence_state':stimulus.get('evidence_state'),'expect':expect,'prohibit':prohibit})
 if set(stimuli)!=set(x['id'] for x in out): raise SystemExit('fixture/matrix case universe mismatch')
 return out
def champion_selector(case): return None
def challenger_selector(case):
 return CONSUMER if case['task_kind'] in ALLOWED_TASKS and case['evidence_state'] in ALLOWED_EVIDENCE else None
def metrics(cases,selector):
 tp=tn=fp=fn=0; lat=[]; family={}
 for case in cases:
  t0=time.perf_counter_ns(); result=selector(case); lat.append(time.perf_counter_ns()-t0); actual=result is not None; expected=case['expected']
  fam=family.setdefault(case['family'],{'tp':0,'tn':0,'fp':0,'fn':0})
  if actual and expected: tp+=1; fam['tp']+=1
  elif actual and not expected: fp+=1; fam['fp']+=1
  elif not actual and expected: fn+=1; fam['fn']+=1
  else: tn+=1; fam['tn']+=1
 precision=tp/(tp+fp) if tp+fp else 0.0; recall=tp/(tp+fn) if tp+fn else 0.0; specificity=tn/(tn+fp) if tn+fp else 0.0; ordered=sorted(lat); p95=ordered[max(0,int(len(ordered)*.95)-1)]
 return {'tp':tp,'tn':tn,'fp':fp,'fn':fn,'precision':round(precision,4),'recall':round(recall,4),'specificity':round(specificity,4),'runtime_ns_p50':int(statistics.median(lat)),'runtime_ns_p95':int(p95),'runtime_ns_max':max(lat),'llm_calls':0,'round_trips':0,'by_family':family}
def main():
 cases=parse_cases()
 if len(cases)!=50: raise SystemExit(f'expected 50 cases, got {len(cases)}')
 champion=metrics(cases,champion_selector); challenger=metrics(cases,challenger_selector); positive=sum(c['expected'] for c in cases); negative=len(cases)-positive
 critical_family_fail=any(v['fp'] or v['fn'] for v in challenger['by_family'].values())
 context_pack={'consumer_id':CONSUMER,'selector':'DETERMINISTIC_EXACT_ID','bindings':['NEGOCIACION_DEUDA','ALTERNATIVAS_FINANCIERAS','EDUCACION_CREDITICIA','DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'],'policy_capsule_ref':'POL-LF-OPERATION-LIFECYCLE','authority_boundary':'COMPETITIVE_EVIDENCE_IS_CONTEXT_NOT_PRODUCT_TRUTH'}
 verdict='CHALLENGER_WINS' if challenger['fp']==0 and challenger['fn']==0 and not critical_family_fail else 'NEEDS_REPAIR'
 result={'benchmark':'LEARNING_CONSUMER_ROUTING_AB_V3_NON_TAUTOLOGICAL','fixture_independent_of_expected':True,'cases':50,'positive_cases':positive,'negative_cases':negative,'champion_id':'CHAMPION-PRODUCT-DIRECTOR-LF-NO-COMPETITIVE-CONTEXT-v1','challenger_id':'CHALLENGER-PRODUCT-DIRECTOR-LF-SELECTED-COMPETITIVE-CONTEXT-v1','champion':champion,'challenger':challenger,'context_pack_bytes':len(json.dumps(context_pack,sort_keys=True).encode()),'behavioral_quality_status':'INSUFFICIENT_EVIDENCE_RUNTIME_DISABLED','provider_cost_status':'PROVIDER_COST_UNAVAILABLE_ZERO_LLM_CALL_ROUTING_LAYER','routing_verdict':verdict}
 print('LEARNING_CONSUMER_ROUTING_BENCHMARK='+json.dumps(result,sort_keys=True)); return 0 if verdict=='CHALLENGER_WINS' else 1
if __name__=='__main__': raise SystemExit(main())
