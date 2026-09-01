#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
MOD=ROOT/'sandbox/lf_contract_gate_test/learning_dynamic_context_selector_v2.py'
spec=importlib.util.spec_from_file_location('dynamic_selector',MOD); mod=importlib.util.module_from_spec(spec); sys.modules[spec.name]=mod; spec.loader.exec_module(mod)
DynamicBindingSpec=mod.DynamicBindingSpec
select=mod.select_dynamic_read_only_context

FAMILIES=[
 'HAPPY_PATH','NEGATIVE_INELIGIBLE_KB','WRONG_CLUSTER','STALE_TAXONOMY','BAD_LIFECYCLE',
 'MULTI_CLUSTER','DUPLICATE_RECEIPT','QUALITY_RANKING','BOUNDED_TOP5','OUT_OF_SCOPE_NO_INVOKE'
]

def kb(kid,score='0.80',ready=True,ground='GROUNDED',category='COMPETENCIA'):
 return {'kb_id':kid,'kb_category':category,'consumer_ready':ready,'grounding_status':ground,'quality_score':score,'topic':'t'+kid,'summary':'s'+kid,'source_url':'https://example.invalid/'+kid,'competitor':'C'}
def ev(eid,kid,cluster='NEGOCIACION_DEUDA',taxonomy='LF_LEARNING_CLUSTER_V1',lifecycle='ANALIZADO',eligibility='PASS'):
 return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':cluster,'taxonomy_version':taxonomy,'lifecycle':lifecycle,'eligibility':eligibility}}

def one(family,variant):
 binding=DynamicBindingSpec('PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',('NEGOCIACION_DEUDA',),5)
 rows=[kb(f'K{i}',f'0.{70+i}') for i in range(1,8)]
 events=[ev(100+i,f'K{i}') for i in range(1,8)]
 expected=None
 if family=='HAPPY_PATH': expected=5
 elif family=='NEGATIVE_INELIGIBLE_KB':
  rows[variant%7]['consumer_ready']=False
  rows[(variant+1)%7]['grounding_status']='UNVERIFIED'
  events[(variant+2)%7]=ev(700+variant,f'K{((variant+2)%7)+1}',eligibility='NOT_PASS')
  expected=4
 elif family=='WRONG_CLUSTER':
  events=[ev(100+i,f'K{i}','EDUCACION_CREDITICIA') for i in range(1,8)]; expected=0
 elif family=='STALE_TAXONOMY':
  events=[ev(100+i,f'K{i}',taxonomy='LF_LEARNING_CLUSTER_V0') for i in range(1,8)]; expected=0
 elif family=='BAD_LIFECYCLE':
  events=[ev(100+i,f'K{i}',lifecycle='DETECTADO') for i in range(1,8)]; expected=0
 elif family=='MULTI_CLUSTER':
  events=[ev(100+i,f'K{i}','PAGOS_Y_NO_ADEUDO|NEGOCIACION_DEUDA') for i in range(1,8)]; expected=5
 elif family=='DUPLICATE_RECEIPT':
  events += [ev(500+variant,'K7')]; expected=5
 elif family=='QUALITY_RANKING':
  expected=5
 elif family=='BOUNDED_TOP5': expected=5
 elif family=='OUT_OF_SCOPE_NO_INVOKE':
  binding=DynamicBindingSpec('PERFIL-PRODUCT-DIRECTOR-LF','DIGITAL_SELF_SERVICE',('AUTOGESTION_DIGITAL',),5); expected=0
 result=select(rows,events,binding=binding)
 if result['selected_count']!=expected: raise AssertionError(f'{family}-{variant}: {result["selected_count"]}!={expected}')
 if result['llm_calls']!=0 or result['round_trips']!=0: raise AssertionError(f'{family}-{variant}: extra calls')
 if result['selected_count']>5: raise AssertionError(f'{family}-{variant}: unbounded')
 ids=[x['kb_id'] for x in result['selected']]
 if len(ids)!=len(set(ids)): raise AssertionError(f'{family}-{variant}: duplicates')
 if family in {'HAPPY_PATH','QUALITY_RANKING','BOUNDED_TOP5'} and ids and ids[0]!='K7': raise AssertionError(f'{family}-{variant}: ranking not deterministic {ids}')
 return True

def main():
 passed=0
 for family in FAMILIES:
  for variant in range(1,6):
   one(family,variant); passed+=1
 print(f'LEARNING_DYNAMIC_SELECTOR_BENCHMARK=PASS cases={passed}/50 families=10x5 llm_calls=0 round_trips=0 max_evidence=5 exact_eligibility=1')
 print('families='+','.join(FAMILIES))
 return 0
if __name__=='__main__': raise SystemExit(main())
