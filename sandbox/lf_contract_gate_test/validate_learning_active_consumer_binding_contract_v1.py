#!/usr/bin/env python3
import json,yaml
from pathlib import Path
R=Path(__file__).resolve().parent
PD=yaml.safe_load((R/'learning_consumer_bindings_v2.yaml').read_text())
UI=yaml.safe_load((R/'ui_architect_learning_consumer_bindings_v1.yaml').read_text())
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text())
REQ={'consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','version','source_learning_ids','champion_id','challenger_id','provenance'}
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
rows=PD['bindings']+UI['bindings']
req(len(rows)==7,'BINDING_COUNT')
keys=set(); total_refs=0
for i,b in enumerate(rows):
    req(REQ<=set(b),f'FIELDS_{i}')
    key=(b['consumer_id'],b['capability_id']); req(key not in keys,f'DUPLICATE_{i}'); keys.add(key)
    req(b['consumer_type']=='PROFILE' and b['router_action']=='EJECUCION_PERFIL_LF',f'ROUTER_{i}')
    req(b['invoke_when'] and b['must_not_invoke_when'],f'ROUTING_{i}')
    req(b['input_contract'].get('required') and b['input_contract'].get('authority'),f'INPUT_{i}')
    req(b['minimum_context'] and b['selected_evidence_refs'],f'CONTEXT_{i}')
    req(b['fallback']=='NO_COMPETITIVE_CONTEXT',f'FALLBACK_{i}')
    req(b['context_budget']['selection']=='DETERMINISTIC_FIRST' and b['context_budget']['max_bytes']>0,f'BUDGET_{i}')
    req(b['lifecycle_state']=='READY_FOR_BINDING',f'LIFECYCLE_{i}')
    req(set(b['source_learning_ids'])=={x.rsplit('/',1)[-1] for x in b['selected_evidence_refs']},f'PROVENANCE_PARITY_{i}')
    req(b['champion_id'] and b['challenger_id'],f'BENCHMARK_IDS_{i}')
    req(b['provenance'].get('production_authorized') is False,f'NO_PRODUCTION_{i}')
    total_refs+=len(b['source_learning_ids'])
dyn={(x['consumer_id'],x['capability_id']) for x in D['bindings']}
req(keys==dyn,'DYNAMIC_SELECTOR_PARITY')
req(total_refs==17,'SELECTED_REF_COUNT')
print('LEARNING_ACTIVE_CONSUMER_BINDING_CONTRACT=PASS bindings=7/7 mandatory_fields=7/7 selector_parity=7/7 selected_refs=17/17')
