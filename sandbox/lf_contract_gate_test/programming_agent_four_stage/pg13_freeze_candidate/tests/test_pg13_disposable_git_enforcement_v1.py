"""Execute the REAL Git mutation harness, not a declared C3 scenario."""
import subprocess
import sys
import unittest
from pathlib import Path

class GitFreezeMutation(unittest.TestCase):
    def test_actual_force_push_non_fast_forward_block(self):
        script=Path(__file__).resolve().parents[1]/"tools"/"pg13_disposable_git_mutation_test_v1.py"
        proc=subprocess.run([sys.executable,str(script)],capture_output=True,
                            text=True,timeout=30,check=False)
        self.assertEqual(proc.returncode,0,proc.stderr+"\n"+proc.stdout)
        self.assertIn("PG13_C3_DISPOSABLE_GIT_FORCE_PUSH_BLOCK=PASS",proc.stdout)
        self.assertIn("PG13_C3_GIT_FORCE_PUSH_COMMAND_EXIT_NONZERO=TRUE",proc.stdout)
        self.assertIn("PG13_C3_REMOTE_SHA_UNCHANGED=TRUE",proc.stdout)
        self.assertIn("PG13_C3_LOCAL_DIVERGENT_COMMIT_BLOCK=PASS",proc.stdout)
        self.assertIn("PG13_C3_PRODUCTION_FREEZE_VERIFIED=FALSE",proc.stdout)
if __name__=="__main__":unittest.main()
