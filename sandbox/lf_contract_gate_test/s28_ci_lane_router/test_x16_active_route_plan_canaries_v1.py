from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import lf_ci_lane_router  # noqa: E402
import lf_ci_execution_plan_v2 as plan_module  # noqa: E402
import lf_pase_control_repair_quarantine_v1 as quarantine_module  # noqa: E402


ROUTES = {
    "sandbox/lf_contract_gate_test/migration_source_parity/x16_route_probe.py": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/s30_migration_source_parity/x16_route_probe.py": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/train_receipt_verifier/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/pase_f09_013/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/db_write_transport/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "MIGRATION_ROUTE_GUARD"}
    },
    "sandbox/lf_contract_gate_test/migration_merge_train/x16_route_probe.py": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/pase_merge_gate/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/pase_orchestrator/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/canonical_route_guard/x16_route_probe.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "MIGRATION_ROUTE_GUARD"}
    },
    "CLAUDE.md": {"mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST"}},
    "AGENTS.md": {"mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST"}},
}


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


class X16ActiveRoutePlanCanariesTest(unittest.TestCase):
    def test_classify_and_full_emitter_for_every_requested_route(self):
        universe, _ = plan_module.load_registry()
        policy = json.loads((HERE / "lf_pase_control_repair_quarantine_v1.json").read_text(encoding="utf-8"))
        quarantined = quarantine_module.validate_policy(policy, control_universe=list(universe))
        self.assertEqual(set(quarantined), set(universe))
        actual_control_ids = {control.control_id for control in plan_module.load_registry()[1]}

        main_sha = git(ROOT, "rev-parse", "HEAD")
        with tempfile.TemporaryDirectory(prefix="x16-route-plan-") as tmp:
            temp_root = Path(tmp)
            for index, (path, expected) in enumerate(ROUTES.items()):
                candidate = temp_root / f"candidate-{index}"
                git(ROOT, "worktree", "add", "--detach", str(candidate), main_sha)
                try:
                    target = candidate / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if path in {"CLAUDE.md", "AGENTS.md"} and target.exists():
                        target.write_text(target.read_text(encoding="utf-8") + "\nX16 local route canary.\n", encoding="utf-8")
                    else:
                        target.write_text("X16 local route canary.\n", encoding="utf-8")
                    git(candidate, "add", path)
                    committed = subprocess.run(
                        ["git", "-C", str(candidate), "-c", "user.name=X16 local canary",
                         "-c", "user.email=x16-canary@example.invalid", "commit", "-m", "test: local X16 route canary"],
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(committed.returncode, 0, committed.stderr)
                    head_sha = git(candidate, "rev-parse", "HEAD")

                    lane = lf_ci_lane_router.classify([path])
                    self.assertEqual(lane.mode, expected["mode"], f"classify {path}: {lane.reasons}")
                    self.assertTrue(expected["controls"].issubset(set(lane.required_controls)), path)
                    self.assertTrue(set(lane.required_controls).issubset(actual_control_ids), path)

                    output = temp_root / f"plan-{index}.json"
                    emitter = candidate / "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py"
                    emitted = subprocess.run(
                        [sys.executable, str(emitter), "--repo-root", str(candidate), "--base", main_sha,
                         "--head", head_sha, "--authority-current-revision", main_sha,
                         "--event-name", "pull_request", "--ref-name", "refs/pull/0/head",
                         "--output-json", str(output)],
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(emitted.returncode, 0, f"emitter {path}\n{emitted.stdout}\n{emitted.stderr}")
                    plan = json.loads(output.read_text(encoding="utf-8"))
                    self.assertTrue(plan["coverage_complete"], path)
                    self.assertEqual(plan["changed_paths"], [path])
                    self.assertTrue(expected["controls"].issubset(set(plan["required_controls"])), path)
                finally:
                    git(ROOT, "worktree", "remove", "--force", str(candidate))


if __name__ == "__main__":
    unittest.main(verbosity=2)
