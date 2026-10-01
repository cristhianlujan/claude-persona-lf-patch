#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"

PULL_REQUEST = re.compile(r"^  pull_request:\s*$", re.MULTILINE)
PULL_REQUEST_TARGET = re.compile(r"^  pull_request_target:\s*$", re.MULTILINE)


def read(name: str) -> str:
    path = WORKFLOWS / name
    if not path.is_file():
        raise AssertionError(f"missing workflow: {name}")
    return path.read_text(encoding="utf-8")


files = sorted([*WORKFLOWS.glob("*.yml"), *WORKFLOWS.glob("*.yaml")])
ordinary_pr = []
trusted_pr = []
for path in files:
    text = path.read_text(encoding="utf-8")
    if PULL_REQUEST.search(text):
        ordinary_pr.append(path.name)
    if PULL_REQUEST_TARGET.search(text):
        trusted_pr.append(path.name)

assert ordinary_pr == ["pase.yml"], ordinary_pr
assert trusted_pr == ["pase-merge-gate.yml"], trusted_pr

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

# Historical validator carriers retired by the earlier PASE workflow cutover stay absent.
assert not (WORKFLOWS / "validate-lf-packs.yml").exists()
assert not (WORKFLOWS / "lf-db-regression.yml").exists()

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

# Reconciliation is POST-PASE only: it must no longer own any pre-merge PR admission.
reconciliation = read("lf-github-reconcile-v3.yml")
assert "  workflow_run:\n" in reconciliation
assert not PULL_REQUEST_TARGET.search(reconciliation)
assert not PULL_REQUEST.search(reconciliation)
assert "independent-change-admission:" not in reconciliation

merge_gate = read("pase-merge-gate.yml")
assert merge_gate.startswith("name: PASE Merge Gate\n")
assert PULL_REQUEST_TARGET.search(merge_gate)
assert not PULL_REQUEST.search(merge_gate)
assert "Checkout trusted PR base" in merge_gate
assert "github.event.pull_request.base.sha" in merge_gate
assert "Evaluate base-anchored PASE merge gate" in merge_gate
assert "independent-change-admission:" in merge_gate
assert "lf_independent_change_admission_carrier_v1.py self-test" in merge_gate
assert "lf_independent_change_admission_carrier_v1.py classify" in merge_gate
assert "lf_independent_change_admission_carrier_v1.py validate" in merge_gate

print(
    "PASS_PASE_SINGLE_PR_ENTRYPOINT_V1 "
    f"workflow_count={len(files)} ordinary_pr={ordinary_pr[0]} "
    f"trusted_pr={','.join(trusted_pr)}"
)
