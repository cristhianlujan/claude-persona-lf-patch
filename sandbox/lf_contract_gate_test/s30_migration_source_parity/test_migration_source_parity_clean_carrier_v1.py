#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py"
CARRIER = ROOT / ".github/workflows/lf-migration-source-parity-core.yml"


def load_runner():
    spec = importlib.util.spec_from_file_location("migration_source_parity_clean_carrier_test_target", RUNNER)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    checks = 0
    module = load_runner()
    if module.self_test() != 0:
        raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_SELFTEST")
    checks += 1

    runner = RUNNER.read_text(encoding="utf-8")
    workflow = CARRIER.read_text(encoding="utf-8")

    forbidden_runner = (
        "required_controls",
        "CI_FAST_DEEP_LANE_ROUTER",
        "LF_CONTRACT_CHECK_DECLARATIVE_CONTROLS",
        "run_gate_groups_v1.py",
        ".github/workflows/lf-contract-check.yml",
    )
    for token in forbidden_runner:
        if token in runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_FOREIGN_TOKEN:{token}")
    checks += 1

    required_runner = (
        "lf_migration_source_parity.py",
        "FAIL_MIGRATION_PARITY_BASE_CURRENTNESS",
        "FAIL_MIGRATION_PARITY_EXACT_HEAD",
        "MIGRATION_OWNER_CURRENTNESS:%",
        "lf-migration-source-parity-run/v1",
        "functional_core_duplicated",
    )
    for token in required_runner:
        if token not in runner:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_REQUIRED_TOKEN:{token}")
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
        "LF_SUPABASE_DB_PASSWORD:",
        "Execute MIGRATION_SOURCE_PARITY",
        "run_migration_source_parity_flow_v1.py",
        'ref: ${{ inputs.head_sha }}',
    ):
        if token not in workflow:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CARRIER_REQUIRED_TOKEN:{token}")
    checks += 1

    forbidden_workflow = (
        "lf-contract-check.yml",
        "validate-lf-packs.yml",
        "required_controls",
        "LF_CONTRACT_CHECK",
        "CI_FAST_DEEP_LANE_ROUTER",
    )
    for token in forbidden_workflow:
        if token in workflow:
            raise SystemExit(f"FAIL_MIGRATION_SOURCE_PARITY_CARRIER_FOREIGN_TOKEN:{token}")
    checks += 1

    print(f"PASS_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
