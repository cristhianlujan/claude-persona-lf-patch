import unittest
from profile_rrf_candidate_v1 import reciprocal_rank_fusion


def sample():
    return [dict(source_id='s1',origin_id='o1',subject_sha256='a'*64,receipt_ref='receipt://1',source_revision='v1',independently_observed=True,ranked_items=['A','B']),
            dict(source_id='s2',origin_id='o2',subject_sha256='a'*64,receipt_ref='receipt://2',source_revision='v2',independently_observed=True,ranked_items=['B','A'])]

class Checks(unittest.TestCase):
    def test_fusion(self):
        r=reciprocal_rank_fusion(sample())
        self.assertEqual(r['status'],'FUSED_RANKING_NOT_ADMISSION')
        self.assertEqual([x['item'] for x in r['ranking']],['A','B'])
        self.assertEqual(len(r['ranking'][0]['supporting_sources']),2)
        self.assertFalse(r['cutover_eligible'])
    def test_duplicate_origin(self):
        x=sample();x[1]['origin_id']='o1'
        self.assertEqual(reciprocal_rank_fusion(x)['reason'],'SOURCE_REUSE_OR_DOUBLE_COUNT')
    def test_stale_subject(self):
        x=sample();x[1]['subject_sha256']='b'*64
        self.assertEqual(reciprocal_rank_fusion(x)['reason'],'SUBJECT_CURRENTNESS_MISMATCH')
    def test_missing_receipt(self):
        x=sample();x[0]['receipt_ref']=''
        self.assertEqual(reciprocal_rank_fusion(x)['reason'],'BOUND_SOURCE_IDENTITY_REQUIRED')
    def test_not_independent(self):
        x=sample();x[0]['independently_observed']=False
        self.assertEqual(reciprocal_rank_fusion(x)['reason'],'SOURCE_OBSERVATION_NOT_VERIFIED')
    def test_one_source(self):
        self.assertEqual(reciprocal_rank_fusion(sample()[:1])['status'],'NOT_APPLICABLE')
    def test_duplicate_item(self):
        x=sample();x[0]['ranked_items']=['A','A']
        self.assertEqual(reciprocal_rank_fusion(x)['reason'],'RANKED_SOURCE_ITEMS_INVALID')
    def test_invalid_k(self):
        self.assertEqual(reciprocal_rank_fusion(sample(),True)['reason'],'RRF_K_INVALID')

if __name__ == '__main__':unittest.main()
