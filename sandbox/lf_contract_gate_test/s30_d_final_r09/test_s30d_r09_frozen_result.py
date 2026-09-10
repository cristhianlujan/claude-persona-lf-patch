#!/usr/bin/env python3
import json,sys,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; sys.path.insert(0,str(HERE)); import s30d_independent_verify_v2 as iv
class T(unittest.TestCase):
 def setUp(self): self.r=json.loads((HERE/'s30_d_r09_frozen_result_v2.json').read_text()); self.c=json.loads((HERE/'s30_d_r09_final_candidate_v2.json').read_text())
 def test_independent_verify_passes(self): self.assertEqual(iv.verify()['result'],'PASS')
 def test_claim_scoped_not_golden(self): self.assertEqual(self.r['result'],'S30_P0_SELF_GOVERNANCE_R09_PASS'); self.assertEqual(self.r['claim_scope'],'R09_ONLY_NOT_S30_GOLDEN')
 def test_52_cases_zero_escapes(self): self.assertEqual(self.r['metrics']['TOTAL_REPLAY_CASES'],52); self.assertEqual(self.r['metrics']['PREVENTABLE_FIRST_HOP_ESCAPE_COUNT'],0)
 def test_branch_ci_green(self): self.assertEqual(self.r['r09']['validate_lf_packs']['conclusion'],'SUCCESS'); self.assertEqual(self.r['r09']['lf_contract_check']['conclusion'],'SUCCESS')
 def test_next_gate_is_c05(self): self.assertEqual(self.r['next_gate'],'C05_DYNAMIC_IDEMPOTENCY_LEASE_FIRE_TEST_BEFORE_OPERATION_BOOTSTRAP')
 def test_main_merge_not_authorized(self): self.assertFalse(self.c['main_merge_authorized']); self.assertEqual(self.c['promotion_authority'],'NONE')
if __name__=='__main__':
 r=unittest.main(verbosity=2,exit=False).result; print(f'S30_D_R09_FROZEN_REGRESSION=1 TEST_COUNT={r.testsRun} RESULT={"PASS" if r.wasSuccessful() else "FAIL"} MODEL_CALLS=0'); raise SystemExit(0 if r.wasSuccessful() else 1)
