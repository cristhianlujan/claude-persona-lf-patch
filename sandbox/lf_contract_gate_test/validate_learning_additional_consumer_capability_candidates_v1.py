#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'learning_additional_consumer_capability_candidates_v1.json'

def main():
    d=json.loads(P.read_text(encoding='utf-8'))
    assert d['schema']=='LF_LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_CANDIDATES_V1'
    assert d['mode']=='READ_ONLY'
    assert d['selection_mode']=='DETERMINISTIC_SOURCE_SCOPE_MATCH_ONLY'
    assert len(d['source_refs'])==2 and all(len(x['sha'])==40 for x in d['source_refs'])
    rows={r['consumer_id']:r for r in d['candidates']}
    assert set(rows)=={'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'}
    for r in rows.values():
        assert set(r['candidate_capabilities'])=={'DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
        assert len(r['source_scope_evidence'])>=5
        assert r['state']=='READY_FOR_BINDING_REVIEW'
        assert r['exact_binding_created'] is False
        assert 'PRODUCT_DIRECTION_AUTHORIZED_CURRENT' in r['required_prerequisites']
        assert set(r['must_not_invoke_without']).issubset(set(r['required_prerequisites']))
    cx=rows['PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531']
    ux=rows['PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531']
    assert 'EXACT_CLAIM_AUTHORITY_CURRENT' in cx['required_prerequisites']
    assert 'payment_status_claim_boundary' in cx['source_scope_evidence']
    assert 'listing_selection_experience' in ux['source_scope_evidence']
    assert d['selector_llm_calls']==0 and d['selector_round_trips']==0 and d['semantic_search'] is False
    assert d['runtime_enabled'] is False and d['automatic_binding'] is False and d['automatic_impact'] is False and d['production_authorized'] is False
    print('LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_CANDIDATES=PASS consumers=2 candidates=4 exact_bindings=0 deterministic=true llm=0 round_trips=0 semantic_search=false runtime_enabled=false')
if __name__=='__main__': main()
