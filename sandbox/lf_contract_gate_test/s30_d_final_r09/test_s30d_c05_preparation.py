#!/usr/bin/env python3
from __future__ import annotations
import json, sys, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; sys.path.insert(0,str(HERE))
from c05_reference_model import ReferenceStore
import s30d_c05_preflight as pre
OP="EJECUCION_ESTRATEGIA_LF"; KEY="EJECUCION_ESTRATEGIA_LF:S30:05:unit:X1"; H="a"*64
class T(unittest.TestCase):
 def new(self):
  s=ReferenceStore(); self.assertEqual(s.reserve(OP,KEY,H,"exec-A")["status"],"RESERVED"); return s
 def test_preparation_is_explicitly_not_dynamic_proof(self):
  x=pre.evaluate(); self.assertEqual(x["status"],"PASS_PREPARATION"); self.assertFalse(x["dynamic_execution_allowed"]); self.assertFalse(x["activation_allowed"]); self.assertIn("LIVE_TYPED_IDEMPOTENCY_LEASE_CARRIER_ABSENT",x["expected_dynamic_blockers"])
 def test_same_key_same_hash_replays_one_execution(self):
  s=self.new(); x=s.reserve(OP,KEY,H,"exec-B"); self.assertEqual(x,{"status":"REPLAY_EXISTING_EXECUTION","execution_id":"exec-A"}); self.assertEqual(len(s.rows),1)
 def test_same_key_different_hash_blocks(self):
  s=self.new(); x=s.reserve(OP,KEY,"b"*64,"exec-B"); self.assertEqual(x["status"],"BLOCKED"); self.assertEqual(x["code"],"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST")
 def test_current_lease_has_single_owner(self):
  s=self.new(); self.assertEqual(s.acquire_lease(OP,KEY,"worker-A",100,30)["status"],"ACQUIRED"); x=s.acquire_lease(OP,KEY,"worker-B",110,30); self.assertEqual(x["status"],"BLOCKED"); self.assertEqual(x["owner"],"worker-A")
 def test_expired_lease_allows_safe_takeover_without_new_reservation(self):
  s=self.new(); s.acquire_lease(OP,KEY,"worker-A",100,10); x=s.acquire_lease(OP,KEY,"worker-B",111,10); self.assertEqual(x["status"],"ACQUIRED"); self.assertEqual(x["owner"],"worker-B"); self.assertEqual(len(s.rows),1)
 def test_effect_success_persist_failure_retry_does_not_duplicate_effect(self):
  s=self.new(); self.assertEqual(s.effect_once(OP,KEY,"effect-1")["status"],"APPLIED"); self.assertEqual(s.effect_once(OP,KEY,"effect-1")["status"],"REPLAY_NOOP"); self.assertEqual(len(s.irreversible_effects),1)
 def test_scheduler_failure_resume_uses_checkpoint(self):
  s=self.new(); s.checkpoint(OP,KEY,4); self.assertEqual(s.resume_cursor(OP,KEY),4); s.checkpoint(OP,KEY,3); self.assertEqual(s.resume_cursor(OP,KEY),4)
 def test_blocked_child_does_not_hide_safe_child(self):
  s=self.new(); x=s.child_sweep({"S30":"BLOCKED_CAUSAL","S24":"SAFE","S27":"SAFE"}); self.assertTrue(x["continue_safe"]); self.assertEqual(x["executed"],["S24","S27"]); self.assertEqual(x["blocked"],["S30"])
 def test_e2e_blueprint_is_10_by_5_with_all_dimensions(self):
  e=json.loads((HERE/"e2e_campaign_blueprint_v1.json").read_text()); self.assertEqual(e["case_count"],50); self.assertEqual(len(e["cases"]),50); self.assertEqual(len({x["case_id"] for x in e["cases"]}),50); counts={}
  for x in e["cases"]:
   counts[x["family"]]=counts.get(x["family"],0)+1; self.assertEqual(set(x["dimensions"]),{"functionality","depth","performance","quality"}); self.assertEqual(x["cross_metrics"]["avoidable_work_target"],0)
  self.assertEqual(set(counts.values()),{5}); self.assertEqual(len(counts),10)
 def test_operation_drafts_are_not_registered_or_active(self):
  for n in ("strategy_execute_contract_draft_v1.json","orchestrator_contract_draft_v1.json"):
   x=json.loads((HERE/n).read_text()); self.assertEqual(x["status"],"SOURCE_DRAFT_NOT_REGISTERED"); self.assertTrue(x["activation_status"].startswith("BLOCKED_"))
if __name__=="__main__":
 r=unittest.main(verbosity=2,exit=False).result; print(f"S30_C05_PREP_REGRESSION_EXECUTED=1 TEST_COUNT={r.testsRun} RESULT={'PASS' if r.wasSuccessful() else 'FAIL'} MODEL_CALLS=0 DYNAMIC_PROOF=0"); raise SystemExit(0 if r.wasSuccessful() else 1)
