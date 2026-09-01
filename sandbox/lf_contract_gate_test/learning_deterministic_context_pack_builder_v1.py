import json
from pathlib import Path
import yaml
from learning_dynamic_context_selector_clean_v1 import select_context, SelectionError

R=Path(__file__).resolve().parent
_BINDING_FILES={
    'PERFIL-PRODUCT-DIRECTOR-LF':'learning_consumer_bindings_v2.yaml',
    'PERFIL-UI-ARCHITECT':'ui_architect_learning_consumer_bindings_v1.yaml',
}

class ContextPackError(ValueError):
    pass

def _binding(consumer_id,capability_id):
    filename=_BINDING_FILES.get(consumer_id)
    if not filename:
        raise ContextPackError('EXACT_CONSUMER_BINDING_SOURCE_REQUIRED')
    data=yaml.safe_load((R/filename).read_text(encoding='utf-8'))
    row=next((x for x in data.get('bindings',[]) if x.get('consumer_id')==consumer_id and x.get('capability_id')==capability_id),None)
    if not row:
        raise ContextPackError('EXACT_BINDING_REQUIRED')
    if row.get('fallback')!='NO_COMPETITIVE_CONTEXT' or row.get('context_budget',{}).get('selection')!='DETERMINISTIC_FIRST':
        raise ContextPackError('BINDING_INVARIANTS_REQUIRED')
    return row

def _empty(consumer_id,capability_id,reason):
    return {
        'schema':'LF_LEARNING_DETERMINISTIC_CONTEXT_PACK_V1','mode':'READ_ONLY',
        'consumer_id':consumer_id,'capability_id':capability_id,
        'facts':[],'evidence_refs':[],'constraints':[],'policy_refs':[],
        'selected_learning_ids':[],'fallback':'NO_COMPETITIVE_CONTEXT','fallback_reason':reason,
        'llm_calls':0,'round_trips':0,'writes':0,'semantic_search':False,'recursive_expansion':False,
        'context_bytes':0,'context_budget_bytes':0,
    }

def build_context_pack(kb_rows,classification_events,consumer_id,capability_id,*,task_intent='',explicit_constraints=(),prerequisites=(),product_direction_ref=None):
    if not isinstance(explicit_constraints,(list,tuple)):
        raise ContextPackError('EXPLICIT_CONSTRAINTS_COLLECTION_REQUIRED')
    try:
        b=_binding(consumer_id,capability_id)
    except ContextPackError:
        return _empty(consumer_id,capability_id,'EXACT_BINDING_REQUIRED')
    selection=select_context(kb_rows,classification_events,consumer_id,capability_id,prerequisites)
    if selection.get('fallback'):
        out=_empty(consumer_id,capability_id,selection.get('nonbinding_reason') or selection.get('blocked_by_prerequisite') or 'NO_ELIGIBLE_EVIDENCE')
        out['context_budget_bytes']=int(b['context_budget']['max_bytes'])
        return out
    if consumer_id=='PERFIL-UI-ARCHITECT' and not product_direction_ref:
        out=_empty(consumer_id,capability_id,'PRODUCT_DIRECTION_REF_REQUIRED')
        out['context_budget_bytes']=int(b['context_budget']['max_bytes'])
        return out
    constraints=[]
    for x in explicit_constraints:
        if isinstance(x,str) and x and x not in constraints: constraints.append(x)
    for x in b.get('must_not_invoke_when',[]):
        token=f'MUST_NOT_INVOKE:{x}'
        if token not in constraints: constraints.append(token)
    authority=b.get('input_contract',{}).get('authority')
    if authority: constraints.append(f'AUTHORITY:{authority}')
    policy_refs=[b['policy_capsule_ref']] if b.get('policy_capsule_ref') else []
    required=b.get('minimum_context',[])
    selected=list(selection['selected'])
    budget=int(b['context_budget']['max_bytes'])
    while True:
        facts=[{'kb_id':x['kb_id'],'topic':x.get('topic'),'summary':x.get('summary'),'source_url':x.get('source_url')} for x in selected]
        pack={
            'schema':'LF_LEARNING_DETERMINISTIC_CONTEXT_PACK_V1','mode':'READ_ONLY',
            'consumer_id':consumer_id,'capability_id':capability_id,'binding_id':b.get('binding_id'),
            'task_intent':task_intent,'product_direction_ref':product_direction_ref,
            'required_context_keys':required,'facts':facts,
            'evidence_refs':[x['evidence_ref'] for x in selected],
            'constraints':constraints,'policy_refs':policy_refs,
            'selected_learning_ids':[x['kb_id'] for x in selected],
            'fallback':None,'llm_calls':0,'round_trips':0,'writes':0,'semantic_search':False,'recursive_expansion':False,
            'context_budget_bytes':budget,
        }
        measured=dict(pack); measured.pop('context_bytes',None)
        size=len(json.dumps(measured,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())
        if size<=budget:
            pack['context_bytes']=size
            return pack
        if not selected:
            out=_empty(consumer_id,capability_id,'CONTEXT_BUDGET_EXCEEDED_BY_REQUIRED_CONSTRAINTS')
            out['context_budget_bytes']=budget
            return out
        selected.pop()
