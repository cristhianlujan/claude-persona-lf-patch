#!/usr/bin/env python3
import json,hashlib,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
class T(unittest.TestCase):
 def setUp(self): self.r=json.loads((HERE/"s30_c_final_closeout_receipt_v1.json").read_text())
 def test_exact_main_evidence_green(self):
  self.assertEqual(self.r["evidence_base_main_sha"],"bbce2cbbd8be2821db86c6feb31bb43a1826a989")
  self.assertEqual(self.r["exact_main_ci"]["validate_lf_packs"]["conclusion"],"SUCCESS")
  self.assertEqual(self.r["exact_main_ci"]["lf_contract_check"]["conclusion"],"SUCCESS")
 def test_router_isolated(self):
  x=self.r["router_readback"]; self.assertEqual(x["s30_c_mode"],"S30_C_RELIABILITY_ISOLATED"); self.assertFalse(x["p0_exact_head_external_required"]); self.assertFalse(x["migration_parity_required"]); self.assertFalse(x["input_governance_parity_required"])
 def test_bindings_current(self):
  for b in self.r["bindings"].values(): self.assertEqual(sha(ROOT/b["path"]),b["sha256"])
 def test_terminal_semantics_verified_but_persistence_pending(self):
  self.assertEqual(self.r["semantic_terminal_state"],"FINAL_CLOSED_VERIFIED"); self.assertEqual(self.r["durable_persistence_state"],"PENDING_THIS_GOVERNED_PROMOTION")
 def test_claim_ceiling_and_safety(self):
  self.assertEqual(self.r["claim_ceiling"],"EVIDENCE_FREEZE_AND_REPLAY_HARNESS_READY"); self.assertTrue(all(v is False for v in self.r["safety"].values())); self.assertFalse(self.r["main_merge_authorized"])
if __name__=="__main__":
 rr=unittest.main(verbosity=2,exit=False).result
 print(f"S30_C_FINAL_CLOSEOUT_TESTS={rr.testsRun} RESULT={'PASS' if rr.wasSuccessful() else 'FAIL'} MODEL_CALLS=0")
 raise SystemExit(0 if rr.wasSuccessful() else 1)
