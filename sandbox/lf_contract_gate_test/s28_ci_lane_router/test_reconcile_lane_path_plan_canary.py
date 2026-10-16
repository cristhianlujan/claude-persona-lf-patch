from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
from lf_ci_lane_router import classify
from lf_repository_path_admission import load_repository_path_admission

WORKFLOW = ".github/workflows/lf-migration-reconcile-lane.yml"


class ReconcileLanePathPlanCanary(unittest.TestCase):
    def test_exact_admission_preserves_denial_of_other_workflows(self):
        policy = load_repository_path_admission()
        self.assertEqual(policy.evaluate(WORKFLOW)["verdict"], "ADMIT")
        for path in (
            ".github/workflows/lf-x-not-admitted.yml",
            WORKFLOW + ".bak",
            WORKFLOW.replace(".yml", ".yaml"),
            WORKFLOW.replace(".yml", "-copy.yml"),
        ):
            with self.subTest(path=path):
                self.assertEqual(policy.evaluate(path), {
                    "verdict": "BLOCK", "code": "FAIL_UNAUTHORIZED_GITHUB_PATH"
                })

    def test_real_main_plan_for_local_only_workflow_git_object(self):
        lane = classify([WORKFLOW])
        self.assertEqual(lane.mode, "CI_ROUTER_SELFTEST_ONLY")
        self.assertEqual(lane.required_controls, ("CI_ROUTER_SELFTEST",))
        with tempfile.TemporaryDirectory(prefix="reconcile-lane-plan-") as tmp:
            # A separate index builds an unreferenced, single-parent canary
            # commit from the real checkout HEAD. No workflow is written to the
            # working tree, no branch moves, and the canary is never pushed.
            env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"))

            def git(*args):
                return subprocess.check_output(
                    ["git", "-C", str(ROOT), *args], env=env, text=True,
                ).strip()

            base = git("rev-parse", "HEAD")
            blob = git("rev-parse", f"{base}:docs/reconcile/lane_workflow.patch.yml")
            git("read-tree", base)
            git("update-index", "--add", "--cacheinfo", f"100644,{blob},{WORKFLOW}")
            tree = git("write-tree")
            head = git(
                "-c", "user.name=Reconcile local canary",
                "-c", "user.email=reconcile-canary@example.invalid",
                "commit-tree", tree, "-p", base, "-m", "Local-only reconcile workflow plan canary",
            )
            output = Path(tmp) / "plan.json"
            result = subprocess.run([
                sys.executable, str(HERE / "emit_ci_execution_plan_v2.py"),
                "--repo-root", str(ROOT), "--base", base, "--head", head,
                "--authority-current-revision", base,
                "--event-name", "pull_request", "--ref-name", "refs/pull/0/head",
                "--output-json", str(output),
            ], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            plan = json.loads(output.read_text(encoding="utf-8"))
            self.assertTrue(plan["coverage_complete"])
            self.assertEqual(plan["changed_paths"], [WORKFLOW])
            self.assertEqual(plan["base_sha"], base)
            self.assertEqual(plan["head_sha"], head)
            self.assertEqual(len(plan["control_universe"]), 26)


if __name__ == "__main__":
    unittest.main(verbosity=2)
