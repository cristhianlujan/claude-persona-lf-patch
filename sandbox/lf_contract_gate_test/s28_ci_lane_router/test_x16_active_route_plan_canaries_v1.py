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
    "sandbox/lf_contract_gate_test/ci_db_target/lf_ci_db_target_v1.json": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/contract_check_self_change_admission/lf_contract_check_self_change_admission_v1.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/edge_function_operation/R17_SEQUENCE_REPAIR_DIAGNOSIS.md": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/engineering_checkpoint_closure/checkpoint_step_judges_v1.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/engineering_checkpoint_mcp/README.md": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_0/test_m100_replacement_contract_v2.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/f0_workflow_activation/test_scope.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/human_decision_routing/test_human_decision_authority_receipt_verifier_v1.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/input_governance/test_ig_runtime_config_existing_authority_reuse_v1.py": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "INPUT_GOVERNANCE_MIGRATION_PARITY"},
        "plan_controls": {"MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "INPUT_GOVERNANCE_MIGRATION_PARITY"},
        "plan_controls": {"MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/input_governance_incremental/advisory_read_l1c.sql": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "INPUT_GOVERNANCE_MIGRATION_PARITY"},
        "plan_controls": {"MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/IG_RUNTIME_CANDIDATE_JUDGE_V1.json": {
        "mode": "SPECIALIZED_REQUIRED", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "INPUT_GOVERNANCE_MIGRATION_PARITY"},
        "plan_controls": {"MIGRATION_SOURCE_PARITY"}
    },
    "sandbox/lf_contract_gate_test/pase_evaluation_quality/f09_014_quality_cases_v1.json": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/pase_github_entrypoint/README.md": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/profile_execution_runtime/NON_CANONICAL_ARTIFACT_SET_V1.md": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"},
        "plan_controls": {"PROFILE_RUNTIME_V3"}
    },
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/ANALYSIS_EXECUTION_QUALIFICATION_BINDING_V1.md": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/programming_simple_executor/test_programming_failure_route_separation_v1.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
    "sandbox/lf_contract_gate_test/s30_engineering_checkpoint_mcp/test_ci_applicability.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"},
        "plan_controls": {"S30_BOUNDED_REGRESSION"}
    },
    "sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/build_external_baseline_delta_v1.py": {
        "mode": "CI_ROUTER_SELFTEST_ONLY", "controls": {"CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE"}
    },
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
                    self.assertTrue(expected.get("plan_controls", set()).issubset(set(plan["required_controls"])), path)
                finally:
                    git(ROOT, "worktree", "remove", "--force", str(candidate))


if __name__ == "__main__":
    unittest.main(verbosity=2)
