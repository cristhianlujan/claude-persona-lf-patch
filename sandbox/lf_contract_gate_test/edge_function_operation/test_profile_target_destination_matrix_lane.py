"""Exercise the existing Profile Updater matrix suite through the existing Edge R17 test lane.

No workflow added; this suite is invoked by lf-edge-function-operation-tests.yml
using unittest discovery whenever this directory changes.
"""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SUITE = "sandbox/lf_contract_gate_test/profile_execution_runtime"


class ProfileUpdaterControlMatrixLane(unittest.TestCase):
    def test_profile_specific_destinations_matrix_suite(self):
        proc = subprocess.run(
            ["python3", "-m", "unittest", "discover", "-s", SUITE,
             "-p", "test_profile_target_destination_matrix.py", "-v"],
            cwd=ROOT, text=True, capture_output=True, timeout=90,
        )
        self.assertEqual(proc.returncode, 0,
                         "Profile destination matrix tests failed:\n" + proc.stdout[-6000:] +
                         "\n" + proc.stderr[-12000:])
        self.assertIn("Ran 22 tests", proc.stderr)
        # The canonical evaluator emits this diagnostic from recorded runs;
        # print only its compact row summary, never the full model RAW.
        for line in proc.stdout.splitlines():
            if line.startswith("WEB001_TRUSTED_GROUP2_READBACK "):
                print(line)
        self.assertIn("OK", proc.stderr)
