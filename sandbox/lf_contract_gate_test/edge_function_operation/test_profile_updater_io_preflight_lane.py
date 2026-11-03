"""Exercise 17-step input binding preflight in existing Edge R17 CI; no workflow added."""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class ProfileUpdaterInputPreflightLane(unittest.TestCase):
    def test_profile_updater_input_preflight_negative_suite(self):
        test = "test_profile_updater_io_preflight_v1.py"
        p = subprocess.run(
            ["python3", "-m", "unittest", "discover",
             "-s", "sandbox/lf_contract_gate_test/profile_execution_runtime",
             "-p", test, "-v"],
            cwd=ROOT, capture_output=True, text=True, timeout=90,
        )
        self.assertEqual(p.returncode, 0, p.stdout[-4000:] + "\n" + p.stderr[-12000:])
        match = re.search(r"Ran (\\d+) tests in", p.stderr)
        self.assertIsNotNone(match, p.stderr)
        self.assertGreaterEqual(int(match.group(1)), 13)
        for name in (
            "test_missing_proof_is_blocked",
            "test_cross_execution_receipt_is_blocked",
            "test_candidate_head_mismatch_is_blocked",
            "test_canonical_catalog_has_seventeen_ordered_stage_bindings",
            "test_ready_only_for_external_server_verification_not_pass",
        ):
            self.assertIn(name, p.stderr)
        self.assertIn("OK", p.stderr)
