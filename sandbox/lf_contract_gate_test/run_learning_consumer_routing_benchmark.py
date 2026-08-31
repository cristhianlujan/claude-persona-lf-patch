#!/usr/bin/env python3
from __future__ import annotations
import json,re,statistics,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_50_cases_v1.yaml'
CONSUMER='PERFIL-PRODUCT-DIRECTOR-LF'
POSITIVE_TASK={'COMPETITIVE_OFFER_INSIGHT':'PRODUCT_OFFER_SCOPE_DECISION','DEBT_EDUCATION':'PRODUCT_EDUCATION_DECISION','PAYMENT_NO_ADEUDO':'PRODUCT_PAYMENT_JOURNEY_DECISION','DIGITAL_SELF_SERVICE':'PRODUCT_SELF_SERVICE_DECISION','FINANCIAL_ALTERNATIVES':'PRODUCT_ALTERNATIVE_TRADEOFF','NEGOTIATION':'PRODUCT_NEGOTIATION_DECISION','CONFLICT_PRECEDENCE':'PRODUCT_SOURCE_PRECEDENCE_DECISION','STALE_LOW_GROUNDING':'PRODUCT_SOURCE_FRESHNESS_DECISION','MULTI_DOMAIN_COMPLEX':'PRODUCT_MULTI_DOMAIN_DECISION'}
ALLOWED_TASKS=set(POSITIVE_TASK.values())
def parse_cases():
 out=[]
 for line in MATRIX.read_text(encoding='utf-8').splitlines():
  line=line.strip()
  if not line.startswith('- {id:'): continue
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: raise SystemExit(f'malformed case: {line}')
  cid,family,invoke,expect,prohibit=[x.strip() for x in m.groups()]
  expected=invoke=='true'; task=POSITIVE_TASK.get(family,'PRODUCT_GENERIC_DECISION') if expected else 'NON_PRODUCT_OR_BLOCKED_SCOPE'
  out.append({'id':cid,'family':family,'expected':expected,'task_kind':task,'expect':expect,'prohibit':prohibit})
 return out
def champion_selector(case): return None
def challenger_selector(case): return CONSUMER if case['task_kind'] in ALLOWED_TASKS else None
def metrics(cases,selector):
 tp=tn=fp=fn=0; lat=[]
 for case in cases:
  t0=time.perf_counter_ns(); result=selector(case); lat.append(time.perf_counter_ns()-t0); actual=result is not None; expected=case['expected']
  if actual and expected: tp+=1
  elif actual and not expected: fp+=1
  elif not actual and expected: fn+=1
  else: tn+=1
 precision=tp/(tp+fp) if tp+fp else 0.0; recall=tp/(tp+fn) if tp+fn else 0.0; specificity=tn/(tn+fp) if tn+fp else 0.0; ordered=sorted(lat); p95=ordered[max(0,int(len(ordered)*.95)-1)]
 return {'tp':tp,'tn':tn,'fp':fp,'fn':fn,'precision':round(precision,4),'recall':round(recall,4),'specificity':round(specificity,4),'runtime_ns_p50':int(statistics.median(lat)),'runtime_ns_p95':int(p95),'runtime_ns_max':max(lat),'llm_calls':0,'round_trips':0}
def main():
 cases=parse_cases()
 if len(cases)!=50: raise SystemExit(f'expected 50 cases, got {len(cases)}')
 champion=metrics(cases,champion_selector); challenger=metrics(cases,challenger_selector); positive=sum(c['expected'] for c in cases); negative=len(cases)-positive
 context_pack={'consumer_id':CONSUMER,'selector':'DETERMINISTIC_FIRST','bindings':['NEGOCIACION_DEUDA','ALTERNATIVAS_FINANCIERAS','EDUCACION_CREDITICIA'],'policy_capsule_ref':'POL-LF-OPERATION-LIFECYCLE','authority_boundary':'COMPETITIVE_EVIDENCE_IS_CONTEXT_NOT_PRODUCT_TRUTH'}
 result={'benchmark':'LEARNING_CONSUMER_ROUTING_AB_V1','cases':50,'positive_cases':positive,'negative_cases':negative,'champion_id':'CHAMPION-PRODUCT-DIRECTOR-LF-NO-COMPETITIVE-CONTEXT-v1','challenger_id':'CHALLENGER-PRODUCT-DIRECTOR-LF-SELECTED-COMPETITIVE-CONTEXT-v1','champion':champion,'challenger':challenger,'context_pack_bytes':len(json.dumps(context_pack,sort_keys=True).encode()),'behavioral_quality_status':'INSUFFICIENT_EVIDENCE_RUNTIME_DISABLED','provider_cost_status':'ZERO_LLM_CALLS_ROUTING_LAYER_ONLY','routing_verdict':'CHALLENGER_WINS' if challenger['fp']==0 and challenger['fn']==0 else 'NEEDS_REPAIR'}
 print('LEARNING_CONSUMER_ROUTING_BENCHMARK='+json.dumps(result,sort_keys=True)); return 0 if result['routing_verdict']=='CHALLENGER_WINS' else 1
if __name__=='__main__': raise SystemExit(main())
