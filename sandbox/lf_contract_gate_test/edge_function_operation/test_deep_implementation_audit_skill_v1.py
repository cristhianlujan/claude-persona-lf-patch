"""Admit the candidate skill's local tests to existing R17; no workflow/DB changes."""
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACK = ROOT / "skills/auditoria-profunda-implementacion-lf"


class DeepImplementationAuditR17(unittest.TestCase):
    def test_candidate_suite_and_pack(self):
        for command in ([sys.executable, "-m", "unittest", "discover", "-s", str(PACK / "evals"), "-p", "test_*.py", "-v"],
                        [sys.executable, str(PACK / "validators/validate_pack.py")]):
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout[-1800:] + result.stderr[-6000:])


if __name__ == "__main__":
    unittest.main()
