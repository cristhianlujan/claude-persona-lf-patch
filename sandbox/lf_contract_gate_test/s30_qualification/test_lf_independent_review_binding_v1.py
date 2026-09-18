#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from lf_independent_review_binding_analyzer_v1 import analyze

HERE = Path(__file__).resolve().parent
BASE = json.loads((HERE / "live_independent_review_inventory_20260914.json").read_text(encoding="utf-8"))


class IndependentReviewBindingAnalyzerTest(unittest.TestCase):
    def test_live_inventory_passes(self) -> None:
        result = analyze(copy.deepcopy(BASE))
        self.assertEqual("PASS", result["status"])
        self.assertEqual(3, result["binding_count"])
        self.assertFalse(result["review_case_authoritative"])

    def test_missing_financial_binding_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["active_requirement_bindings"] = [
            row for row in payload["active_requirement_bindings"]
            if row["suite_code"] != "TS-STRATEGY-FINANCIAL-V1"
        ]
        result = analyze(payload)
        self.assertEqual("BLOCKED", result["status"])
        self.assertTrue(any("TS-STRATEGY-FINANCIAL-V1" in x for x in result["findings"]))

    def test_non_independent_binding_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["active_requirement_bindings"][0]["independent_review_required"] = False
        result = analyze(payload)
        self.assertEqual("BLOCKED", result["status"])

    def test_probe_drift_blocks(self) -> None:
        payload = copy.deepcopy(BASE)
        payload["suite_case_pattern"]["probe_code"] = "OTHER"
        result = analyze(payload)
        self.assertEqual("BLOCKED", result["status"])
        self.assertIn("INDEPENDENT_PROBE_DRIFT", result["findings"])


if __name__ == "__main__":
    unittest.main()
