#!/usr/bin/env python3
"""Regression for Contract Check repository-admission cleanup.

This test proves repository `.github` path admission is no longer owned by
scripts/lf_contract_check.py. Changeset Governance owns that boundary; Contract
Check retains only its contract, receipt and non-GitHub scope responsibilities.
"""
from pathlib import Path

SOURCE = Path("scripts/lf_contract_check.py")

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


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    leaked = sorted(token for token in FORBIDDEN_TOKENS if token in text)
    if leaked:
        raise SystemExit("FAIL_CONTRACT_CHECK_GITHUB_ADMISSION_OWNERSHIP_LEAK:" + ",".join(leaked))
    if "LF Contract Check v0.20" not in text:
        raise SystemExit("FAIL_CONTRACT_CHECK_EXPECTED_GITHUB_CLEAN_BASELINE")
    print("PASS_CONTRACT_CHECK_GITHUB_ADMISSION_REMOVAL=16/16")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
