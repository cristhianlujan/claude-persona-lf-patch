#!/usr/bin/env python3
from __future__ import annotations
import json,sys,unittest
from collections import Counter
from pathlib import Path
HERE=Path(__file__).resolve().parent; sys.path.insert(0,str(HERE))
import s30d_e2e_blueprint_gate as gate
class T(unittest.TestCase):
 def test_blueprint_gate_passes_but_execution_is_not_authorized(self):
  x=gate.validate(); self.assertEqual(x["status"],"PASS_BLUEPRINT"); self.assertFalse(x["execution_allowed"]); self.assertEqual(x["case_count"],50)
 def test_exact_10_families_5_each(self):
  e=json.loads((HERE/"e2e_campaign_blueprint_v1.json").read_text()); c=Counter(x["family"] for x in e["cases"]); self.assertEqual(len(c),10); self.assertEqual(set(c.values()),{5})
 def test_four_dimensions_present_everywhere(self):
  e=json.loads((HERE/"e2e_campaign_blueprint_v1.json").read_text()); self.assertTrue(all(set(x["dimensions"])=={"functionality","depth","performance","quality"} for x in e["cases"]))
 def test_performance_collects_latency_calls_context_retries(self):
  r=json.loads((HERE/"e2e_result_contract_v1.json").read_text()); self.assertEqual(set(r["performance"]["required_metrics"]),{"total_ms","per_hop_ms","backend_calls","model_calls","bytes_or_context","retries"})
 def test_quality_keeps_semantic_judge_evaluation_only(self):
  r=json.loads((HERE/"e2e_result_contract_v1.json").read_text()); self.assertFalse(r["quality"]["producer_self_verdict_allowed"]); self.assertIn("independent evaluation only",r["quality"]["semantic"])
 def test_navigation_runs_only_after_e2e(self):
  n=json.loads((HERE/"data_navigation_trace_blueprint_v1.json").read_text()); self.assertEqual(n["execution_prerequisite"],"S30_INTEGRATED_E2E_50_PASS"); self.assertIn("INDEPENDENT_READBACK",n["trace_order"]); self.assertIn("EVIDENCE_RECEIPT",n["trace_order"])
if __name__=="__main__":
 r=unittest.main(verbosity=2,exit=False).result; print(f"S30_E2E_BLUEPRINT_REGRESSION_EXECUTED=1 TEST_COUNT={r.testsRun} RESULT={'PASS' if r.wasSuccessful() else 'FAIL'} MODEL_CALLS=0 LIVE_E2E=0"); raise SystemExit(0 if r.wasSuccessful() else 1)
