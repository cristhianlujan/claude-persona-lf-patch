#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


BRIDGE = load(HERE / "lf_ci_currentness_bridge_v1.py", "lf_ci_currentness_bridge_transport_test")
COMPAT = load(HERE / "lf_ci_compatibility_assessment_v1.py", "lf_ci_compatibility_assessment_test")


def sh(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, text=True, capture_output=True
    ).stdout.strip()


def emitter_source(*, lane_mode: str = "FAST") -> str:
    return f'''#!/usr/bin/env python3
import argparse, json
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument("--repo-root"); p.add_argument("--base"); p.add_argument("--head")
p.add_argument("--authority-current-revision"); p.add_argument("--event-name")
p.add_argument("--ref-name"); p.add_argument("--output-json", required=True)
a=p.parse_args()
plan={{
  "lane_mode": "{lane_mode}",
  "full_regression": False,
  "required_controls": ["CI_ROUTER_SELFTEST"],
  "carrier_controls": {{"LF_CONTRACT_CHECK": ["CI_ROUTER_SELFTEST"]}},
  "coverage_complete": True,
  "contract_check_resolution_request": {{"handoff_state": "RESOLVED"}},
  "pase_control_enforcement": {{"blocking_controls": [], "observe_only_controls": []}}
}}
Path(a.output_json).write_text(json.dumps(plan), encoding="utf-8")
'''


def setup_repo(*, drift: bool) -> tuple[Path, str, str, str]:
    repo = Path(tempfile.mkdtemp(prefix="lf-ci-compat-transport-"))
    sh(repo, "init")
    sh(repo, "config", "user.email", "ci@example.invalid")
    sh(repo, "config", "user.name", "CI")
    paths = {
        ".github/workflows/lf-contract-check.yml": "name: contract\n",
        ".github/workflows/validate-lf-packs.yml": "name: packs\n",
        ".github/workflows/lf-db-regression.yml": "name: db\n",
        "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py": "ROUTER_VERSION='v1'\n",
        "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py": emitter_source(),
        "sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py": "print('gates')\n",
        "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md": "# CI\n",
        "feature.txt": "base\n",
    }
    for rel, text in paths.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", "base authority")
    base = sh(repo, "rev-parse", "HEAD")

    sh(repo, "checkout", "-b", "feature")
    (repo / "feature.txt").write_text("candidate\n", encoding="utf-8")
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", "candidate")
    candidate = sh(repo, "rev-parse", "HEAD")

    sh(repo, "checkout", "master")
    router = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    router.write_text("ROUTER_VERSION='v2'\n", encoding="utf-8")
    if drift:
        emitter = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py"
        emitter.write_text(emitter_source(lane_mode="DEEP"), encoding="utf-8")
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", "main authority update")
    current = sh(repo, "rev-parse", "HEAD")
    return repo, base, candidate, current


def test_equivalent_replay_transports_exact_assessment() -> None:
    repo, base, candidate, current = setup_repo(drift=False)
    binding = BRIDGE.build_binding(bound_revision=base, current_revision=current)
    compat = COMPAT.assess_ci_compatibility(
        repo=repo,
        binding_without_assessments=binding,
        diff_base_revision=base,
        candidate_head_revision=candidate,
    )
    assert compat["ready"] is True, compat
    assert compat["reason"] == "BOUNDED_REPLAY_EQUIVALENT", compat
    assert compat["bounded_validation"]["verdict"] == "PASS", compat
    assessment = compat["assessment"]
    assert assessment["change_class"] == "CONTRACT_COMPATIBLE", assessment

    receipt = BRIDGE.evaluate_ci_authority_currentness(
        repo=repo,
        bound_revision=base,
        current_revision=current,
        compatibility_assessments=[assessment],
    )
    assert receipt["ready"] is True, receipt
    assert receipt["decision"] == "CURRENT_REBOUND", receipt
    assert receipt["bounded_validation_required"] is True, receipt


def test_missing_transport_still_fails_closed() -> None:
    repo, base, _candidate, current = setup_repo(drift=False)
    receipt = BRIDGE.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=base, current_revision=current
    )
    assert receipt["ready"] is False, receipt
    assert receipt["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING", receipt


def test_tampered_proof_is_rejected() -> None:
    repo, base, candidate, current = setup_repo(drift=False)
    binding = BRIDGE.build_binding(bound_revision=base, current_revision=current)
    compat = COMPAT.assess_ci_compatibility(
        repo=repo,
        binding_without_assessments=binding,
        diff_base_revision=base,
        candidate_head_revision=candidate,
    )
    bad = dict(compat["assessment"])
    bad["proof_sha256"] = "0" * 64
    receipt = BRIDGE.evaluate_ci_authority_currentness(
        repo=repo,
        bound_revision=base,
        current_revision=current,
        compatibility_assessments=[bad],
    )
    assert receipt["ready"] is False, receipt
    assert receipt["reason"].startswith("COMPATIBILITY_PROOF_CONTEXT_MISMATCH"), receipt


def test_semantic_drift_blocks_assessment() -> None:
    repo, base, candidate, current = setup_repo(drift=True)
    binding = BRIDGE.build_binding(bound_revision=base, current_revision=current)
    compat = COMPAT.assess_ci_compatibility(
        repo=repo,
        binding_without_assessments=binding,
        diff_base_revision=base,
        candidate_head_revision=candidate,
    )
    assert compat["ready"] is False, compat
    assert compat["reason"] == "BOUNDED_REPLAY_SEMANTIC_DRIFT", compat
    assert compat["bounded_validation"]["verdict"] == "FAIL", compat


def main() -> None:
    tests = [
        test_equivalent_replay_transports_exact_assessment,
        test_missing_transport_still_fails_closed,
        test_tampered_proof_is_rejected,
        test_semantic_drift_blocks_assessment,
    ]
    for test in tests:
        test()
    print(f"LF_CI_COMPATIBILITY_ASSESSMENT_TRANSPORT_V1_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
