#!/usr/bin/env python3
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=ROOT/'sandbox/lf_contract_gate_test/learning_additional_consumers_50_cases_v1.json'
UX='PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
CX='PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531'
SUPPORTED={
 (UX,'DIGITAL_SELF_SERVICE'): {'PRODUCT_DIRECTION_AUTHORIZED_CURRENT','TARGET_MARKETPLACE_SURFACE_CURRENT'},
 (CX,'PAYMENT_NO_ADEUDO'): {'PRODUCT_CLAIM_AUTHORITY_CURRENT','SUPPORT_AUTHORITY_CURRENT'},
 (CX,'NEGOCIACION_DEUDA'): {'PRODUCT_CLAIM_AUTHORITY_CURRENT','NEGOTIATION_FLOW_CURRENT'},
}

def route(case):
 key=(case['consumer_id'],case['capability_id'])
 if key not in SUPPORTED: return 'MUST_NOT_INVOKE'
 if case.get('direct_learning_requested') is True: return 'BLOCK_DIRECT_LEARNING'
 if case.get('claim_boundary_ok') is not True: return 'BLOCK_CLAIM_BOUNDARY'
 if not SUPPORTED[key].issubset(set(case.get('prerequisites',[]))): return 'RETURN_UPSTREAM_AUTHORITY'
 return 'CANDIDATE_CONTEXT_ALLOWED'

def main():
 data=json.loads(CASES.read_text())
 cases=data.get('cases',[])
 results=[]; cm=Counter(); fam=Counter()
 for c in cases:
  got=route(c); exp=c['expected_route']; ok=got==exp
  results.append({'id':c['id'],'family':c['family'],'expected':exp,'actual':got,'pass':ok})
  fam[c['family']]+=1
  if exp=='CANDIDATE_CONTEXT_ALLOWED' and got=='CANDIDATE_CONTEXT_ALLOWED': cm['tp']+=1
  elif exp!='CANDIDATE_CONTEXT_ALLOWED' and got!='CANDIDATE_CONTEXT_ALLOWED': cm['tn']+=1
  elif exp!='CANDIDATE_CONTEXT_ALLOWED' and got=='CANDIDATE_CONTEXT_ALLOWED': cm['fp']+=1
  else: cm['fn']+=1
 total=len(cases); passed=sum(1 for x in results if x['pass'])
 precision=cm['tp']/(cm['tp']+cm['fp']) if cm['tp']+cm['fp'] else 1.0
 recall=cm['tp']/(cm['tp']+cm['fn']) if cm['tp']+cm['fn'] else 1.0
 specificity=cm['tn']/(cm['tn']+cm['fp']) if cm['tn']+cm['fp'] else 1.0
 out={'schema':'LF_LEARNING_ADDITIONAL_CONSUMERS_ROUTING_BENCHMARK_V1','cases':total,'families':len(fam),'passed':passed,'failed':total-passed,'family_counts':dict(sorted(fam.items())),'routing':{'tp':cm['tp'],'tn':cm['tn'],'fp':cm['fp'],'fn':cm['fn'],'precision':round(precision,6),'recall':round(recall,6),'specificity':round(specificity,6)},'llm_calls':0,'round_trips':0,'tool_calls':0,'production_impact':False}
 print(json.dumps(out,sort_keys=True))
 return 0 if passed==total and cm['fp']==0 and cm['fn']==0 else 1
if __name__=='__main__': raise SystemExit(main())
