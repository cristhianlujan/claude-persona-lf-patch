import importlib.util
from pathlib import Path
import unittest
p=Path(__file__).with_name('edge_pg01_oidc_one_use_gate_v1.py')
s=importlib.util.spec_from_file_location('oneuse',p)
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
SHA='a'*40;DIGEST='b'*64;OP='RUN-123'
def receipt():
    return dict(schema_version=m.SCHEMA,decision='CONSUMED',ready=True,authority_layer='INDEPENDENT_ATOMIC_CONSUMER',target_slug=m.SLUG,main_sha=SHA,source_sha256=DIGEST,consumer_execution_id=OP,max_uses=1,uses_count=1,active=False)
class Tests(unittest.TestCase):
    def check(self,r,**kw):return m.qualify(r,main_sha=kw.get('main_sha',SHA),source_sha256=kw.get('source_sha256',DIGEST),operation_id=kw.get('operation_id',OP))
    def test_valid_shape_is_only_candidate(self):self.assertIsNone(self.check(receipt()))
    def test_missing(self):self.assertEqual(self.check(None),'CONSUMPTION_RECEIPT_MISSING')
    def test_self_attested(self):
        r=receipt();r['authority_layer']='GITHUB_ACTIONS';self.assertEqual(self.check(r),'CONSUMPTION_AUTHORITY_UNVERIFIED')
    def test_pending(self):
        r=receipt();r['decision']='READY';self.assertEqual(self.check(r),'CONSUMPTION_AUTHORITY_UNVERIFIED')
    def test_cross_function(self):
        r=receipt();r['target_slug']='other';self.assertEqual(self.check(r),'CONSUMPTION_CONTEXT_MISMATCH')
    def test_cross_commit(self):self.assertEqual(self.check(receipt(),main_sha='c'*40),'CONSUMPTION_CONTEXT_MISMATCH')
    def test_cross_source(self):self.assertEqual(self.check(receipt(),source_sha256='d'*64),'CONSUMPTION_CONTEXT_MISMATCH')
    def test_cross_operation(self):self.assertEqual(self.check(receipt(),operation_id='RUN-124'),'CONSUMPTION_CONTEXT_MISMATCH')
    def test_not_consumed(self):
        r=receipt();r['uses_count']=0;self.assertEqual(self.check(r),'CONSUMPTION_NOT_EXHAUSTED')
    def test_multiple_uses(self):
        r=receipt();r['max_uses']=2;self.assertEqual(self.check(r),'CONSUMPTION_NOT_EXHAUSTED')
    def test_still_active(self):
        r=receipt();r['active']=True;self.assertEqual(self.check(r),'CONSUMPTION_NOT_EXHAUSTED')
if __name__=='__main__':unittest.main()
