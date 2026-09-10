#!/usr/bin/env python3
from __future__ import annotations
import json,sys,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]; sys.path.insert(0,str(HERE))
import s30d_integration_gate_v2 as gate, s30d_r09_v2 as r09
class T(unittest.TestCase):
    def test_prepare_gate_passes(self): self.assertEqual(gate.evaluate(False)['status'],'PASS')
    def test_final_gate_passes_after_c_terminal_closeout(self):
        x=gate.evaluate(True); self.assertEqual(x['status'],'PASS'); self.assertTrue(x['final_acceptance_allowed']); self.assertEqual(x['external_pending'],[])
    def test_r09_52_cases_zero_escape_zero_model(self):
        x=r09.run(); self.assertEqual(x['r09_status'],'PASS'); self.assertEqual(x['metrics']['TOTAL_REPLAY_CASES'],52); self.assertEqual(x['metrics']['PREVENTABLE_FIRST_HOP_ESCAPE_COUNT'],0); self.assertEqual(x['metrics']['MODEL_CALLS_FOR_MACHINE_DETECTABLE_REPLAY'],0)
    def test_deterministic_first_extension_present(self):
        ids={x['case_id'] for x in json.loads((HERE/'r09_corpus_v2.json').read_text())['cases']}; self.assertTrue({'I01','I02','I03','I04','I05','I06'}<=ids)
    def test_current_readback_is_safe(self):
        r=json.loads((HERE/'r09_current_readback_v2.json').read_text()); self.assertFalse(r['supabase_write']); self.assertFalse(r['runtime_changed']); self.assertEqual(r['future_operation_registry']['rows_found'],0)
    def test_router_isolation(self):
        x=gate.router_decision('sandbox/lf_contract_gate_test/s30_d_final_r09/r09_corpus_v2.json'); self.assertEqual(x['mode'],'S30_D_FINAL_R09_ISOLATED'); self.assertFalse(x['p0_exact_head_external_required'])
    def test_generic_ci_discovery_present(self):
        w=(ROOT/'.github/workflows/validate-lf-packs.yml').read_text(); self.assertIn('tests=(sandbox/lf_contract_gate_test/s30_*/test_*.py)',w)
    def test_scope_safety(self):
        self.assertEqual(json.loads((HERE/'upstream_status_v1.json').read_text())['safety'],{'production_changed':False,'runtime_changed':False,'s26_changed':False,'scheduler_changed':False,'snapshot_35_write':False})
if __name__=='__main__':
    r=unittest.main(verbosity=2,exit=False).result; print(f'S30_D_R09_REGRESSION_EXECUTED=1 TEST_COUNT={r.testsRun} RESULT={"PASS" if r.wasSuccessful() else "FAIL"} MODEL_CALLS=0'); raise SystemExit(0 if r.wasSuccessful() else 1)
