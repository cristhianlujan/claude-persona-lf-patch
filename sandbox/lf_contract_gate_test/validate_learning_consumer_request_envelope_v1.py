#!/usr/bin/env python3
from __future__ import annotations
from learning_consumer_request_envelope_v1 import build_envelope

def must_fail(fn):
    try: fn()
    except ValueError: return
    raise SystemExit('FAIL expected ValueError')

def good_context():
    return {
      'schema':'LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2','mode':'READ_ONLY','selector':'DETERMINISTIC_EXACT_ID',
      'llm_calls':0,'round_trips':0,'tool_calls':0,'consumer_id':'PERFIL-PRODUCT-DIRECTOR-LF','capability_id':'NEGOCIACION_DEUDA',
      'max_context_bytes':6000,'context_bytes':500,'selected_count':1,
      'selected':[{'kb_id':'kb-1','summary':'grounded','evidence_ref':'public.lf_knowledge_base/kb-1'}],'fallback':None
    }

def main() -> int:
    ctx=good_context()
    out=build_envelope(task_intent='definir alcance de negociación',explicit_constraints=['no inventar descuento','no auto aprobar'],context_pack=ctx,binding_id='BIND-LF-PD-NEGOCIACION-DEUDA-v2')
    assert out['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
    assert out['binding_id']=='BIND-LF-PD-NEGOCIACION-DEUDA-v2'
    assert out['selected_evidence_refs']==['public.lf_knowledge_base/kb-1']
    assert out['writes_allowed'] is False and out['automatic_promotion'] is False
    assert len(out['context_pack_sha256'])==64
    must_fail(lambda: build_envelope(task_intent='',explicit_constraints=[],context_pack=ctx,binding_id='B'))
    must_fail(lambda: build_envelope(task_intent='x',explicit_constraints=[],context_pack=ctx,binding_id=''))
    bad=dict(ctx); bad['mode']='WRITE'; must_fail(lambda: build_envelope(task_intent='x',explicit_constraints=[],context_pack=bad,binding_id='B'))
    bad=dict(ctx); bad['llm_calls']=1; must_fail(lambda: build_envelope(task_intent='x',explicit_constraints=[],context_pack=bad,binding_id='B'))
    bad=dict(ctx); bad['context_bytes']=7000; must_fail(lambda: build_envelope(task_intent='x',explicit_constraints=[],context_pack=bad,binding_id='B'))
    print('LEARNING_CONSUMER_REQUEST_ENVELOPE=PASS authority=bounded read_only=1 writes=0 auto_promotion=0 negative=5')
    return 0
if __name__=='__main__': raise SystemExit(main())
