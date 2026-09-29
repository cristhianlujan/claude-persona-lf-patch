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

assert ordinary_pr == ["lf-contract-check.yml"], ordinary_pr
assert trusted_pr == ["lf-github-reconcile-v3.yml"], trusted_pr

entrypoint = read("lf-contract-check.yml")
assert entrypoint.startswith("name: lf-contract-check\n")
assert "  lf-pase:\n" in entrypoint
assert "Build canonical PASE applicability and repair-enforcement plan" in entrypoint
assert "PASE_CONTROL_REPAIR_QUARANTINE_V1" in entrypoint

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

reconcile = read("lf-github-reconcile-v3.yml")
assert 'workflows: ["lf-contract-check"]' in reconcile
assert PULL_REQUEST_TARGET.search(reconcile)

print(
    "PASS_PASE_SINGLE_PR_ENTRYPOINT_V1 "
    f"workflow_count={len(files)} ordinary_pr={ordinary_pr[0]} "
    f"independent_guardian={trusted_pr[0]}"
)
