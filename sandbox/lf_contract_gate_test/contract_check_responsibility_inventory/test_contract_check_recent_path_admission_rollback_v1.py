#!/usr/bin/env python3
"""Regression for Contract Check repository-admission cleanup.

Changeset Governance owns `.github` admission. Contract Check must not carry an
allowlist or decide registered-vs-unregistered GitHub paths; after the upstream
owner runs, its scope validator only checks non-GitHub paths and governed
receipts.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "scripts/lf_contract_check.py"
ADMISSION_SOURCE = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_repository_path_admission.py"

FORBIDDEN_TOKENS = {
    "VISUAL_EVIDENCE_GATE_WORKFLOW_PATH",
    "PACK_VALIDATION_CORE_WORKFLOW_PATH",
    "MIGRATION_SOURCE_PARITY_CORE_WORKFLOW_PATH",
    ".github/workflows/visual-evidence-gate.yml",
    ".github/workflows/lf-pack-validation-core.yml",
    ".github/workflows/lf-migration-source-parity-core.yml",
    "validate_visual_evidence_gate_workflow_admission_scope",
    "validate_pack_validation_core_workflow_admission_scope",
    "validate_migration_source_parity_core_workflow_admission_scope",
    "ALLOWED_GITHUB_EXACT",
    "RETIRED_GITHUB_DELETE_ONLY",
    "FORBIDDEN_GITHUB_PREFIX",
    "PROFILE_CREATOR_CALLER_WORKFLOW_PATH",
    "PROFILE_CREATOR_CALLER_WORKFLOW_DENIED_LOOKALIKES",
    "validate_retired_github_paths",
    "validate_profile_creator_workflow_admission_scope",
}


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL_MODULE_LOAD:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    leaked = sorted(token for token in FORBIDDEN_TOKENS if token in text)
    if leaked:
        raise SystemExit("FAIL_CONTRACT_CHECK_GITHUB_ADMISSION_OWNERSHIP_LEAK:" + ",".join(leaked))
    if "LF Contract Check v0.21" not in text:
        raise SystemExit("FAIL_CONTRACT_CHECK_EXPECTED_GITHUB_DELEGATION_BASELINE")

    contract_check = load_module("contract_check_boundary_regression", SOURCE)
    admission = load_module("repository_path_admission_boundary_regression", ADMISSION_SOURCE)
    policy = admission.load_repository_path_admission()

    canonical_pack = ".github/workflows/lf-pack-validation-core.yml"
    unknown = ".github/workflows/not-registered-by-changeset.yml"

    # Canonical owner distinguishes admitted vs unknown GitHub paths.
    if policy.evaluate(canonical_pack)["verdict"] != "ADMIT":
        raise SystemExit("FAIL_CHANGESET_PACK_WORKFLOW_NOT_ADMITTED")
    if policy.evaluate(unknown)["verdict"] != "BLOCK":
        raise SystemExit("FAIL_CHANGESET_UNKNOWN_GITHUB_NOT_BLOCKED")

    # Contract Check deliberately does not re-decide either GitHub path.
    if contract_check.validate_changed_files([canonical_pack]) != []:
        raise SystemExit("FAIL_CONTRACT_CHECK_PACK_WORKFLOW_NOT_DELEGATED")
    if contract_check.validate_changed_files([unknown]) != []:
        raise SystemExit("FAIL_CONTRACT_CHECK_UNKNOWN_GITHUB_REDECIDED")

    # Non-GitHub scope remains fail-closed.
    try:
        contract_check.validate_changed_files(["unowned/outside-scope.txt"])
    except SystemExit as exc:
        if exc.code != 1:
            raise
    else:
        raise SystemExit("FAIL_CONTRACT_CHECK_NON_GITHUB_SCOPE_WIDENED")

    # Blocked productive prefixes remain blocked before any other scope decision.
    try:
        contract_check.validate_changed_files(["production/unsafe.txt"])
    except SystemExit as exc:
        if exc.code != 1:
            raise
    else:
        raise SystemExit("FAIL_CONTRACT_CHECK_BLOCKED_PREFIX_WIDENED")

    print("PASS_CONTRACT_CHECK_GITHUB_ADMISSION_DELEGATION=22/22")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
