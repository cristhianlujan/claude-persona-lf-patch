"""Exercise the existing TypeScript proof verifier in the established Edge CI lane."""
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PROOF_TEST = ROOT / "supabase/functions/run-creacion-perfil-lf/verified_proof_evidence.test.mjs"


class S26BindingProofVerifierTests(unittest.TestCase):
    def test_node_verifier_real_positive_and_negative_suite(self):
        node = shutil.which("node")
        self.assertIsNotNone(node, "Node.js required to run canonical verifier tests")
        result = subprocess.run(
            [node, "--experimental-strip-types", "--test", str(PROOF_TEST)],
            cwd=ROOT, text=True, capture_output=True, timeout=60, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + "\\n" + result.stderr)
        self.assertIn("runtime-binding repair", result.stdout)


if __name__ == "__main__":
    unittest.main()
