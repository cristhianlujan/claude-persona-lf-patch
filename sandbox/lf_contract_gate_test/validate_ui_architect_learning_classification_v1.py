#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
C=json.loads((R/'ui_architect_learning_classification_readback_v1.json').read_text())
P=json.loads((R/'ui_architect_learning_context_pack_v1.json').read_text())
ALLOWED_LIFECYCLE={'ANALIZADO','CARD_CREADA'}
ALLOWED_ELIGIBILITY={'PASS','CANONICAL_PASS','CANONICAL_PASS_STALE_NOTE_FLAGGED'}
CAP_CLUSTERS={'DIGITAL_SELF_SERVICE':{'AUTOGESTION_DIGITAL'},'PAYMENT_NO_ADEUDO':{'PAGOS_Y_NO_ADEUDO'}}
def main():
 receipts={r['kb_id']:r for r in C['receipts']}; checked=0
 for capability,spec in P['capabilities'].items():
  for kid in spec['source_learning_ids']:
   r=receipts[kid]; clusters=set(r['cluster_code'].split('|'))
   assert r['lifecycle'] in ALLOWED_LIFECYCLE
   assert r['eligibility'] in ALLOWED_ELIGIBILITY
   assert clusters & CAP_CLUSTERS[capability]
   assert r['automatic_impact'] is False
   checked+=1
 assert checked==4
 print('UI_ARCHITECT_CLASSIFICATION_READBACK=PASS exact_receipts=4/4 taxonomy=LF_LEARNING_CLUSTER_V1 lifecycle_allowed=4/4 eligibility_allowed=4/4')
if __name__=='__main__': main()
