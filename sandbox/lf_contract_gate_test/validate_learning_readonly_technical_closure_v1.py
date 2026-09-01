#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_readonly_technical_closure_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_READONLY_TECHNICAL_CLOSURE_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['router']['asset']=='ACT-0001','ROUTER')
req(D['router']['impacto_automatico']=='BLOQUEADO','AUTO_IMPACT')
F=D['source_freshness']
req(F['snapshots_guarded']=='4/4','FRESHNESS_SNAPSHOTS')
req(F['fresh_readback_required_for_new_binding'] is True and F['fresh_readback_required_for_new_context_pack_evidence'] is True and F['fresh_readback_required_for_new_learning_admission'] is True and F['fresh_readback_required_for_card_creation_decision'] is True and F['fresh_readback_required_for_source_backlog_empty_decision'] is True,'FRESHNESS_REQUIRED')
req(F['historical_snapshot_can_authorize_promotion'] is False,'HISTORICAL_NO_PROMOTION')
RDR=D['reader']
req(RDR['dynamic_exact_join_rule']=='NEW_LEARNING_REQUIRES_EXACT_KB_CLASSIFICATION_RECEIPT_AND_EXACT_CONSUMER_CLUSTER_BINDING','READER_JOIN_RULE')
req(RDR['adversarial_cases']=='50/50' and RDR['adversarial_families']=='10x5' and RDR['positive_controls']=='5/5','READER_JOIN_BENCHMARK')
req(RDR['malformed_input_cases']=='25/25','READER_ROBUSTNESS')
req(RDR['stability_permutations']=='60/60' and RDR['ordering']=='QUALITY_DESC_RECEIPT_DESC_KB_ID_ASC','READER_STABILITY')
req(RDR['boundedness']=='MAX_REFS_5_AND_BYTE_BUDGET_ENFORCED' and RDR['utf8_byte_budget']=='PASS' and RDR['oversized_item_skip']=='PASS','READER_BOUNDEDNESS')
req(RDR['selector_llm_calls']==0 and RDR['selector_round_trips']==0 and RDR['reader_writes']==0 and RDR['semantic_search'] is False,'READER_ZERO_COST')
req(D['product_director']['exact_bindings']=='5/5' and D['product_director']['selected_learning_ids']=='13/13' and D['product_director']['selector_stability']=='60/60','PD_BINDING')
req(D['product_director']['canonical_bridge_eligibility']=='13/13','PD_CANONICAL_ELIGIBILITY')
req(D['ui_architect']['exact_bindings']=='2/2' and D['ui_architect']['selected_learning_ids']=='4/4' and D['ui_architect']['selector_stability']=='60/60','UI_BINDING')
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
for script in ('validate_learning_active_consumer_binding_contract_v1.py','validate_learning_source_snapshot_freshness_guard_v1.py'):
    r=subprocess.run([sys.executable,str(R/script)],capture_output=True,text=True)
    if r.stdout: print(r.stdout.strip())
    if r.returncode:
        if r.stderr: sys.stderr.write(r.stderr)
        raise SystemExit(r.returncode)
if D['status']=='VERIFICATION_IN_PROGRESS':
    req(D['read_only_route_technically_verified'] is False,'PENDING_NOT_VERIFIED')
    req(D['exact_head_ci']['canonical_workflows_passed']<3,'PENDING_CI_NOT_3')
    req(D['closure_boundary']=='TECHNICAL_READ_ONLY_CI_RECHECK_REQUIRED','PENDING_BOUNDARY')
    req(D['next_gate']=='CURRENT_HEAD_EXACT_CI_3_OF_3','PENDING_NEXT_GATE')
    print('LEARNING_READONLY_TECHNICAL_CLOSURE=PASS_FAIL_CLOSED status=VERIFICATION_IN_PROGRESS freshness=4/4 reader=HARDENED active_bindings=7/7 specialized=HARDENED production_authorized=false')
elif D['status']=='TECHNICALLY_VERIFIED_READ_ONLY_CANDIDATE':
    req(D['read_only_route_technically_verified'] is True,'VERIFIED_FLAG')
    req(D['exact_head_ci']['canonical_workflows_passed']==D['exact_head_ci']['canonical_workflows_total']==3,'CI_3_OF_3')
    for k in ('lf_contract_check','validate_lf_packs','lf_bootstrap_reproducibility_probe'): req(D['exact_head_ci'][k]=='PASS','CI_'+k.upper())
    req(D['closure_boundary']=='TECHNICAL_READ_ONLY_ONLY','VERIFIED_BOUNDARY')
    print('LEARNING_READONLY_TECHNICAL_CLOSURE=PASS verified=true ci=3/3 production_authorized=false')
else:
    raise SystemExit('FAIL_STATUS')
