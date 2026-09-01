#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_readonly_technical_closure_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_READONLY_TECHNICAL_CLOSURE_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['router']['asset']=='ACT-0001','ROUTER')
req(D['router']['impacto_automatico']=='BLOQUEADO','AUTO_IMPACT')
req(D['product_director']['exact_bindings']=='5/5' and D['product_director']['selected_learning_ids']=='13/13','PD_BINDING')
req(D['product_director']['canonical_bridge_eligibility']=='13/13','PD_CANONICAL_ELIGIBILITY')
req(D['ui_architect']['exact_bindings']=='2/2' and D['ui_architect']['selected_learning_ids']=='4/4','UI_BINDING')
S=D['specialized_consumers']
req(S['authority_decision']=='NO_DIRECT_GENERIC_INJECTION','SPECIALIZED_AUTHORITY')
req(S['authority_event_role']=='HISTORICAL_SNAPSHOT_NOT_SUFFICIENT_FOR_PROMOTION','SPECIALIZED_EVENT_BOUNDARY')
req(S['exact_bindings_active']==0 and S['context_delivery_enabled'] is False,'SPECIALIZED_NO_DELIVERY')
req(S['source_contract_sha']=='2/2_MATCHED_BY_GIT_BLOB_SHA','SPECIALIZED_SOURCE_SHA')
req(S['activation_negative_cases']=='12/12' and S['selector_nonbinding_cases']=='10/10','SPECIALIZED_NEGATIVES')
req(S['failclosed_benchmark_cases']=='50/50' and S['failclosed_benchmark_families']=='10x5' and S['unsafe_delivery']==0,'SPECIALIZED_BENCHMARK')
req(S['readiness_matrix']=='4/4_READY_FOR_BINDING','SPECIALIZED_READINESS')
req(S['champion_challenger_outcome']=='INSUFFICIENT_EVIDENCE','SPECIALIZED_OUTCOME')
req(D['corpus']['canonical_bridge_eligible']=='35/35' and D['corpus']['eligible_classified']=='35/35','CORPUS')
req(D['behavioral']['status']=='INSUFFICIENT_EVIDENCE' and D['behavioral']['behavioral_ab']=='NOT_EXECUTED','BEHAVIORAL')
for k in ('behavioral_promotion_authorized','automatic_promotion','production_authorized','merge_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
if D['status']=='VERIFICATION_IN_PROGRESS':
    req(D['read_only_route_technically_verified'] is False,'PENDING_NOT_VERIFIED')
    req(D['exact_head_ci']['canonical_workflows_passed']<3,'PENDING_CI_NOT_3')
    req(D['closure_boundary']=='TECHNICAL_READ_ONLY_CI_RECHECK_REQUIRED','PENDING_BOUNDARY')
    req(D['next_gate']=='CURRENT_HEAD_EXACT_CI_3_OF_3','PENDING_NEXT_GATE')
    print('LEARNING_READONLY_TECHNICAL_CLOSURE=PASS_FAIL_CLOSED status=VERIFICATION_IN_PROGRESS specialized=HARDENED production_authorized=false')
elif D['status']=='TECHNICALLY_VERIFIED_READ_ONLY_CANDIDATE':
    req(D['read_only_route_technically_verified'] is True,'VERIFIED_FLAG')
    req(D['exact_head_ci']['canonical_workflows_passed']==D['exact_head_ci']['canonical_workflows_total']==3,'CI_3_OF_3')
    for k in ('lf_contract_check','validate_lf_packs','lf_bootstrap_reproducibility_probe'): req(D['exact_head_ci'][k]=='PASS','CI_'+k.upper())
    req(D['closure_boundary']=='TECHNICAL_READ_ONLY_ONLY','VERIFIED_BOUNDARY')
    print('LEARNING_READONLY_TECHNICAL_CLOSURE=PASS verified=true ci=3/3 production_authorized=false')
else:
    raise SystemExit('FAIL_STATUS')
