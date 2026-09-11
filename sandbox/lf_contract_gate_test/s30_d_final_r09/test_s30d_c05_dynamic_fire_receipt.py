#!/usr/bin/env python3
import hashlib, json, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
class T(unittest.TestCase):
 def setUp(self): self.r=json.loads((HERE/"c05_dynamic_fire_test_receipt_v1.json").read_text())
 def test_primary_migration_source_is_exact_candidate(self):
  a=ROOT/self.r["migration"]["primary"]["repo_path"]
  b=HERE/"c05_generic_execution_reliability_candidate_v1.sql"
  self.assertEqual(hashlib.sha256(a.read_bytes()).hexdigest(),self.r["migration"]["primary"]["sql_sha256"])
  self.assertEqual(a.read_bytes(),b.read_bytes())
 def test_migration_ledgers_bound(self):
  self.assertEqual(self.r["migration"]["primary"]["version"],"20260911025454")
  self.assertEqual(self.r["migration"]["acl_hardening"]["version"],"20260911030211")
  for m in self.r["migration"].values(): self.assertTrue(m["applied"] and m["ledger_readback"])
 def test_all_nine_cases_pass(self):
  self.assertEqual(set(self.r["cases"]),{f"C05-{i:02d}" for i in range(1,10)})
  self.assertTrue(all(x["status"]=="PASS" for x in self.r["cases"].values()))
 def test_hard_targets_zero(self): self.assertTrue(all(v==0 for v in self.r["hard_targets"].values()))
 def test_security_boundary_and_acl_repair(self):
  s=self.r["schema_readback"]
  self.assertFalse(s["authenticated_function_execute"]); self.assertFalse(s["anon_function_execute"]); self.assertTrue(s["service_role_function_execute"])
  self.assertEqual(s["effect_guard_service_role_privileges"],["INSERT","SELECT","UPDATE"])
  self.assertFalse(s["effect_guard_service_role_delete_allowed"])
  self.assertTrue(self.r["acl_repair"]["initial_overgrant_detected"] and self.r["acl_repair"]["repair_migration_applied"])
  self.assertEqual(self.r["acl_repair"]["delete_negative_sqlstate"],"42501")
 def test_downstream_not_bootstrapped(self):
  self.assertFalse(self.r["schema_readback"]["strategy_execute_registered"]); self.assertFalse(self.r["schema_readback"]["orchestrator_registered"])
  self.assertFalse(self.r["safety"]["runtime_activated"]); self.assertFalse(self.r["safety"]["scheduler_changed"])
 def test_proof_limit_is_explicit(self):
  p=self.r["proof_limits"]
  self.assertTrue(p["two_distinct_database_sessions_exercised"] and p["connector_invocations_serialized"])
  self.assertFalse(p["temporal_overlap_empirically_proven"]); self.assertFalse(p["external_exactly_once_claimed"])
if __name__=="__main__":
 r=unittest.main(verbosity=2,exit=False).result
 print(f"S30_C05_DYNAMIC_FIRE_RECEIPT_TESTS={r.testsRun} RESULT={'PASS' if r.wasSuccessful() else 'FAIL'}")
 raise SystemExit(0 if r.wasSuccessful() else 1)
