#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("verify_f07_x01_parity", HERE / "verify_f07_x01_parity.py")
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class F07X01ParityTests(unittest.TestCase):
    def test_loads_check_list_from_versioned_file(self):
        self.assertEqual(verify.load_required_checks(), {
            "lf-independent-change-admission", "ig-runtime-candidate-judge"
        })

    def test_equal_context_sets_pass(self):
        required = {"PASE", "pase-merge-gate"}
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [
                {"context": "PASE"}, {"context": "pase-merge-gate"},
                {"context": "lf-merge-train/verified"}
            ]
        }}]}
        self.assertEqual(verify.compare(required, ruleset), (True, [], []))

    def test_extra_ruleset_context_fails_as_surplus(self):
        required = {"PASE"}
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [{"context": "PASE"}, {"context": "unexpected"}]
        }}]}
        self.assertEqual(verify.compare(required, ruleset), (False, [], ["unexpected"]))


if __name__ == "__main__":
    unittest.main()
