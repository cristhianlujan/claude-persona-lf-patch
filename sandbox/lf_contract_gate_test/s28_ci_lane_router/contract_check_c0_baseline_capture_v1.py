#!/usr/bin/env python3
"""C0 demonstrable baseline capture for GITHUB_CONTRACT_GATE_LF.

The capture replays the exact pre-restructure main commit in a detached worktree,
records observable routing/planning behavior, and binds it to exact Git blobs and
a real historical lf-contract-check applicability artifact.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

BASELINE_COMMIT = "1f179dfb76741e3c96f921cf64c07533dd082bad"
HISTORICAL_PLAN_FILE = Path(__file__).with_name("contract_check_c0_historical_plan_36007475239.json")
EXPECTED_FILE = Path(__file__).with_name("contract_check_c0_baseline_expected_v1.json")

SOURCE_PATHS = (
    ".github/workflows/lf-contract-check.yml",
    "scripts/lf_contract_check.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_execution_plan_v2.py",
)


def run(argv: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, cwd=cwd, text=True, capture_output=True, check=check)


def git_text(*args: str) -> str:
    return run(["git", *args]).stdout.strip()


def git_bytes(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


def assert_frozen_main() -> str:
    """Require the frozen baseline to remain reachable from the current canonical main."""
    run(["git", "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"])
    for ref in ("refs/remotes/origin/main", "refs/heads/main"):
        completed = run(["git", "rev-parse", "--verify", ref], check=False)
        if completed.returncode != 0:
            continue
        ancestor = run(["git", "merge-base", "--is-ancestor", BASELINE_COMMIT, ref], check=False)
        if ancestor.returncode != 0:
            resolved = completed.stdout.strip()
            raise SystemExit(f"FAIL_C0_FROZEN_BASELINE_NOT_ANCESTOR_OF_CURRENT_MAIN:{ref}:{resolved}")
        return ref
    raise SystemExit("FAIL_C0_MAIN_REF_UNRESOLVABLE")


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL_C0_MODULE_LOAD:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def make_repo(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="lf-c0-plan-"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def plan_projection(plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "coverage_complete": plan["coverage_complete"],
        "full_regression": plan["full_regression"],
        "full_regression_reason": plan["full_regression_reason"],
        "carrier_regression": plan["carrier_regression"],
        "carrier_regression_reason": plan["carrier_regression_reason"],
        "carrier_regression_carriers": plan["carrier_regression_carriers"],
        "required_controls": plan["required_controls"],
        "required_control_reasons": plan["required_control_reasons"],
        "carrier_controls": plan["carrier_controls"],
    }


def capture_router(router) -> dict[str, Any]:
    cases = {
        "migration_only": ["supabase/migrations/20260909010101_lf_example.sql"],
        "input_governance_migration": ["supabase/migrations/20260909010102_input_governance_example.sql"],
        "workflow_self_change": [".github/workflows/lf-contract-check.yml"],
        "validator_self_change": ["scripts/lf_contract_check.py"],
        "profile_shared": ["profiles/quality_pack/SKILL.md"],
        "p0_external": ["supabase/config.toml"],
        "unknown_surface": ["mystery/new_surface.xyz"],
        "empty_change": [],
    }
    return {name: router.classify(paths).to_dict() for name, paths in cases.items()}


def capture_plans(plan_module) -> dict[str, Any]:
    out: dict[str, Any] = {}

    path = "supabase/migrations/20260918042000_s30_operation_policy_context_v1.sql"
    repo = make_repo({path: "create or replace view public.v_lf_operation_policy_snapshot as select 1;"})
    out["policy_migration"] = plan_projection(plan_module.build_plan(
        changed_paths=[path], lane_required_controls=(), lane_mode="SPECIALIZED_REQUIRED", repo_root=repo
    ))

    path = "profiles/quality_pack/SKILL.md"
    repo = make_repo({path: "# profile\n"})
    out["profile_change"] = plan_projection(plan_module.build_plan(
        changed_paths=[path], lane_required_controls=(), lane_mode="DEEP_SHARED_KNOWN", repo_root=repo
    ))

    path = "mystery/new_surface.xyz"
    repo = make_repo({path: "x\n"})
    out["unknown_fail_closed"] = plan_projection(plan_module.build_plan(
        changed_paths=[path], lane_required_controls=(), lane_mode="DEEP_SHARED_UNKNOWN", repo_root=repo
    ))

    path = ".github/workflows/lf-contract-check.yml"
    repo = make_repo({path: "name: lf-contract-check\n"})
    out["contract_carrier_self_change"] = plan_projection(plan_module.build_plan(
        changed_paths=[path], lane_required_controls=("CI_ROUTER_SELFTEST",), lane_mode="CI_ROUTER_SELFTEST_ONLY", repo_root=repo
    ))

    path = "docs/p0/MATRIZ_OPCIONES_OCR_CV.md"
    repo = make_repo({path: "# evidence\n"})
    out["p0_fast_doc"] = plan_projection(plan_module.build_plan(
        changed_paths=[path], lane_required_controls=(), lane_mode="DEEP_SHARED_KNOWN", repo_root=repo
    ))

    return out


def source_identity() -> dict[str, Any]:
    rows: dict[str, Any] = {}
    for path in SOURCE_PATHS:
        content = git_bytes("show", f"{BASELINE_COMMIT}:{path}")
        rows[path] = {
            "git_blob": git_text("rev-parse", f"{BASELINE_COMMIT}:{path}"),
            "sha256": hashlib.sha256(content).hexdigest(),
            "bytes": len(content),
        }
    return rows


def normalize(value: dict[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(value))
    value.pop("demonstration_sha256", None)
    value.pop("resolved_main_ref", None)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=".lf_gate_diagnostics/lf_contract_check/ci_router_selftest/contract_check_c0_baseline_demonstration_v1.json",
    )
    parser.add_argument("--expected", default=str(EXPECTED_FILE))
    args = parser.parse_args()

    resolved_main_ref = assert_frozen_main()

    historical = json.loads(HISTORICAL_PLAN_FILE.read_text(encoding="utf-8"))
    if historical.get("head_sha") != "fd990b734b1112e465914fd6a1b508c3f7b506e3":
        raise SystemExit("FAIL_C0_HISTORICAL_PLAN_HEAD")
    if historical.get("changed_paths") != ["scripts/lf_contract_check.py"]:
        raise SystemExit("FAIL_C0_HISTORICAL_PLAN_CHANGED_PATH")
    if historical.get("required_controls") != ["CI_ROUTER_SELFTEST", "LF_CONTRACT_CORE", "LF_VALIDATION_ENGINE"]:
        raise SystemExit("FAIL_C0_HISTORICAL_PLAN_CONTROLS")

    identities = source_identity()
    script_sha = identities["scripts/lf_contract_check.py"]["sha256"]
    historical_material = historical.get("material_evidence") or []
    if len(historical_material) != 1 or historical_material[0].get("sha256") != script_sha:
        raise SystemExit("FAIL_C0_HISTORICAL_PLAN_SCRIPT_CONTENT_MISMATCH")

    with tempfile.TemporaryDirectory(prefix="lf-contract-c0-") as td:
        worktree = Path(td) / "baseline"
        run(["git", "worktree", "add", "--detach", str(worktree), BASELINE_COMMIT])
        try:
            router_test = run([
                sys.executable,
                "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py",
            ], cwd=worktree)
            plan_test = run([
                sys.executable,
                "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_execution_plan_v2.py",
            ], cwd=worktree)

            router_dir = worktree / "sandbox/lf_contract_gate_test/s28_ci_lane_router"
            router = load_module(router_dir / "lf_ci_lane_router.py", "lf_c0_baseline_router")
            plan_module = load_module(router_dir / "lf_ci_execution_plan_v2.py", "lf_c0_baseline_plan")
            router_cases = capture_router(router)
            plan_cases = capture_plans(plan_module)
        finally:
            run(["git", "worktree", "remove", "--force", str(worktree)], check=False)

    if "CI_LANE_ROUTER_REGRESSIONS_PASS=39/39" not in router_test.stdout:
        raise SystemExit("FAIL_C0_ROUTER_REGRESSION_REPLAY")
    if "CI_REQUIRED_CONTROLS_SHADOW_PASS=10/10" not in router_test.stdout:
        raise SystemExit("FAIL_C0_ROUTER_REQUIRED_CONTROLS_REPLAY")
    if "LF_CI_EXECUTION_PLAN_V2_PASS=18/18" not in plan_test.stdout:
        raise SystemExit("FAIL_C0_PLAN_REGRESSION_REPLAY")

    demonstration: dict[str, Any] = {
        "schema_version": "lf-contract-check-c0-baseline/v1",
        "baseline_commit": BASELINE_COMMIT,
        "baseline_main_ref": "main",
        "resolved_main_ref": resolved_main_ref,
        "source_identity": identities,
        "representative_router_cases": router_cases,
        "representative_plan_cases": plan_cases,
        "replay_receipts": {
            "router_regressions_stdout": [line for line in router_test.stdout.splitlines() if line.strip()],
            "execution_plan_stdout": [line for line in plan_test.stdout.splitlines() if line.strip()],
        },
        "historical_real_run": {
            "pr_number": 1057,
            "candidate_head_sha": "fd990b734b1112e465914fd6a1b508c3f7b506e3",
            "merge_commit_sha": BASELINE_COMMIT,
            "lf_contract_check_run_id": 36007475239,
            "lf_contract_check_job_id": 107659318606,
            "applicability_artifact_id": 10811146908,
            "applicability_artifact_digest": "sha256:5dd4f178fb384881a874c62e3f5b94df8b266924ae6c0ed517a6ef3423264804",
            "applicability_plan": historical,
        },
    }
    raw = json.dumps(demonstration, sort_keys=True, separators=(",", ":")).encode("utf-8")
    demonstration["demonstration_sha256"] = hashlib.sha256(raw).hexdigest()

    expected_path = Path(args.expected)
    if expected_path.exists():
        expected = json.loads(expected_path.read_text(encoding="utf-8"))
        if normalize(expected) != normalize(demonstration):
            raise SystemExit("FAIL_C0_BASELINE_REPLAY_DIFFERS_FROM_FROZEN_EXPECTED")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(demonstration, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    for name, decision in router_cases.items():
        print(
            "C0_ROUTER_CASE "
            f"id={name} mode={decision['mode']} required_controls={json.dumps(decision['required_controls'], separators=(',', ':'))} "
            f"deep_shared={str(decision['deep_shared']).lower()}"
        )
    for name, plan in plan_cases.items():
        print(
            "C0_PLAN_CASE "
            f"id={name} full_regression={str(plan['full_regression']).lower()} "
            f"carrier_regression={str(plan['carrier_regression']).lower()} "
            f"required_controls={json.dumps(plan['required_controls'], separators=(',', ':'))}"
        )
    print(f"C0_BASELINE_MAIN_REF={resolved_main_ref}")
    print(f"C0_BASELINE_DEMONSTRATION_SHA256={demonstration['demonstration_sha256']}")
    print(f"C0_BASELINE_EVIDENCE={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
