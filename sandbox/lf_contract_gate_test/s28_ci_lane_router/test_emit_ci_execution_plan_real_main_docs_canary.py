from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
EMITTER_REL = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py")
DOC_PATH = "docs/pase/x16/x16_docs_plan_canary.md"


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


class RealMainDocsCanaryPlanTest(unittest.TestCase):
    def test_emits_full_plan_for_docs_only_canary_on_real_main_snapshot(self):
        # Use the actual checked-out repository and its real registries. Only the
        # candidate docs file and temporary commit are synthetic; no plan,
        # ownership, family, impact, or quarantine fixture is substituted.
        main_sha = git(ROOT, "rev-parse", "HEAD")

        with tempfile.TemporaryDirectory(prefix="x16-main-docs-canary-") as tmp:
            temp_root = Path(tmp)
            repo = temp_root / "repo"
            git(ROOT, "worktree", "add", "--detach", str(repo), main_sha)
            try:
                canary = repo / DOC_PATH
                canary.parent.mkdir(parents=True, exist_ok=True)
                canary.write_text("X16 local docs-only canary.\n", encoding="utf-8")
                git(repo, "add", DOC_PATH)
                head_sha = subprocess.run(
                    [
                        "git", "-C", str(repo),
                        "-c", "user.name=F09-X16 regression",
                        "-c", "user.email=f09-x16-regression@example.invalid",
                        "commit", "-m", "test: ephemeral X16 docs-only plan canary",
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(head_sha.returncode, 0, head_sha.stderr)
                candidate_sha = git(repo, "rev-parse", "HEAD")
                output = temp_root / "plan.json"
                command = [
                    "python3", str(repo / EMITTER_REL),
                    "--repo-root", str(repo),
                    "--base", main_sha,
                    "--head", candidate_sha,
                    "--authority-current-revision", main_sha,
                    "--event-name", "pull_request",
                    "--ref-name", "refs/pull/0/head",
                    "--output-json", str(output),
                ]
                emitted = subprocess.run(
                    command,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(
                    emitted.returncode,
                    0,
                    f"full plan emitter failed\nstdout={emitted.stdout}\nstderr={emitted.stderr}",
                )
                plan = json.loads(output.read_text(encoding="utf-8"))
                self.assertEqual(plan["schema_version"], "lf-ci-execution-plan/v2")
                self.assertTrue(plan["coverage_complete"])
                self.assertEqual(plan["base_sha"], main_sha)
                self.assertEqual(plan["head_sha"], candidate_sha)
                self.assertEqual(plan["changed_paths"], [DOC_PATH])
                self.assertEqual(len(plan["control_universe"]), 26)
                enforcement = plan["pase_control_enforcement"]
                self.assertEqual(enforcement["blocking_controls"], [])
                self.assertTrue(enforcement["no_applicability_reclassification"])
            finally:
                git(ROOT, "worktree", "remove", "--force", str(repo))


if __name__ == "__main__":
    unittest.main(verbosity=2)
