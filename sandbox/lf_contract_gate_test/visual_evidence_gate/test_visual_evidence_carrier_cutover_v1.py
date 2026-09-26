#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
PLAN_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
VALIDATOR_PATH = ROOT / "scripts/lf_contract_check.py"
WORKFLOW = ROOT / ".github/workflows/visual-evidence-gate.yml"
CONTRACT_WORKFLOW = ROOT / ".github/workflows/lf-contract-check.yml"
CONTROL_ID = "VISUAL_EVIDENCE_GATE"
LEGACY_ID = "P0_VISUAL_RUNTIME"
WORKFLOW_REL = ".github/workflows/visual-evidence-gate.yml"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot_load:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PLAN = load(PLAN_PATH, "visual_cutover_plan")
VALIDATOR = load(VALIDATOR_PATH, "visual_cutover_validator")


def make_repo(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="visual-evidence-cutover-"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def build(path: str, text: str = "x") -> dict:
    return PLAN.build_plan(
        changed_paths=[path],
        lane_required_controls=(),
        lane_mode="DEEP_SHARED_KNOWN",
        repo_root=make_repo({path: text}),
    )


def test_registry_cutover() -> None:
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    rows = {row["control_id"]: row for row in data["controls"]}
    assert LEGACY_ID not in rows
    assert LEGACY_ID not in data["full_regression_controls"]
    assert CONTROL_ID in data["full_regression_controls"]
    row = rows[CONTROL_ID]
    assert row["carrier"] == CONTROL_ID
    matchers = {(item["kind"], item["value"]) for item in row["path_matchers"]}
    assert ("prefix", "sandbox/story_creator_p0_visual/") in matchers
    assert ("prefix", "sandbox/lf_contract_gate_test/story_creator_visual_screen_reading_architecture/") in matchers
    assert ("prefix", "sandbox/lf_contract_gate_test/visual_evidence_gate/") in matchers
    assert ("exact", WORKFLOW_REL) in matchers


def test_visual_change_routes_only_to_visual_carrier() -> None:
    path = "sandbox/story_creator_p0_visual/v1.1/evals/example_visual_case.json"
    got = build(path, "{}\n")
    assert CONTROL_ID in got["required_controls"]
    assert LEGACY_ID not in got["required_controls"]
    assert got["carrier_controls"][CONTROL_ID] == [CONTROL_ID]
    assert CONTROL_ID not in got["carrier_controls"].get("LF_CONTRACT_CHECK", [])


def test_nonvisual_change_does_not_route_to_visual_carrier() -> None:
    path = "profiles/example/SKILL.md"
    got = build(path, "# example\n")
    assert CONTROL_ID not in got["required_controls"]
    assert CONTROL_ID not in got["carrier_controls"]


def test_workflow_self_change_routes_to_visual_carrier() -> None:
    got = build(WORKFLOW_REL, "name: Visual Evidence Gate\n")
    assert CONTROL_ID in got["required_controls"]
    assert got["carrier_controls"][CONTROL_ID] == [CONTROL_ID]


def test_visual_cutover_does_not_self_authorize_github_path() -> None:
    # Path admission is a Changeset Governance responsibility. The visual
    # carrier must not mutate Contract Check's exact workflow allowlist merely
    # to authorize itself.
    assert WORKFLOW_REL not in VALIDATOR.ALLOWED_GITHUB_EXACT
    assert not VALIDATOR.is_allowed_path(WORKFLOW_REL)
    assert ".github/" not in VALIDATOR.ALLOWED_PREFIXES
    for lookalike in (
        WORKFLOW_REL + ".bak",
        ".github/workflows/visual-evidence-gate.yaml",
        ".github/workflows/visual-evidence-gate/child.yml",
        ".github/workflows/visual-evidence-gate-copy.yml",
    ):
        assert lookalike not in VALIDATOR.ALLOWED_GITHUB_EXACT
        assert not VALIDATOR.is_allowed_path(lookalike)


def test_dedicated_workflow_consumes_unified_plan_and_owner() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "emit_ci_execution_plan_v2.py" in text
    assert "carrier_controls" in text
    assert "VISUAL_EVIDENCE_GATE" in text
    assert "visual_evidence_gate_v1.py --self-test" in text
    assert "test_visual_evidence_gate_v1.py" in text
    assert "visual_evidence_gate_v1.py" in text
    assert "lf_contract_check.py" not in text


def test_contract_check_no_longer_owns_visual_control_in_plan() -> None:
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    owned = [row["control_id"] for row in data["controls"] if row["carrier"] == "LF_CONTRACT_CHECK"]
    assert CONTROL_ID not in owned
    assert LEGACY_ID not in owned
    # Historical dead compatibility text may remain until a later cleanup PR,
    # but it cannot be reachable from the canonical plan after this cutover.
    assert CONTRACT_WORKFLOW.is_file()


def main() -> None:
    tests = [
        test_registry_cutover,
        test_visual_change_routes_only_to_visual_carrier,
        test_nonvisual_change_does_not_route_to_visual_carrier,
        test_workflow_self_change_routes_to_visual_carrier,
        test_visual_cutover_does_not_self_authorize_github_path,
        test_dedicated_workflow_consumes_unified_plan_and_owner,
        test_contract_check_no_longer_owns_visual_control_in_plan,
    ]
    for test in tests:
        test()
    print(f"VISUAL_EVIDENCE_CARRIER_CUTOVER_PASS tests={len(tests)}")


if __name__ == "__main__":
    main()
