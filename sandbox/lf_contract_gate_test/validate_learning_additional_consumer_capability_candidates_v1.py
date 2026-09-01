#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'learning_additional_consumer_capability_candidates_v1.json'

def main():
    d=json.loads(P.read_text(encoding='utf-8'))
    assert d['schema']=='LF_LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_CANDIDATES_V1'
    assert d['mode']=='READ_ONLY'
    assert len(d['source_refs'])==2 and all(len(x['sha'])==40 for x in d['source_refs'])
    rows={r['consumer_id']:r for r in d['candidates']}
    assert set(rows)=={'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'}
    for r in rows.values():
        assert set(r['candidate_capabilities'])=={'DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
        assert r['state']=='READY_FOR_BINDING_REVIEW'
        assert r['exact_binding_created'] is False
        assert 'PRODUCT_DIRECTION_AUTHORIZED_CURRENT' in r['required_prerequisites']
    assert 'EXACT_CLAIM_AUTHORITY_CURRENT' in rows['PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531']['required_prerequisites']
    assert d['runtime_enabled'] is False and d['automatic_binding'] is False and d['automatic_impact'] is False and d['production_authorized'] is False
    print('LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_CANDIDATES=PASS consumers=2 candidates=4 exact_bindings=0 runtime_enabled=false')
if __name__=='__main__': main()
