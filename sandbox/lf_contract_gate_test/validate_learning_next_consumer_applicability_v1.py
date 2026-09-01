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
 assert f['runtime_status']=='NO_APLICA'
 assert f['profile_source_ref']=='profiles/frontend_prototype_architect_lf/SKILL.md' and len(f['profile_source_sha'])==40
 assert f['router_action']=='EJECUCION_PERFIL_LF' and f['route']=='ACT-0001 -> EJECUCION_PERFIL_LF -> ACT-0051'
 required={'PRODUCT_DIRECTION_AUTHORIZED_CURRENT','UI_ARCHITECTURE_AUTHORIZED_CURRENT'}
 assert set(f['required_prerequisites'])==required and set(f['must_not_invoke_without'])==required
 assert f['exact_learning_binding_created'] is False and f['direct_competitive_learning_allowed'] is False
 assert f['fallback']=='NO_COMPETITIVE_CONTEXT' and f['production_enabled'] is False
 catalog_consumers={x['consumer_id'] for x in D['bindings']}
 assert catalog_consumers=={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}
 assert 'ACT-0051' not in catalog_consumers
 print('LEARNING_NEXT_CONSUMER_APPLICABILITY=PASS governed_targets=4 exact_consumers=2 no_exact=1 waiting_upstream=1 frontend_direct_learning=false automatic_binding=0')
if __name__=='__main__': main()
