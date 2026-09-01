#!/usr/bin/env python3
from __future__ import annotations
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MAP=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_dynamic_cluster_bindings_v1.json'
PD=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v2.yaml'
UI=ROOT/'sandbox/lf_contract_gate_test/learning_ui_consumer_bindings_v1.yaml'
EXPECTED={
 ('PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'):('NEGOCIACION_DEUDA',),
 ('PERFIL-PRODUCT-DIRECTOR-LF','ALTERNATIVAS_FINANCIERAS'):('ALTERNATIVAS_FINANCIERAS',),
 ('PERFIL-PRODUCT-DIRECTOR-LF','EDUCACION_CREDITICIA'):('EDUCACION_CREDITICIA',),
 ('PERFIL-PRODUCT-DIRECTOR-LF','DIGITAL_SELF_SERVICE'):('AUTOGESTION_DIGITAL',),
 ('PERFIL-PRODUCT-DIRECTOR-LF','PAYMENT_NO_ADEUDO'):('PAGOS_Y_NO_ADEUDO',),
 ('PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE'):('AUTOGESTION_DIGITAL',),
 ('PERFIL-UI-ARCHITECT','PAYMENT_NO_ADEUDO'):('PAGOS_Y_NO_ADEUDO',),
}
def fail(x): raise SystemExit('FAIL dynamic-cluster-bindings: '+x)
def caps(text): return set(re.findall(r'^    capability_id:\s*(\S+)\s*$',text,re.M))
def main():
 d=json.loads(MAP.read_text())
 if d.get('mode')!='READ_ONLY' or d.get('taxonomy_version')!='LF_LEARNING_CLUSTER_V1': fail('mode/taxonomy')
 if d.get('selector')!='DETERMINISTIC_CLASSIFIED_CLUSTER_CURRENT_KB': fail('selector')
 e=d.get('eligibility',{})
 if e!={'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'classification_eligibility':['PASS','CANONICAL_PASS','CANONICAL_PASS_STALE_NOTE_FLAGGED'],'classification_lifecycle':['ANALIZADO','CARD_CREADA']}: fail('eligibility contract')
 b=d.get('boundedness',{})
 if b.get('max_evidence_refs_per_capability')!=5 or b.get('llm_calls_for_selection')!=0 or b.get('round_trips_for_selection')!=0: fail('boundedness')
 got={}
 for x in d.get('bindings',[]):
  key=(x.get('consumer_id'),x.get('capability_id'))
  if key in got: fail('duplicate '+repr(key))
  got[key]=tuple(x.get('cluster_codes',[]))
  if key[0]=='PERFIL-UI-ARCHITECT' and x.get('prerequisite')!='PRODUCT_DIRECTION_AUTHORIZED_CURRENT': fail('ui prerequisite')
 if got!=EXPECTED: fail(f'mapping mismatch {got}')
 if caps(PD.read_text())!={x[1] for x in EXPECTED if x[0]=='PERFIL-PRODUCT-DIRECTOR-LF'}: fail('PD capability mismatch')
 if caps(UI.read_text())!={x[1] for x in EXPECTED if x[0]=='PERFIL-UI-ARCHITECT'}: fail('UI capability mismatch')
 if d.get('automatic_impact') is not False or d.get('production_authorized') is not False: fail('impact boundary')
 print('LEARNING_DYNAMIC_CLUSTER_BINDINGS=PASS exact_bindings=7 consumers=2 capabilities=5 taxonomy=LF_LEARNING_CLUSTER_V1 max_evidence=5 llm_calls=0 round_trips=0')
if __name__=='__main__': main()
