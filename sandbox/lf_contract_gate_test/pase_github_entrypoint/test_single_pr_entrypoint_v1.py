#!/usr/bin/env python3
from __future__ import annotations

import re
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"
ALLOWLIST = Path(__file__).with_name("auxiliary_pr_workflows_v1.json")

PULL_REQUEST = re.compile(r"^  pull_request:\s*$", re.MULTILINE)
PULL_REQUEST_TARGET = re.compile(r"^  pull_request_target:\s*$", re.MULTILINE)
EXPECTED_TRUSTED_PR = sorted(
    [
        "lf-ig-runtime-candidate-judge.yml",
        "lf-independent-change-admission.yml",
        "lf-migration-merge-train.yml",
        "lf-migration-route-guard.yml",
        "pase-merge-gate.yml",
    ]
)


def read(name: str) -> str:
    path = WORKFLOWS / name
    if not path.is_file():
        raise AssertionError(f"missing workflow: {name}")
    return path.read_text(encoding="utf-8")


def load_auxiliary_allowlist(path: Path) -> list[str]:
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document.get("schema_version") == "pase-auxiliary-pr-workflows/v1"
    entries = document.get("workflows")
    assert isinstance(entries, list), "allowlist workflows must be a list"
    names: list[str] = []
    for entry in entries:
        assert isinstance(entry, dict), f"invalid allowlist entry: {entry!r}"
        name = entry.get("name")
        owner = entry.get("owner")
        reason = entry.get("reason")
        assert isinstance(name, str) and name.endswith((".yml", ".yaml")), entry
        assert isinstance(owner, str) and owner.strip(), entry
        assert isinstance(reason, str) and reason.strip(), entry
        names.append(name)
    assert len(names) == len(set(names)), "duplicate auxiliary workflow in allowlist"
    return names


def validate_ordinary_workflows(workflows_dir: Path, allowlist_names: list[str]) -> list[str]:
    files = sorted([*workflows_dir.glob("*.yml"), *workflows_dir.glob("*.yaml")])
    ordinary_pr = sorted(
        path.name
        for path in files
        if PULL_REQUEST.search(path.read_text(encoding="utf-8"))
    )
    allowed = sorted(["pase.yml", *allowlist_names])
    missing = sorted(set(allowlist_names) - {path.name for path in files})
    if missing:
        raise AssertionError(f"allowlisted workflow no longer exists: {missing}")
    if ordinary_pr != allowed:
        unlisted = sorted(set(ordinary_pr) - set(allowed))
        stale = sorted(set(allowed) - set(ordinary_pr))
        raise AssertionError(
            f"ordinary pull_request workflows differ: unlisted={unlisted}; missing_or_stale={stale}"
        )
    return ordinary_pr


def exercise_allowlist_regressions() -> None:
    """Prove unexpected and stale allowlist entries are rejected."""
    with tempfile.TemporaryDirectory(prefix="pase-entrypoint-") as temporary:
        workflows = Path(temporary) / "workflows"
        workflows.mkdir()
        (workflows / "pase.yml").write_text("on:\n  pull_request:\n", encoding="utf-8")
        (workflows / "aux.yml").write_text("on:\n  pull_request:\n", encoding="utf-8")
        assert validate_ordinary_workflows(workflows, ["aux.yml"]) == ["aux.yml", "pase.yml"]

        (workflows / "new-ordinary.yml").write_text(
            "on:\n  pull_request:\n", encoding="utf-8"
        )
        try:
            validate_ordinary_workflows(workflows, ["aux.yml"])
        except AssertionError as exc:
            assert "new-ordinary.yml" in str(exc)
        else:
            raise AssertionError("unlisted ordinary workflow was accepted")
        (workflows / "new-ordinary.yml").unlink()

        try:
            validate_ordinary_workflows(workflows, ["aux.yml", "removed.yml"])
        except AssertionError as exc:
            assert "removed.yml" in str(exc)
        else:
            raise AssertionError("stale allowlist entry was accepted")


files = sorted([*WORKFLOWS.glob("*.yml"), *WORKFLOWS.glob("*.yaml")])
ordinary_pr = []
trusted_pr = []
for path in files:
    text = path.read_text(encoding="utf-8")
    if PULL_REQUEST.search(text):
        ordinary_pr.append(path.name)
    if PULL_REQUEST_TARGET.search(text):
        trusted_pr.append(path.name)

