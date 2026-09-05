#!/usr/bin/env python3
import hashlib, json
from pathlib import Path
R=Path(__file__).resolve().parent
ROOT=R.parents[1]
G=json.loads((R/'learning_specialized_consumer_activation_guard_v1.json').read_text())
B=json.loads((R/'learning_additional_consumer_binding_candidates_v1.json').read_text())
C=json.loads((R/'learning_additional_consumer_context_pack_candidates_v1.json').read_text())
A=json.loads((R/'learning_additional_consumer_applicability_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
def git_blob_sha(text):
    raw=text.encode(); return hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
req(G['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_ACTIVATION_GUARD_V1','SCHEMA')
req(G['mode']=='READ_ONLY','MODE')
req(G['rule']=='NO_EXACT_BINDING_OR_CURRENT_RUNTIME_AUTHORITY_MEANS_ZERO_CONTEXT','RULE')
app={x['consumer_id']:x for x in A['consumers']}
contracts={x['consumer_id']:x for x in G['source_contracts']}
pairs={(x['consumer_id'],x['capability_id']) for x in B['bindings']}
req(pairs=={(x['consumer_id'],x['capability_id']) for x in C['packs']},'PAIR_PARITY')
for cid,s in contracts.items():
    p=ROOT/s['adapter_path']; req(p.exists(),'SOURCE_EXISTS_'+cid)
    txt=p.read_text(); req(git_blob_sha(txt)==s['adapter_blob_sha'],'SOURCE_SHA_'+cid)
    for tok in s['required_status_tokens']: req(tok in txt,'STATUS_'+cid+'_'+tok)
    req(s['required_runtime_boundary'] in txt,'RUNTIME_BOUNDARY_'+cid)
    req(s['required_receipt_boundary'] in txt,'RECEIPT_BOUNDARY_'+cid)
    req(cid in app,'APPLICABILITY_'+cid)
    req(app[cid]['runtime_enabled'] is False and app[cid]['production_enabled'] is False,'RUNTIME_DISABLED_'+cid)
    req(app[cid]['exact_capability_binding_observed'] is False,'NO_EXACT_BINDING_'+cid)
for i,b in enumerate(B['bindings']):
    req(b['lifecycle_state']=='READY_FOR_BINDING',f'BINDING_STATE_{i}')
    req(b['fallback']=='NO_COMPETITIVE_CONTEXT',f'FALLBACK_{i}')
    req(b['selected_evidence_refs']==[] and b['source_learning_ids']==[],f'ZERO_EVIDENCE_{i}')
    req(b['token/context_budget']['learning_context_max_bytes']==0,f'ZERO_BUDGET_{i}')
    req(b['provenance']['exact_binding_created'] is False,f'NO_BINDING_{i}')
for i,p in enumerate(C['packs']):
    req(p['binding_state']=='READY_FOR_BINDING',f'PACK_STATE_{i}')
    req(p['selected_evidence_refs']==[] and p['source_learning_ids']==[],f'PACK_ZERO_EVIDENCE_{i}')
    req(p['context_bytes']==0 and p['context_budget_bytes']==0,f'PACK_ZERO_BYTES_{i}')
    req(p['delivery_enabled'] is False and p['fallback']=='NO_COMPETITIVE_CONTEXT',f'PACK_NO_DELIVERY_{i}')
req(B['active_exact_binding_count']==0 and B['selector_context_delivery_enabled'] is False,'GLOBAL_NO_DELIVERY')
req(C['selector_llm_calls']==0 and C['selector_round_trips']==0 and C['reader_writes']==0,'ZERO_COST_SELECTOR')
req(G['behavioral_promotion_authorized'] is False and G['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_SPECIALIZED_CONSUMER_ACTIVATION_GUARD=PASS consumers=2 candidates=4 packs=4 exact_bindings=0 delivery=false source_sha=2/2')
