#!/usr/bin/env python3
import subprocess,sys
from pathlib import Path
from learning_dynamic_context_selector_clean_v1 import select_context, SelectionError
R=Path(__file__).resolve().parent

def ev(kid, cluster, eid=1, lifecycle='ANALIZADO', eligibility='PASS'):
    return {'event_id':eid,'payload':{'kb_id':kid,'cluster_code':cluster,'taxonomy_version':'LF_LEARNING_CLUSTER_V1','lifecycle':lifecycle,'eligibility':eligibility}}

def kb(kid, **kw):
    x={'kb_id':kid,'kb_category':'COMPETENCIA','grounding_status':'GROUNDED','consumer_ready':True,'quality_score':8,'topic':'t','summary':'s','source_url':'https://example.invalid'}; x.update(kw); return x

def assert_reader_invariants(result):
    assert result['llm_calls']==0
    assert result['round_trips']==0
    assert result['writes']==0
    assert result['semantic_search'] is False

def run(script):
    p=subprocess.run([sys.executable,str(R/script)],capture_output=True,text=True)
    if p.stdout: print(p.stdout.strip())
    if p.returncode:
        if p.stderr: sys.stderr.write(p.stderr)
        raise SystemExit(p.returncode)

def main():
    r=select_context([kb('a'),kb('b',grounding_status='UNGROUNDED'),kb('c',consumer_ready=False)],[ev('a','NEGOCIACION_DEUDA'),ev('b','NEGOCIACION_DEUDA'),ev('c','NEGOCIACION_DEUDA')],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
    assert [x['kb_id'] for x in r['selected']]==['a']; assert_reader_invariants(r); assert r['context_bytes']<=r['context_budget_bytes']
    f=select_context([],[],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA'); assert f['fallback']=='NO_COMPETITIVE_CONTEXT'; assert_reader_invariants(f)
    u=select_context([kb('a')],[ev('a','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE'); assert u['selected']==[] and u['blocked_by_prerequisite']=='PRODUCT_DIRECTION_AUTHORIZED_CURRENT'; assert_reader_invariants(u)
    u2=select_context([kb('a')],[ev('a','AUTOGESTION_DIGITAL')],'PERFIL-UI-ARCHITECT','DIGITAL_SELF_SERVICE',['PRODUCT_DIRECTION_AUTHORIZED_CURRENT']); assert len(u2['selected'])==1; assert_reader_invariants(u2)
    for i,cluster in enumerate(('REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS','BENCHMARK_PERIFERICO'),start=10):
        x=select_context([kb(f'u{i}')],[ev(f'u{i}',cluster,i)],'PERFIL-PRODUCT-DIRECTOR-LF','NEGOCIACION_DEUDA')
        assert x['selected']==[] and x['fallback']=='NO_COMPETITIVE_CONTEXT'; assert_reader_invariants(x)
    known_nonbindings={
      'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT':'NO_EXACT_COMPETITIVE_CAPABILITY',
      'ACT-0051':'UPSTREAM_PRODUCT_AND_UI_AUTHORITY_REQUIRED',
      'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531':'READY_FOR_BINDING_REVIEW_ONLY_RUNTIME_DISABLED',
      'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531':'READY_FOR_BINDING_REVIEW_ONLY_RUNTIME_DISABLED',
    }
    for consumer,reason in known_nonbindings.items():
        x=select_context([kb('z')],[ev('z','AUTOGESTION_DIGITAL',99)],consumer,'DIGITAL_SELF_SERVICE',['PRODUCT_DIRECTION_AUTHORIZED_CURRENT','UI_ARCHITECTURE_AUTHORIZED_CURRENT','EXACT_CLAIM_AUTHORITY_CURRENT'])
        assert x['selected']==[] and x['fallback']=='NO_COMPETITIVE_CONTEXT' and x['nonbinding_reason']==reason; assert_reader_invariants(x)
    try: select_context([],[],'UNKNOWN','UNKNOWN')
    except SelectionError as e: assert str(e)=='EXACT_BINDING_REQUIRED'
    else: raise AssertionError('must fail closed')
    print('PASS learning_dynamic_context_selector_clean_v1 writes=0 semantic_search=false llm_calls=0 round_trips=0 unbound_clusters_fail_closed=3/3 explicit_nonbindings_fail_closed=4/4 unknown_binding_error=PASS')
    run('validate_learning_dynamic_exact_join_contract_v1.py')
    run('validate_learning_dynamic_selector_robustness_v1.py')
    run('validate_learning_dynamic_selector_stability_v1.py')
    run('validate_learning_dynamic_selector_boundedness_v1.py')
if __name__=='__main__': main()
