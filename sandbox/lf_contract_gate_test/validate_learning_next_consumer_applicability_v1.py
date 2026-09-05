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
 assert targets['PERFIL-PRODUCT-DIRECTOR-LF']['adapter_runtime_enabled'] is True and targets['PERFIL-PRODUCT-DIRECTOR-LF']['profile_runtime_state']=='NO_HABILITADO'
 assert targets['PERFIL-UI-ARCHITECT']['exact_capabilities']==2
 assert targets['PERFIL-UI-ARCHITECT']['adapter_runtime_enabled'] is True and targets['PERFIL-UI-ARCHITECT']['profile_runtime_state']=='NO_HABILITADO'
 g=targets['PERFIL-GAMIFICATION-SYSTEM-ARCHITECT']
 assert g['read_only_learning_status']=='NO_EXACT_CONSUMER' and g['fallback']=='NO_COMPETITIVE_CONTEXT' and g['profile_runtime_state']=='NO_HABILITADO'
 assert g['profile_source_sha']=='5e805cb355da421a76c917e965f2971675e80a9e'
 assert 'NO_EXACT_GAMIFICATION_CAPABILITY' in g['reason'] and 'NOT_FINANCIAL_OR_SAFETY_AUTHORITY' in g['reason']
 f=targets['ACT-0051']
 assert f['read_only_learning_status']=='NO_DIRECT_LEARNING_BINDING_UPSTREAM_CONTEXT_ONLY'
 assert f['runtime_status']=='NO_APLICA'
 required={'PRODUCT_DIRECTION_AUTHORIZED_CURRENT','UI_ARCHITECTURE_AUTHORIZED_CURRENT'}
 assert set(f['required_prerequisites'])==required and set(f['must_not_invoke_without'])==required
 assert f['exact_learning_binding_created'] is False and f['direct_competitive_learning_allowed'] is False
 assert f['fallback']=='NO_COMPETITIVE_CONTEXT' and f['production_enabled'] is False
 assert 'COMPETITIVE_LEARNING_MUST_ARRIVE_ONLY_THROUGH_AUTHORIZED_UPSTREAM_CONTEXT' in f['reason']
 catalog_consumers={x['consumer_id'] for x in D['bindings']}
 assert catalog_consumers=={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}
 assert 'ACT-0051' not in catalog_consumers and 'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT' not in catalog_consumers
 assert A['source_operativa_readback']['ACT-0051']=='NO_APLICA'
 print('LEARNING_NEXT_CONSUMER_APPLICABILITY=PASS governed_targets=4 exact_consumers=2 no_exact=2 downstream_frontend=UPSTREAM_CONTEXT_ONLY runtime_states_reconciled=4')
if __name__=='__main__': main()
