"""B25/B28: mutate guard behavior, fail for EXPECTED assertion not a syntax error."""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
SRC = (ROOT / 'render_ready_gate_v1.py').read_text()
TESTS = (ROOT / 'test_render_ready_gate_v1.py').read_text()


class GuardMutationTests(unittest.TestCase):
    def kills(self, before: str, after: str, case: str):
        self.assertEqual(SRC.count(before),1, 'mutation anchor must occur once')
        mutant = SRC.replace(before,after)
        with tempfile.TemporaryDirectory() as folder:
            d=pathlib.Path(folder)
            (d/'render_ready_gate_v1.py').write_text(mutant)
            (d/'test_render_ready_gate_v1.py').write_text(TESTS)
            result=subprocess.run([sys.executable,'-m','unittest','-v',
                                   'test_render_ready_gate_v1.Tests.'+case],
                                  cwd=d,capture_output=True,text=True,timeout=10)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('AssertionError: RenderAdmissionRejected not raised', result.stderr,
                      'mutant must fail by the specific expected rejection check')
        self.assertNotIn('SyntaxError',result.stderr)

    def test_mutant_skips_render_authorized_dies(self):
        self.kills('and row.get("render_authorized") is True', 'and True',
                   'test_render_authorized_flag_required')

    def test_mutant_skips_review_only_dies(self):
        self.kills('and row.get("review_only") is False', 'and True',
                   'test_review_only_flag_denied')


if __name__=='__main__':
    unittest.main(verbosity=2)
