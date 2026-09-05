#!/usr/bin/env python3
import copy,json
from pathlib import Path
R=Path(__file__).resolve().parent
B0=json.loads((R/'learning_additional_consumer_binding_candidates_v1.json').read_text())
C0=json.loads((R/'learning_additional_consumer_context_pack_candidates_v1.json').read_text())
A0=json.loads((R/'learning_additional_consumer_applicability_v1.json').read_text())
def safe(B,C,A):
    if B.get('active_exact_binding_count')!=0 or B.get('selector_context_delivery_enabled') is not False:return False
    if C.get('automatic_binding') is not False or C.get('automatic_impact') is not False or C.get('production_authorized') is not False:return False
    apps={x['consumer_id']:x for x in A['consumers']}
    for b in B['bindings']:
        a=apps.get(b['consumer_id'],{})
        if b['lifecycle_state']!='READY_FOR_BINDING' or b['fallback']!='NO_COMPETITIVE_CONTEXT':return False
        if b['selected_evidence_refs'] or b['source_learning_ids'] or b['token/context_budget']['learning_context_max_bytes']!=0:return False
        if b['provenance']['exact_binding_created'] is not False:return False
        if a.get('runtime_enabled') is not False or a.get('exact_capability_binding_observed') is not False:return False
    for p in C['packs']:
        if p['binding_state']!='READY_FOR_BINDING' or p['delivery_enabled'] is not False:return False
        if p['selected_evidence_refs'] or p['source_learning_ids'] or p['context_bytes']!=0 or p['context_budget_bytes']!=0:return False
    return True
def mutate(which,fn):
    B,C,A=copy.deepcopy(B0),copy.deepcopy(C0),copy.deepcopy(A0); fn(B,C,A); return safe(B,C,A)
cases=[
 ('binding_evidence_injected',lambda B,C,A:B['bindings'][0]['selected_evidence_refs'].append('x')),
 ('learning_id_injected',lambda B,C,A:B['bindings'][0]['source_learning_ids'].append('x')),
 ('budget_opened',lambda B,C,A:B['bindings'][0]['token/context_budget'].__setitem__('learning_context_max_bytes',1)),
 ('binding_flag_true',lambda B,C,A:B['bindings'][0]['provenance'].__setitem__('exact_binding_created',True)),
 ('lifecycle_promoted',lambda B,C,A:B['bindings'][0].__setitem__('lifecycle_state','ACTIVE')),
 ('active_count_nonzero',lambda B,C,A:B.__setitem__('active_exact_binding_count',1)),
 ('selector_delivery_true',lambda B,C,A:B.__setitem__('selector_context_delivery_enabled',True)),
 ('pack_evidence_injected',lambda B,C,A:C['packs'][0]['selected_evidence_refs'].append('x')),
 ('pack_bytes_nonzero',lambda B,C,A:C['packs'][0].__setitem__('context_bytes',1)),
 ('pack_delivery_true',lambda B,C,A:C['packs'][0].__setitem__('delivery_enabled',True)),
 ('runtime_enabled',lambda B,C,A:A['consumers'][0].__setitem__('runtime_enabled',True)),
 ('exact_binding_observed',lambda B,C,A:A['consumers'][0].__setitem__('exact_capability_binding_observed',True)),
]
if not safe(B0,C0,A0): raise SystemExit('FAIL_BASELINE_NOT_SAFE')
failed=[]
for name,fn in cases:
    if mutate(name,fn): failed.append(name)
if failed: raise SystemExit('FAIL_NEGATIVES_NOT_BLOCKED:'+','.join(failed))
print('LEARNING_SPECIALIZED_CONSUMER_ACTIVATION_NEGATIVE=PASS cases=12/12 all_unsafe_mutations_blocked=true')
