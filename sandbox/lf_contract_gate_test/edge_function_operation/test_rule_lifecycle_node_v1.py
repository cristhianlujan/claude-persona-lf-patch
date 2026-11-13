"""Bridge the existing allowlisted edge-operation test carrier to LF lifecycle tests.
This does not add or change a workflow, ACL, Router or writer.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TEST = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/test_lifecycle_gate.mjs"

class LifecycleCandidateTest(unittest.TestCase):
    def test_node_positive_negative_and_simulated_e2e(self):
        node = shutil.which("node")
        self.assertIsNotNone(node, "Node.js is required for the existing CI test carrier")
        self.assertTrue(TEST.is_file(), str(TEST))
        result = subprocess.run([node, "--test", "--test-reporter=tap", str(TEST)], cwd=ROOT, text=True,
                                capture_output=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + "\n" + result.stderr)
        self.assertIn("# fail 0", result.stdout)
        self.assertIn("# tests 26", result.stdout)

if __name__ == "__main__":
    unittest.main()
