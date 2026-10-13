from __future__ import annotations

import pathlib
import subprocess
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
WORKFLOW = ROOT / ".github/workflows/lf-migration-merge-train.yml"
RECORDER = HERE / "lf_train_execution_recorder.py"


class TrainExecutionRecorderTest(unittest.TestCase):
    def test_self_test(self) -> None:
        out = subprocess.run([sys.executable, str(RECORDER), "self-test"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("PASS_TRAIN_EXECUTION_RECORDER_SELFTEST", out.stdout)

    def test_reservation_idempotency_is_version_scoped(self) -> None:
        source = RECORDER.read_text()
        self.assertIn('idem=f"train:{ctx[\'version\']}:{ctx[\'source_blob\']}"', source)
        self.assertNotIn('idem=f"gitblob:{ctx[\'source_blob\']}"', source)
        self.assertIn("fn_lf_operation_reserve_execution_v1", source)

    def test_workflow_order(self) -> None:
        wf = WORKFLOW.read_text()
        begin = wf.index("Router execution begin (Train-managed, pre-apply)")
        apply = wf.index("- name: Apply exact version and ledger readback")
        commit = wf.index("Router execution patch step (Train-managed, post-apply)")
        parity = wf.index("- name: Run changeset-scoped parity")
        merge = wf.index("- name: Merge exact head only")
        close = wf.index("Router execution verify and close (Train-managed, post-merge)")
        self.assertLess(begin, apply)
        self.assertLess(apply, commit)
        self.assertLess(commit, parity)
        self.assertLess(merge, close)

    def test_post_apply_steps_never_block(self) -> None:
        wf = WORKFLOW.read_text()
        for name in ("Router execution patch step (Train-managed, post-apply)",
                     "Router execution verify and close (Train-managed, post-merge)"):
            block = wf[wf.index(name):wf.index(name) + 400]
            self.assertIn("continue-on-error: true", block, name)
        begin = wf[wf.index("Router execution begin (Train-managed, pre-apply)"):]
        begin = begin[:begin.index("- name: Apply exact version")]
        self.assertNotIn("continue-on-error", begin)
        self.assertIn("lf-train-trusted", begin)


if __name__ == "__main__":
    unittest.main()
