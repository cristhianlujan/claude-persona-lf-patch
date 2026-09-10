#!/usr/bin/env python3
from __future__ import annotations
import json, subprocess, sys, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE))
import s30d_integration_gate_v2 as gate
import s30d_r09_v2 as r09
class T(unittest.TestCase):
 def test_prepare_gate_passes_while_external_blocker_is_explicit(self):
  x=gate.evaluate(False); self.assertEqual(x['status'],'PASS'); self.assertIn('S30-C:LF_CONTRACT_CHECK_NOT_GREEN',x['external_pending']); self.assertEqual(x['model_calls'],0)
 def test_final_gate_fails_closed_on_s30c_external_ci(self):
  x=gate.evaluate(True); self.assertEqual(x['status'],'BLOCKED'); self.assertFalse(x['final_acceptance_allowed']); self.assertIn('S30-C:LF_CONTRACT_CHECK_NOT_GREEN',x['blocking_reasons'])
 def test_r09_build_52_cases_zero_escape_zero_model(self):
  x=r09.run(); self.assertEqual(x['r09_build_status'],'PASS'); self.assertEqual(x['metrics']['TOTAL_REPLAY_CASES'],52); self.assertEqual(x['metrics']['PREVENTABLE_FIRST_HOP_ESCAPE_COUNT'],0); self.assertEqual(x['metrics']['MODEL_CALLS_FOR_MACHINE_DETECTABLE_REPLAY'],0)
 def test_new_deterministic_first_cases_present(self):
  c=json.loads((HERE/'r09_corpus_v2.json').read_text()); ids={x['case_id'] for x in c['cases']}; self.assertTrue({'I01','I02','I03','I04','I05','I06'}<=ids)
 def test_no_shared_workflow_change_required(self):
  w=(ROOT/'.github/workflows/validate-lf-packs.yml').read_text(); self.assertIn('tests=(sandbox/lf_contract_gate_test/s30_*/test_*.py)',w); self.assertIn('python "${test_file}"',w)
 def test_safety_scope_is_sandbox_only(self):
  s=json.loads((HERE/'upstream_status_v1.json').read_text()); self.assertEqual(s['safety'],{'production_changed':False,'runtime_changed':False,'s26_changed':False,'scheduler_changed':False,'snapshot_35_write':False})
if __name__=='__main__':
 r=unittest.main(verbosity=2,exit=False).result
 print(f'S30_D_PREP_REGRESSION_EXECUTED=1 TEST_COUNT={r.testsRun} RESULT={"PASS" if r.wasSuccessful() else "FAIL"} MODEL_CALLS=0')
 raise SystemExit(0 if r.wasSuccessful() else 1)
