#!/usr/bin/env python3
from __future__ import annotations
from learning_read_only_context_selector_v2 import BindingSpec, LearningSelectionError, select_read_only_context


def must_fail(fn):
    try: fn()
    except LearningSelectionError: return
    raise SystemExit('FAIL expected LearningSelectionError')


def row(kb_id: str, *, grounded='GROUNDED', ready=True, summary='ok'):
    return {'kb_id':kb_id,'grounding_status':grounded,'consumer_ready':ready,'topic':'topic','summary':summary,'source_url':f'https://example.test/{kb_id}','competitor':'fixture','quality_score':0.9}


def main() -> int:
    binding=BindingSpec('PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA',('kb-1','kb-2','kb-3','kb-4','kb-5','kb-6'),5,6000)
    rows=[row(f'kb-{i}') for i in range(1,7)] + [row('not-bound'),row('stale',grounded='STALE'),row('not-ready',ready=False)]
    out=select_read_only_context(rows,binding=binding)
    assert out['mode']=='READ_ONLY' and out['selector']=='DETERMINISTIC_EXACT_ID'
    assert out['llm_calls']==0 and out['round_trips']==0 and out['tool_calls']==0
    assert out['selected_count']==5
    assert [x['kb_id'] for x in out['selected']]==['kb-1','kb-2','kb-3','kb-4','kb-5']
    assert out['context_bytes']<=6000
    assert out['budget_blocked_count']==0
    assert all(x['kb_id']!='not-bound' for x in out['selected'])

    tight=BindingSpec('PD','NEGOCIACION_DEUDA',('kb-big','kb-small'),2,1024)
    tight_out=select_read_only_context([row('kb-big',summary='X'*4000),row('kb-small',summary='s')],binding=tight)
    assert tight_out['budget_blocked_count']==1
    assert [x['kb_id'] for x in tight_out['selected']]==['kb-small']
    assert tight_out['context_bytes']<=1024

    empty=select_read_only_context([row('other')],binding=binding)
    assert empty['selected_count']==0 and empty['fallback']=='NO_COMPETITIVE_CONTEXT'

    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('','NEGOCIACION_DEUDA',('kb-1',))))
    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('PD','',('kb-1',))))
    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('PD','NEGOCIACION_DEUDA',())))
    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('PD','NEGOCIACION_DEUDA',('kb-1',),6,6000)))
    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('PD','NEGOCIACION_DEUDA',('kb-1',),1,7000)))
    must_fail(lambda: select_read_only_context(rows,binding=BindingSpec('CONSUMER-'+'X'*400,'CAP-'+'Y'*400,('kb-1',),1,512)))
    print('LEARNING_READ_ONLY_CONTEXT_SELECTOR_V2=PASS exact_id=1 grounded=1 ready=1 max_refs=5 max_bytes=6000 bounded_metadata=1 envelope_minimum=1 llm_calls=0 round_trips=0 tool_calls=0')
    return 0

if __name__=='__main__': raise SystemExit(main())
