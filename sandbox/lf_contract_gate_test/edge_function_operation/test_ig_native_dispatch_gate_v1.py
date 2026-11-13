"""Execute genuine Node runtime tests on the native dispatcher candidate.
Model-provider execution is NOT simulated as a real provider invocation.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
TEST=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/native_dispatch_v1.test.mjs"
CRYPTO=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/native_receipt_ed25519_v1.test.mjs"
class NativeDispatchCandidate(unittest.TestCase):
    def test_actual_node_negative_cases(self):
        self.assertTrue(shutil.which("node"),"NOT_TESTED_NODE_MISSING")
        p=subprocess.run(["node","--test","--test-reporter=tap",str(TEST),str(CRYPTO)],
          text=True,capture_output=True,timeout=120)
        self.assertEqual(p.returncode,0,"NODE_NATIVE_DISPATCH_TEST_FAIL\n"+p.stdout[-3500:]+"\n"+p.stderr[-2000:])
        self.assertIn("# fail 0",p.stdout)
        self.assertIn("# tests 23",p.stdout)
        print("PASS_NATIVE_DISPATCH_23_NODE_TESTS_ED25519_AND_NEGATIVES_NO_HMAC",flush=True)

if __name__=="__main__": unittest.main()
