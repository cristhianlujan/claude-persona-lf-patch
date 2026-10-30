from pg00_c3_source_verify_candidate_v1 import verify_release

def test_untrusted_claim_blocks():
    result = verify_release({'found': True}, lambda *_: None)
    assert result['verified'] is False and result['decision'] == 'BLOCK'

if __name__ == '__main__':
    test_untrusted_claim_blocks()
    print('PG00_C3_TRUST_BOUNDARY_PASS')
