#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
A=json.loads((R/'learning_next_consumer_applicability_v1.json').read_text())
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text())
def main():
 assert A['governed_targets']==4 and A['automatic_binding'] is False and A['production_authorized'] is False
 targets={x['consumer_id']:x for x in A['targets']}
 assert targets['PERFIL-PRODUCT-DIRECTOR-LF']['exact_capabilities']==5
 assert targets['PERFIL-UI-ARCHITECT']['exact_capabilities']==2
 assert targets['PERFIL-GAMIFICATION-SYSTEM-ARCHITECT']['read_only_learning_status']=='NO_EXACT_CONSUMER'
 assert targets['PERFIL-GAMIFICATION-SYSTEM-ARCHITECT']['fallback']=='NO_COMPETITIVE_CONTEXT'
 f=targets['ACT-0051']
 assert f['read_only_learning_status']=='READY_FOR_BINDING_AFTER_UPSTREAM_UI_AUTHORITY'
 assert f['runtime_status']=='NO_APLICA' and set(f['required_prerequisites'])=={'PRODUCT_DIRECTION_AUTHORIZED_CURRENT','UI_ARCHITECTURE_AUTHORIZED_CURRENT'}
 catalog_consumers={x['consumer_id'] for x in D['bindings']}
 assert catalog_consumers=={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}
 print('LEARNING_NEXT_CONSUMER_APPLICABILITY=PASS governed_targets=4 exact_consumers=2 no_exact=1 waiting_upstream=1 automatic_binding=0')
if __name__=='__main__': main()
