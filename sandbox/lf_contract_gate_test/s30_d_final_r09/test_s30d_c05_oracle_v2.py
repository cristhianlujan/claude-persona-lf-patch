#!/usr/bin/env python3
import unittest,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
from c05_reliability_oracle_v2 import Store,Blocked
class T(unittest.TestCase):
 def setUp(self):
  self.s=Store(); self.op='ACT'; self.key='k'; self.req='a'*64; self.t=('STRATEGY','x',None,None); self.s.reserve(self.op,self.key,self.req,'e1',self.t)
 def test_same_key_same_hash_replays(self): self.assertEqual(self.s.reserve(self.op,self.key,self.req,'e2',self.t)['execution_id'],'e1')
 def test_same_key_different_hash_blocks(self):
  with self.assertRaisesRegex(Blocked,'DIFFERENT_REQUEST'): self.s.reserve(self.op,self.key,'b'*64,'e2',self.t)
 def test_same_hash_target_mismatch_blocks(self):
  with self.assertRaisesRegex(Blocked,'TARGET_MISMATCH'): self.s.reserve(self.op,self.key,self.req,'e2',('STRATEGY','y',None,None))
 def test_current_lease_contention(self):
  a=self.s.acquire(self.op,self.key,'A',0,30); b=self.s.acquire(self.op,self.key,'B',1,30); self.assertEqual(a['lease_fence'],1); self.assertEqual(b['code'],'LEASE_HELD')
 def test_expiry_takeover_increments_fence(self):
  a=self.s.acquire(self.op,self.key,'A',0,5); b=self.s.acquire(self.op,self.key,'B',6,5); self.assertGreater(b['lease_fence'],a['lease_fence'])
 def test_stale_fence_checkpoint_blocks(self):
  a=self.s.acquire(self.op,self.key,'A',0,5); b=self.s.acquire(self.op,self.key,'B',6,5)
  with self.assertRaisesRegex(Blocked,'STALE_OR_MISSING_LEASE_FENCE'): self.s.checkpoint(self.op,self.key,'A',a['lease_fence'],1,{'x':1},6)
 def test_checkpoint_persist_and_replay(self):
  a=self.s.acquire(self.op,self.key,'A',0,30); f=a['lease_fence']; self.assertEqual(self.s.checkpoint(self.op,self.key,'A',f,1,{'x':1},1)['result'],'CHECKPOINT_PERSISTED'); self.assertEqual(self.s.checkpoint(self.op,self.key,'A',f,1,{'x':1},2)['result'],'REPLAY_CHECKPOINT')
 def test_checkpoint_payload_mismatch_blocks(self):
  f=self.s.acquire(self.op,self.key,'A',0,30)['lease_fence']; self.s.checkpoint(self.op,self.key,'A',f,1,{'x':1},1)
  with self.assertRaisesRegex(Blocked,'DIFFERENT_PAYLOAD'): self.s.checkpoint(self.op,self.key,'A',f,1,{'x':2},2)
 def test_effect_first_reservation_permits_dispatch(self):
  f=self.s.acquire(self.op,self.key,'A',0,30)['lease_fence']; x=self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',1); self.assertTrue(x['dispatch_permitted'])
 def test_effect_response_loss_retry_requires_reconciliation(self):
  f=self.s.acquire(self.op,self.key,'A',0,30)['lease_fence']; self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',1); x=self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',2); self.assertEqual(x,{'result':'RECONCILIATION_REQUIRED','dispatch_permitted':False})
 def test_effect_success_replay_no_dispatch(self):
  f=self.s.acquire(self.op,self.key,'A',0,30)['lease_fence']; self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',1); self.s.succeed_effect(self.op,self.key,'A',f,'PAY',{'ref':'1'},2); x=self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',3); self.assertEqual(x['result'],'REPLAY_SUCCEEDED_EFFECT'); self.assertFalse(x['dispatch_permitted'])
 def test_effect_scope_request_mismatch_blocks(self):
  f=self.s.acquire(self.op,self.key,'A',0,30)['lease_fence']; self.s.reserve_effect(self.op,self.key,'A',f,'PAY','c'*64,'dkey',1)
  with self.assertRaisesRegex(Blocked,'DIFFERENT_REQUEST'): self.s.reserve_effect(self.op,self.key,'A',f,'PAY','e'*64,'dkey',2)
if __name__=='__main__':
 r=unittest.main(verbosity=2,exit=False).result
 print(f'S30_C05_ORACLE_V2_TESTS={r.testsRun} RESULT={"PASS" if r.wasSuccessful() else "FAIL"} DYNAMIC_PROOF=0 MODEL_CALLS=0')
 raise SystemExit(0 if r.wasSuccessful() else 1)
