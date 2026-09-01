#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_readonly_technical_closure_v1.json').read_text())

def req(cond,msg):
    if not cond: raise SystemExit('FAIL_'+msg)

req(D['schema']=='LF_LEARNING_READONLY_TECHNICAL_CLOSURE_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['status']=='TECHNICALLY_VERIFIED_READ_ONLY_CANDIDATE','STATUS')
req(D['router']['asset']=='ACT-0001','ROUTER')
req(D['router']['estado_documental']=='VIGENTE','ROUTER_DOCUMENTAL')
req(D['router']['estado_operativo']=='ACTIVO','ROUTER_OPERATIVO')
req(D['router']['runtime_estado']=='RUNTIME_OPERATIVO','ROUTER_RUNTIME')
req(D['router']['impacto_automatico']=='BLOQUEADO','AUTO_IMPACT_BLOCK')
req(D['source_parity']['lf_migration_source_parity']=='PASS','LF_PARITY')
req(D['source_parity']['input_governance_migration_source_parity']=='PASS','IG_PARITY')
req(D['exact_head_ci']['canonical_workflows_passed']==D['exact_head_ci']['canonical_workflows_total']==3,'CI_3_OF_3')
for k in ('lf_contract_check','validate_lf_packs','lf_bootstrap_reproducibility_probe'):
    req(D['exact_head_ci'][k]=='PASS','CI_'+k.upper())
pd=D['product_director']; ui=D['ui_architect']; b=D['behavioral']
req(pd['exact_bindings']=='5/5' and pd['selected_learning_ids']=='13/13','PD_BINDING')
req(pd['routing_cases']=='50/50' and pd['routing_families']=='10x5','PD_BENCHMARK')
req(pd['fp']==0 and pd['fn']==0 and pd['precision']==pd['recall']==pd['specificity']==1.0,'PD_ROUTING')
req(pd['selector_llm_calls']==pd['selector_round_trips']==pd['reader_writes']==0 and pd['semantic_search'] is False,'PD_DETERMINISTIC')
req(ui['exact_bindings']=='2/2' and ui['selected_learning_ids']=='4/4','UI_BINDING')
req(ui['routing_cases']=='50/50' and ui['routing_families']=='10x5' and ui['adversarial_cases']=='12/12','UI_BENCHMARK')
req(ui['fp']==0 and ui['fn']==0 and ui['critical_false_positives']==0,'UI_ROUTING')
req(ui['challenger_context_bytes']<=ui['context_budget_bytes'] and ui['requirement_retention']=='5/5','UI_CONTEXT')
req(ui['selector_llm_calls']==ui['selector_round_trips']==ui['reader_writes']==0 and ui['semantic_search'] is False,'UI_DETERMINISTIC')
req(D['corpus']['eligible_classified']=='35/35','CORPUS_CLASSIFIED')
req(b['status']=='INSUFFICIENT_EVIDENCE' and b['behavioral_ab']=='NOT_EXECUTED','BEHAVIORAL_FAIL_CLOSED')
req(b['target_screen_declared']=='0/2' and b['exact_screen_receipt_missing']=='2/2','BEHAVIORAL_RECEIPT')
req(D['outcome']=='INSUFFICIENT_EVIDENCE','OUTCOME')
req(D['read_only_route_technically_verified'] is True,'READONLY_TECHNICAL')
for k in ('behavioral_promotion_authorized','automatic_promotion','production_authorized','merge_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
req(D['closure_boundary']=='TECHNICAL_READ_ONLY_ONLY','BOUNDARY')
print('LEARNING_READONLY_TECHNICAL_CLOSURE=PASS read_only_technical=true behavioral=INSUFFICIENT_EVIDENCE ci=3/3 production_authorized=false merge_authorized=false')
