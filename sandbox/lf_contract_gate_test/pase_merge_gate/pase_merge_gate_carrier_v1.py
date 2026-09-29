#!/usr/bin/env python3
"""Base-anchored shadow carrier for PASE_MERGE_GATE_V1.

The carrier runs only trusted base-branch code. Candidate Git objects are read as
data for diff/applicability; candidate Python/workflow code is never imported or
executed. External ruleset enforcement is deliberately out of scope here.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
S28 = HERE.parent / "s28_ci_lane_router"
ROUTE_PATH = S28 / "lf_pase_merge_route_v1.py"
GATE_PATH = HERE / "pase_merge_gate_v1.py"
EMITTER_PATH = S28 / "emit_ci_execution_plan_v2.py"
HEX40 = __import__("re").compile(r"^[0-9a-f]{40}$")
RESULT_SCHEMA = "lf-pase-merge-gate-carrier-result/v1"


class CarrierError(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str = "") -> None:
    raise CarrierError(code, detail)


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        _fail("BLOCK_PASE_MERGE_GATE_TRUSTED_MODULE_LOAD", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ROUTE = _load(ROUTE_PATH, "lf_pase_merge_route_v1_carrier")
GATE = _load(GATE_PATH, "pase_merge_gate_v1_carrier")


def _sha40(value: str, code: str) -> str:
    if not isinstance(value, str) or HEX40.fullmatch(value) is None:
        _fail(code, str(value))
    return value


def validate_identity(*, repository: str, head_repository: str, base_sha: str, head_sha: str, current_main_sha: str, trusted_checkout_sha: str) -> None:
    if not repository or head_repository != repository:
        _fail("BLOCK_PASE_MERGE_GATE_HEAD_REPOSITORY", f"repository={repository} head_repository={head_repository}")
    base_sha = _sha40(base_sha, "BLOCK_PASE_MERGE_GATE_BASE_SHA")
    head_sha = _sha40(head_sha, "BLOCK_PASE_MERGE_GATE_HEAD_SHA")
    current_main_sha = _sha40(current_main_sha, "BLOCK_PASE_MERGE_GATE_CURRENT_MAIN_SHA")
    trusted_checkout_sha = _sha40(trusted_checkout_sha, "BLOCK_PASE_MERGE_GATE_TRUSTED_CHECKOUT_SHA")
    if base_sha != current_main_sha:
        _fail("BLOCK_PASE_MERGE_GATE_STALE_BASE", f"base={base_sha} current_main={current_main_sha}")
    if trusted_checkout_sha != base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_UNTRUSTED_CHECKOUT", f"checkout={trusted_checkout_sha} base={base_sha}")
    if head_sha == base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_EMPTY_RANGE")


def evaluate_plan(*, plan: Mapping[str, Any], head_sha: str) -> dict[str, Any]:
    if not isinstance(plan, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_PLAN_SHAPE")
    if plan.get("head_sha") not in (None, head_sha):
        _fail("BLOCK_PASE_MERGE_GATE_PLAN_HEAD_DRIFT", f"plan={plan.get('head_sha')} expected={head_sha}")
    changed_paths = plan.get("changed_paths")
    enforcement = plan.get("pase_control_enforcement")
    if not isinstance(changed_paths, list) or not changed_paths:
        _fail("BLOCK_PASE_MERGE_GATE_CHANGED_PATHS")
    if not isinstance(enforcement, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_ENFORCEMENT_MISSING")

    route = ROUTE.build_merge_route(
        plan=plan,
        enforcement=enforcement,
        head_sha=head_sha,
        changed_paths=changed_paths,
    )
    packet = {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": head_sha,
        "route": route,
        "plan": plan,
        "enforcement": enforcement,
        # Shadow carrier does not invent qualification or domain-control evidence.
        "qualification": None,
        "control_results": [],
        "diagnostic_results": [],
    }
    try:
        gate_result = GATE.evaluate_merge_gate(packet)
    except GATE.PaseMergeGateError as exc:
        _fail("BLOCK_PASE_MERGE_GATE_POLICY", str(exc))
    return {
        "schema_version": RESULT_SCHEMA,
        "carrier": "PASE_MERGE_GATE_CARRIER_V1",
        "status": "PASS",
        "head_sha": head_sha,
        "mode": route["mode"],
        "candidate_id": route.get("candidate_id"),
        "required_control_ids": route["required_control_ids"],
        "gate_result": gate_result,
        "candidate_code_executed": False,
        "external_enforcement_active": False,
    }


def build_live_plan(*, repo_root: Path, base_sha: str, head_sha: str, current_main_sha: str) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="lf-pase-merge-gate-") as td:
        out = Path(td) / "plan.json"
        cmd = [
            sys.executable,
            str(EMITTER_PATH),
            "--repo-root", str(repo_root),
            "--base", base_sha,
            "--head", head_sha,
            "--authority-current-revision", current_main_sha,
            "--event-name", "pull_request",
            "--ref-name", "main",
            "--output-json", str(out),
        ]
        completed = subprocess.run(cmd, cwd=repo_root, text=True, capture_output=True, check=False)
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip().replace("\n", " | ")[:700]
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_EMIT", detail)
        try:
            plan = json.loads(out.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_READ", type(exc).__name__)
        if not isinstance(plan, Mapping):
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_SHAPE")
        return dict(plan)


def self_test() -> dict[str, Any]:
    checks = 0
    head = "b" * 40
    base = "a" * 40
    validate_identity(repository="r/x", head_repository="r/x", base_sha=base, head_sha=head, current_main_sha=base, trusted_checkout_sha=base)
    checks += 1

    def enforcement(required: list[str], blocking: list[str]) -> dict[str, Any]:
        observe = sorted(set(required) - set(blocking))
        value = {
            "schema_version": "lf-pase-control-enforcement/v1",
            "authority": "CHANGESET_GOVERNANCE_LF_V1",
            "policy_id": "PASE_CONTROL_REPAIR_QUARANTINE_V1",
            "source_plan_sha256": "c" * 64,
            "required_controls": sorted(required),
            "blocking_controls": sorted(blocking),
            "observe_only_controls": observe,
            "repair_window_active": True,
            "manual_diagnostic_execution_allowed": True,
            "observe_only_results_cannot_block_merge": True,
            "no_applicability_reclassification": True,
            "structural_governance_fail_closed": True,
            "silent_reactivation_forbidden": True,
        }
        value["result_sha256"] = ROUTE._sha256(value)
        return value

    normal = {
        "schema_version": "lf-ci-execution-plan/v2",
        "coverage_complete": True,
        "required_controls": ["OBSERVE_ONLY"],
        "plan_sha256": "c" * 64,
        "head_sha": head,
        "changed_paths": ["docs/pase-shadow-probe.md"],
    }
    normal["pase_control_enforcement"] = enforcement(normal["required_controls"], [])
    got = evaluate_plan(plan=normal, head_sha=head)
    assert got["status"] == "PASS" and got["mode"] == "EXECUTION_PLAN" and got["candidate_code_executed"] is False
    checks += 1

    control_change = dict(normal)
    control_change["changed_paths"] = [".github/workflows/pase-merge-gate.yml"]
    try:
        evaluate_plan(plan=control_change, head_sha=head)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_POLICY" and "QUALIFICATION_MISSING" in exc.detail
        checks += 1
    else:
        raise AssertionError("control-system change must fail closed without independent qualification")

    blocker = dict(normal)
    blocker["required_controls"] = ["ACTIVE_BLOCKER"]
    blocker["pase_control_enforcement"] = enforcement(blocker["required_controls"], blocker["required_controls"])
    try:
        evaluate_plan(plan=blocker, head_sha=head)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_POLICY" and "CONTROL_RESULT_COVERAGE" in exc.detail
        checks += 1
    else:
        raise AssertionError("active blocker must fail closed without canonical PASS evidence")

    try:
        validate_identity(repository="r/x", head_repository="r/x", base_sha=base, head_sha=head, current_main_sha="d" * 40, trusted_checkout_sha=base)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_STALE_BASE"
        checks += 1
    else:
        raise AssertionError("stale base must block")

    return {"status": "PASS_PASE_MERGE_GATE_CARRIER_V1", "checks": checks}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test")
    ev = sub.add_parser("evaluate")
    ev.add_argument("--repo-root", type=Path, default=Path("."))
    ev.add_argument("--repository", required=True)
    ev.add_argument("--head-repository", required=True)
    ev.add_argument("--base-sha", required=True)
    ev.add_argument("--head-sha", required=True)
    ev.add_argument("--current-main-sha", required=True)
    ev.add_argument("--output-json", required=True, type=Path)
    ns = ap.parse_args()
    try:
        if ns.command == "self-test":
            result = self_test()
        else:
            root = ns.repo_root.resolve()
            trusted = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
            validate_identity(
                repository=ns.repository,
                head_repository=ns.head_repository,
                base_sha=ns.base_sha,
                head_sha=ns.head_sha,
                current_main_sha=ns.current_main_sha,
                trusted_checkout_sha=trusted,
            )
            plan = build_live_plan(repo_root=root, base_sha=ns.base_sha, head_sha=ns.head_sha, current_main_sha=ns.current_main_sha)
            result = evaluate_plan(plan=plan, head_sha=ns.head_sha)
            result.update({"repository": ns.repository, "base_sha": ns.base_sha, "trusted_checkout_sha": trusted, "current_main_sha": ns.current_main_sha})
            ns.output_json.parent.mkdir(parents=True, exist_ok=True)
            ns.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return 0
    except CarrierError as exc:
        result = {"schema_version": RESULT_SCHEMA, "carrier": "PASE_MERGE_GATE_CARRIER_V1", "status": "BLOCK", "blocking_code": exc.code, "detail": exc.detail, "candidate_code_executed": False, "external_enforcement_active": False}
        if ns.command == "evaluate":
            ns.output_json.parent.mkdir(parents=True, exist_ok=True)
            ns.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
