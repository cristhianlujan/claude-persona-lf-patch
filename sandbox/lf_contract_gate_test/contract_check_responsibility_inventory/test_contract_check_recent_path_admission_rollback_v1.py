#!/usr/bin/env python3
"""Regression for recent Contract Check path-admission contamination rollback.

This test is intentionally narrow: it proves the Visual Evidence Gate, Pack Validation
core, and Migration Source Parity reusable workflow admissions are not owned by
scripts/lf_contract_check.py. Historical path-admission cleanup is a separate lot.
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
}


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    leaked = sorted(token for token in FORBIDDEN_TOKENS if token in text)
    if leaked:
        raise SystemExit("FAIL_CONTRACT_CHECK_RECENT_PATH_ADMISSION_LEAK:" + ",".join(leaked))
    if "LF Contract Check v0.19" not in text:
        raise SystemExit("FAIL_CONTRACT_CHECK_EXPECTED_PRE_CONTAMINATION_BASELINE")
    print("PASS_CONTRACT_CHECK_RECENT_PATH_ADMISSION_ROLLBACK=9/9")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
