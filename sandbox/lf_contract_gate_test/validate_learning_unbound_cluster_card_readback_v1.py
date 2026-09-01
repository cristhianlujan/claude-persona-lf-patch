#!/usr/bin/env python3
import json,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parent
P=R/'learning_unbound_cluster_card_readback_v1.json'

def main():
    d=json.loads(P.read_text(encoding='utf-8'))
    assert d['schema']=='LF_LEARNING_UNBOUND_CLUSTER_CARD_READBACK_V1'
    assert d['mode']=='READ_ONLY'
    assert d['exact_card_matches']==0
    assert d['keyword_candidate_matches']==0
    assert d['semantic_search_used'] is False
    rows={r['cluster_code']:r for r in d['clusters']}
    assert set(rows)=={'REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS','BENCHMARK_PERIFERICO'}
    for code in ('REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS'):
        r=rows[code]
        assert r['canonical_bridge_policy']=='EXISTING_CARD_CHECK_REQUIRED'
        assert r['existing_exact_card_observed'] is False
        assert r['keyword_candidate_observed'] is False
        assert r['next_state']=='READY_FOR_BINDING_ONLY'
        assert r['automatic_card_creation'] is False
    b=rows['BENCHMARK_PERIFERICO']
    assert b['canonical_bridge_policy']=='NO_CARD' and b['next_state']=='NO_CARD'
    assert b['existing_exact_card_observed'] is False and b['keyword_candidate_observed'] is False
    assert b['automatic_card_creation'] is False
    assert d['automatic_binding'] is False and d['automatic_impact'] is False and d['production_authorized'] is False
    p=subprocess.run([sys.executable,str(R/'validate_learning_source_snapshot_freshness_guard_v1.py')],capture_output=True,text=True)
    if p.stdout: print(p.stdout.strip())
    if p.returncode:
        if p.stderr: sys.stderr.write(p.stderr)
        raise SystemExit(p.returncode)
    print('LEARNING_UNBOUND_CLUSTER_CARD_READBACK=PASS historical_matches=0 ready_for_binding_only=2 no_card=1 fresh_readback_required_before_new_binding_or_card=true')
if __name__=='__main__': main()
