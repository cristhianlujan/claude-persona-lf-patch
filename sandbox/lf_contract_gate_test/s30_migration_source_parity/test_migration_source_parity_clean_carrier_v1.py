#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FULL_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py"
FOCAL_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_focal_v1.py"
PASE_ENTRY = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_pase_entry_v1.py"
CARRIER = ROOT / ".github/workflows/lf-migration-source-parity-core.yml"


def load_runner(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    checks = 0

    full = load_runner(FULL_RUNNER, "migration_source_parity_full_audit_test_target")
    if full.self_test() != 0:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_FULL_AUDIT_SELFTEST")
    checks += 1

    focal = load_runner(FOCAL_RUNNER, "migration_source_parity_focal_test_target")
    if focal.self_test() != 0:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_FOCAL_SELFTEST")
    checks += 1

    pase_entry = load_runner(PASE_ENTRY, "migration_source_parity_pase_entry_test_target")
    if pase_entry.self_test() != 0:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_PASE_ENTRY_SELFTEST")
    checks += 1

    full_runner = FULL_RUNNER.read_text(encoding="utf-8")
    focal_runner = FOCAL_RUNNER.read_text(encoding="utf-8")
    entry_runner = PASE_ENTRY.read_text(encoding="utf-8")
    workflow = CARRIER.read_text(encoding="utf-8")

    forbidden_runner = (
        "required_controls",
        "CI_FAST_DEEP_LANE_ROUTER",
        "LF_CONTRACT_CHECK_DECLARATIVE_CONTROLS",
        "run_gate_groups_v1.py",
        ".github/workflows/lf-contract-check.yml",
    )
    for token in forbidden_runner:
        if token in full_runner or token in focal_runner or token in entry_runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_FOREIGN_TOKEN:{token}")
    checks += 1

    for token in (
        "lf_migration_source_parity.py",
        "FAIL_MIGRATION_PARITY_BASE_CURRENTNESS",
        "FAIL_MIGRATION_PARITY_EXACT_HEAD",
        "MIGRATION_OWNER_CURRENTNESS:%",
        "lf-migration-source-parity-run/v1",
        "functional_core_duplicated",
    ):
        if token not in full_runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_FULL_AUDIT_REQUIRED_TOKEN:{token}")
    checks += 1

    for token in (
        "PASE_EVALUATION_SCOPE_POLICY_V1",
        "PASE-CONTEXT-AWARE-EVALUATION-NO-HISTORICAL-DRAG-001",
        "CHANGESET_SCOPED",
        "RECONCILIATION_WORK_ITEM",
        "NO_UNBOUNDED_HISTORICAL_SCAN_IN_CRITICAL_PATH",
        "REQUIRED_BOUNDED_AGGREGATE",
        "FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS",
    ):
        if token not in focal_runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_FOCAL_REQUIRED_TOKEN:{token}")
    checks += 1

    for token in (
        "_expected_live_ref_sha",
        'event_name == "push"',
        "FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS",
        "refs/remotes/origin/",
        "FAIL_MIGRATION_PARITY_BASE_NOT_ANCESTOR",
        "pull_request",
        "workflow_dispatch",
    ):
        if token not in entry_runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_PASE_ENTRY_REQUIRED_TOKEN:{token}")
    checks += 1

    if "workflow_call:" not in workflow:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CARRIER_NOT_REUSABLE")
    if "pull_request:" in workflow or "\npush:" in workflow or "workflow_dispatch:" in workflow:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CARRIER_HAS_DIRECT_TRIGGER")
    checks += 1

    for token in (
        "base_sha:",
        "head_sha:",
        "base_ref:",
        "control_maturity:",
        'default: "CUTOVER"',
        "evaluation_scope:",
        'default: "CHANGESET_SCOPED"',
        "historical_debt_disposition:",
        'default: "RECONCILIATION_WORK_ITEM"',
        "LF_SUPABASE_DB_PASSWORD:",
        "Execute MIGRATION_SOURCE_PARITY",
        "run_migration_source_parity_pase_entry_v1.py",
        "--control-maturity",
        "--evaluation-scope",
        "--historical-debt-disposition",
        'ref: ${{ inputs.head_sha }}',
    ):
        if token not in workflow:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CARRIER_REQUIRED_TOKEN:{token}")
    if "run_migration_source_parity_flow_v1.py" in workflow:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CARRIER_BROAD_SCAN_RUNNER_ACTIVE")
    checks += 1

    for token in (
        "lf-contract-check.yml",
        "validate-lf-packs.yml",
        "required_controls",
        "LF_CONTRACT_CHECK",
        "CI_FAST_DEEP_LANE_ROUTER",
    ):
        if token in workflow:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CARRIER_FOREIGN_TOKEN:{token}")
    checks += 1

    print(f"PASS_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
