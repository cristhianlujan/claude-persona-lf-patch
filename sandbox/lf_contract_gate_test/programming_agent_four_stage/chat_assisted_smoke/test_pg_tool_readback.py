import unittest
from pg_tool_readback import PLAN, ReadbackError, project_tool_row
class Tests(unittest.TestCase):
 def setUp(self): self.r={'plan_code':PLAN,'unit_code':'PG-00','checkpoint_code':'PG-00_C1','status':'PENDING','required':True,'updated_at':'2026-10-28 16:13:20+00'}
 def call(self): return project_tool_row(self.r,unit='PG-00',checkpoint='PG-00_C1')
 def test_pending(self): self.assertFalse(self.call()['worker_dispatch_authorized'])
 def test_done_not_authority(self):
  self.r['status']='DONE'; self.assertFalse(self.call()['transition_authorized'])
 def test_plan_mismatch(self):
  self.r['plan_code']='OTHER'
  with self.assertRaises(ReadbackError): self.call()
 def test_checkpoint_mismatch(self):
  self.r['checkpoint_code']='OTHER'
  with self.assertRaises(ReadbackError): self.call()
 def test_invalid_status(self):
  self.r['status']='BYPASS'
  with self.assertRaises(ReadbackError): self.call()
 def test_required_type(self):
  self.r['required']='true'
  with self.assertRaises(ReadbackError): self.call()
 def test_missing_timestamp(self):
  del self.r['updated_at']
  with self.assertRaises(ReadbackError): self.call()
 def test_invalid_row(self):
  with self.assertRaises(ReadbackError): project_tool_row(None,unit='PG-00',checkpoint='PG-00_C1')
if __name__=='__main__': unittest.main()
