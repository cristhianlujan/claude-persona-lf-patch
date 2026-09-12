#!/usr/bin/env python3
import json,hashlib,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
class T(unittest.TestCase):
 def setUp(self): self.r=json.loads((HERE/"s30_c_terminal_closeout_candidate_v1.json").read_text())
 def test_not_final_before_merge(self): self.assertFalse(self.r["final_closed_now"]); self.assertFalse(self.r["main_merge_authorized"]); self.assertEqual(self.r["promotion_authority"],"NONE")
 def test_exact_main_green(self): self.assertEqual(self.r["current_exact_main_ci"]["validate_lf_packs"]["conclusion"],"SUCCESS"); self.assertEqual(self.r["current_exact_main_ci"]["lf_contract_check"]["conclusion"],"SUCCESS")
 def test_router_isolation(self): x=self.r["router_fix"]; self.assertEqual(x["s30_c_mode"],"S30_C_RELIABILITY_ISOLATED"); self.assertFalse(x["p0_exact_head_external_required"]); self.assertFalse(x["migration_parity_required"]); self.assertFalse(x["input_governance_parity_required"])
 def test_bound_hashes_current(self):
  for b in self.r["bindings"].values(): self.assertEqual(sha(ROOT/b["path"]),b["sha256"])
 def test_claim_ceiling_preserved(self): self.assertEqual(self.r["claim_ceiling"],"EVIDENCE_FREEZE_AND_REPLAY_HARNESS_READY")
if __name__=="__main__":
 rr=unittest.main(verbosity=2,exit=False).result
 print(f"S30_C_CLOSEOUT_CANDIDATE_TESTS={rr.testsRun} RESULT={'PASS' if rr.wasSuccessful() else 'FAIL'}")
 raise SystemExit(0 if rr.wasSuccessful() else 1)
