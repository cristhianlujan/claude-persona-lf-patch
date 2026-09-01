#!/usr/bin/env python3
import json
from pathlib import Path
import yaml

R=Path(__file__).resolve().parent
B=yaml.safe_load((R/'learning_consumer_bindings_v2.yaml').read_text())
C=json.loads((R/'product_director_learning_classification_readback_v1.json').read_text())
E=json.loads((R/'product_director_learning_kb_eligibility_readback_v1.json').read_text())
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text())
ALLOWED_L={'ANALIZADO','CARD_CREADA'}
ALLOWED_E={'PASS','CANONICAL_PASS','CANONICAL_PASS_STALE_NOTE_FLAGGED'}
REQ={'consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','version','source_learning_ids','champion_id','challenger_id','provenance'}

def main():
 assert B['consumer']['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
 receipts={x['kb_id']:x for x in C['receipts']}
 eligible=set(E['selected_ids'])
 dyn={(x['consumer_id'],x['capability_id']):set(x['cluster_codes']) for x in D['bindings']}
 seen=set(); checked=0
 for row in B['bindings']:
  assert not (REQ-set(row)), (row.get('binding_id'),sorted(REQ-set(row)))
  assert row['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
  assert row['fallback']=='NO_COMPETITIVE_CONTEXT'
  assert row['lifecycle_state']=='READY_FOR_BINDING'
  assert row['context_budget']['selection']=='DETERMINISTIC_FIRST'
  ids=set(row['source_learning_ids']); refs={x.rsplit('/',1)[-1] for x in row['selected_evidence_refs']}
  assert ids==refs
  allowed=dyn[(row['consumer_id'],row['capability_id'])]
  for kid in ids:
   assert kid in eligible
   r=receipts[kid]
   assert r['lifecycle'] in ALLOWED_L and r['eligibility'] in ALLOWED_E
   assert set(r['cluster_code'].split('|')) & allowed, (row['capability_id'],kid,r['cluster_code'])
   checked+=1
  assert row['binding_id'] not in seen; seen.add(row['binding_id'])
 assert checked==13 and len(seen)==5
 assert set(E['excluded_due_cluster_mismatch']).isdisjoint(eligible)
 print('PRODUCT_DIRECTOR_EXACT_BINDING=PASS bindings=5/5 selected_refs=13/13 canonical_cluster_match=13/13 composite_eligibility=13/13')
if __name__=='__main__': main()