allowlist_names = load_auxiliary_allowlist(ALLOWLIST)
assert validate_ordinary_workflows(WORKFLOWS, allowlist_names) == ordinary_pr
assert "pase.yml" not in allowlist_names, "canonical entrypoint cannot be an auxiliary"
exercise_allowlist_regressions()
assert trusted_pr == EXPECTED_TRUSTED_PR, trusted_pr

entrypoint = read("pase.yml")
assert entrypoint.startswith("name: PASE\n")
assert "  workflow_call:\n" in entrypoint
assert "  push:\n" in entrypoint
assert "    branches:\n      - main\n" in entrypoint
assert "  pull_request:\n" in entrypoint
assert "  lf-pase:\n" in entrypoint
assert "    name: PASE\n" in entrypoint
assert "Build canonical PASE applicability and repair-enforcement plan" in entrypoint
assert "PASE_CONTROL_REPAIR_QUARANTINE_V1" in entrypoint

legacy = read("lf-contract-check.yml")
assert legacy.startswith("name: lf-contract-check\n")
assert not PULL_REQUEST.search(legacy)
assert "  workflow_dispatch:\n" in legacy
assert "  push:\n" not in legacy
assert "uses: ./.github/workflows/pase.yml" in legacy
assert "Build canonical PASE applicability and repair-enforcement plan" not in legacy

# Changeset Governance is the repository-path/admission authority. The canonical
# PASE entrypoint must not invoke the historical Contract Check scope validator
# before the canonical plan because that would pre-empt legitimate owner routing.
assert "Enforce structural repository admission" not in entrypoint
assert "lf_pase_structural_admission" not in entrypoint
assert "validator.validate_changed_files" not in entrypoint
assert "scripts/lf_contract_check.py:structural-admission-only" not in entrypoint
assert "s28_ci_lane_router/emit_ci_execution_plan_v2.py" in entrypoint

# Historical validator and reconciliation carriers retired by cutover stay absent.
assert not (WORKFLOWS / "validate-lf-packs.yml").exists()
assert not (WORKFLOWS / "lf-db-regression.yml").exists()
assert not (WORKFLOWS / "lf-github-reconcile-v3.yml").exists()

# Operational capabilities remain available but cannot create a second ordinary PR entrypoint.
currentness = read("lf-material-currentness.yml")
assert "  workflow_dispatch:\n" in currentness
assert "  workflow_call:\n" in currentness
assert "  evaluate-current:\n" in currentness
assert not PULL_REQUEST.search(currentness)

story = read("story-agent-evidence-verifier.yml")
assert "  push:\n" in story
assert "  verify-agent-task-worker-receipt:\n" in story
assert not PULL_REQUEST.search(story)

profile = read("profile-driven-screen-generation.yml")
assert "  issue_comment:\n" in profile
assert "  s30-owner-chatops-broker:\n" in profile
assert not PULL_REQUEST.search(profile)

merge_gate = read("pase-merge-gate.yml")
assert merge_gate.startswith("name: PASE Merge Gate\n")
assert PULL_REQUEST_TARGET.search(merge_gate)
assert not PULL_REQUEST.search(merge_gate)
assert "Checkout trusted PR base" in merge_gate
assert "github.event.pull_request.base.sha" in merge_gate
assert "Evaluate base-anchored PASE merge gate" in merge_gate
assert "  pase-merge-gate:\n" in merge_gate

# Independent trusted guardians remain separate from the merge-gate workflow.
admission = read("lf-independent-change-admission.yml")
assert PULL_REQUEST_TARGET.search(admission)
assert "independent-change-admission:" in admission
assert "lf_independent_change_admission_carrier_v1.py self-test" in admission
assert "lf_independent_change_admission_carrier_v1.py classify" in admission
assert "lf_independent_change_admission_carrier_v1.py validate" in admission

judge = read("lf-ig-runtime-candidate-judge.yml")
assert PULL_REQUEST_TARGET.search(judge)
assert "ig-runtime-candidate-judge:" in judge
assert "Checkout trusted base judge source" in judge
assert "git diff --quiet \"$BASE_SHA\" \"$HEAD_SHA\" -- \"$REQUEST_PATH\"" in judge
assert "ig_runtime_candidate_judge_request_v1.py self-test" in judge
assert "ig_runtime_candidate_judge_request_v1.py run" in judge
assert 'echo "applicable=false"' in judge
assert 'echo "applicable=true"' in judge
assert "needs.classify-ig-n9-applicability.outputs.applicable == 'true'" in judge

print(
    "PASS_PASE_SINGLE_PR_ENTRYPOINT_V1 "
    f"workflow_count={len(files)} ordinary_pr={','.join(ordinary_pr)} "
    f"trusted_pr={','.join(trusted_pr)}"
)
