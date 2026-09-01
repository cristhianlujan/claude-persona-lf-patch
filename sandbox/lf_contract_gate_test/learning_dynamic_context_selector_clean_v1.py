import json
from pathlib import Path

CATALOG = Path(__file__).with_name('learning_consumer_dynamic_cluster_bindings_v1.json')

class SelectionError(ValueError):
    pass

def _catalog():
    data=json.loads(CATALOG.read_text(encoding='utf-8'))
    if data.get('mode')!='READ_ONLY': raise SelectionError('READ_ONLY_REQUIRED')
    bounded=data.get('boundedness',{})
    if bounded.get('llm_calls_for_selection')!=0 or bounded.get('round_trips_for_selection')!=0 or bounded.get('reader_writes')!=0 or bounded.get('semantic_search') is not False:
        raise SelectionError('READ_ONLY_INVARIANTS_REQUIRED')
    return data

def _fallback(consumer_id, capability_id, reason):
    return {'mode':'READ_ONLY','consumer_id':consumer_id,'capability_id':capability_id,'selected':[],'fallback':'NO_COMPETITIVE_CONTEXT','llm_calls':0,'round_trips':0,'writes':0,'semantic_search':False,'nonbinding_reason':reason}

def _event_order(e):
    try: return int(e.get('event_id',e.get('id',0)))
    except (TypeError,ValueError): return None

def _quality_score(r):
    try: return float(r.get('quality_score') or 0)
    except (TypeError,ValueError): return 0.0

def select_context(kb_rows, classification_events, consumer_id, capability_id, prerequisites=()):
    if not isinstance(kb_rows,(list,tuple)) or not isinstance(classification_events,(list,tuple)):
        raise SelectionError('INPUT_COLLECTIONS_REQUIRED')
    if not isinstance(prerequisites,(list,tuple,set,frozenset)):
        raise SelectionError('PREREQUISITES_COLLECTION_REQUIRED')
    c=_catalog(); b=next((x for x in c['bindings'] if x['consumer_id']==consumer_id and x['capability_id']==capability_id),None)
    if not b:
        nonbinding=next((x for x in c.get('explicit_nonbindings',[]) if x['consumer_id']==consumer_id),None)
        if nonbinding:
            return _fallback(consumer_id,capability_id,nonbinding['reason'])
        raise SelectionError('EXACT_BINDING_REQUIRED')
    if b.get('prerequisite') and b['prerequisite'] not in set(prerequisites):
        out=_fallback(consumer_id,capability_id,'PREREQUISITE_REQUIRED')
        out['blocked_by_prerequisite']=b['prerequisite']
        return out
    allowed=set(b['cluster_codes']); receipts={}
    for e in classification_events:
        if not isinstance(e,dict): continue
        p=e.get('payload',{})
        if not isinstance(p,dict): continue
        order=_event_order(e)
        kid=p.get('kb_id')
        if order is None or not isinstance(kid,(str,int)) or str(kid)=='': continue
        kid=str(kid); clusters={x for x in str(p.get('cluster_code','')).split('|') if x}
        if p.get('taxonomy_version')==c['taxonomy_version'] and p.get('lifecycle') in c['eligibility']['classification_lifecycle'] and p.get('eligibility') in c['eligibility']['classification_eligibility'] and clusters & allowed:
            receipts[kid]=max(order,receipts.get(kid,0))
    rows=[]
    for r in kb_rows:
        if not isinstance(r,dict): continue
        kid=str(r.get('kb_id',''))
        if not kid: continue
        if kid in receipts and r.get('kb_category')=='COMPETENCIA' and r.get('grounding_status')=='GROUNDED' and r.get('consumer_ready') is True:
            rows.append((-_quality_score(r), -receipts[kid], kid, r))
    rows.sort(key=lambda x:(x[0],x[1],x[2]))
    out=[]; budget=int(b['context_budget_bytes']); max_refs=int(c['boundedness']['max_evidence_refs_per_capability'])
    for _,_,kid,r in rows:
        item={'kb_id':kid,'topic':r.get('topic'),'summary':r.get('summary'),'source_url':r.get('source_url'),'evidence_ref':f'public.lf_knowledge_base/{kid}'}
        trial=out+[item]
        if len(json.dumps(trial,ensure_ascii=False,sort_keys=True).encode())<=budget: out=trial
        if len(out)>=max_refs: break
    return {'mode':'READ_ONLY','consumer_id':consumer_id,'capability_id':capability_id,'selected':out,'fallback':None if out else 'NO_COMPETITIVE_CONTEXT','llm_calls':0,'round_trips':0,'writes':0,'semantic_search':False,'context_bytes':len(json.dumps(out,ensure_ascii=False,sort_keys=True).encode()),'context_budget_bytes':budget}
