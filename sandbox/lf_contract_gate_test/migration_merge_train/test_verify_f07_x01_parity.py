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
            "lf-independent-change-admission", "ig-runtime-candidate-judge", "PASE",
            "migration-source-parity",
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

    def test_activation_ruleset_including_pase_matches_train(self):
        required = verify.load_required_checks()
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [
                {"context": "lf-independent-change-admission"},
                {"context": "ig-runtime-candidate-judge"},
                {"context": "PASE"},
                {"context": "migration-source-parity"},
                {"context": "lf-merge-train/verified"},
            ]
        }}]}
        self.assertEqual(verify.compare(required, ruleset), (True, [], []))

    def test_ruleset_without_pase_remains_out_of_parity(self):
        required = verify.load_required_checks()
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [
                {"context": "lf-independent-change-admission"},
                {"context": "ig-runtime-candidate-judge"},
                {"context": "migration-source-parity"},
                {"context": "lf-merge-train/verified"},
            ]
        }}]}
        self.assertEqual(verify.compare(required, ruleset), (False, ["PASE"], []))

    def test_ruleset_without_migration_source_parity_remains_out_of_parity(self):
        required = verify.load_required_checks()
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [
                {"context": "lf-independent-change-admission"},
                {"context": "ig-runtime-candidate-judge"},
                {"context": "PASE"},
                {"context": "lf-merge-train/verified"},
            ]
        }}]}
        self.assertEqual(
            verify.compare(required, ruleset),
            (False, ["migration-source-parity"], []),
        )

    def test_extra_ruleset_context_fails_as_surplus(self):
        required = {"PASE"}
        ruleset = {"rules": [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [{"context": "PASE"}, {"context": "unexpected"}]
        }}]}
        self.assertEqual(verify.compare(required, ruleset), (False, [], ["unexpected"]))


if __name__ == "__main__":
    unittest.main()
