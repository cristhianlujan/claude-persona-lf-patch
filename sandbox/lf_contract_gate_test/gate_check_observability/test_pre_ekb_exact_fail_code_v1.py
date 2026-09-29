#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("persist_gate_failures_to_ekb_v1.py")
spec = importlib.util.spec_from_file_location("pre_ekb_exact_fail", MODULE_PATH)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def candidate(error_class: str, summary: str, rc: int = 1) -> dict:
    return module.payload_from_failure(
        gate_id="MIGRATION_SOURCE_PARITY",
        owner="GITHUB_CONTRACT_GATE_LF",
        group_id="MIGRATION_CONTROL",
        check={
            "check_id": "CHECK-007",
            "source_path": "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
            "error_class": error_class,
            "error_summary": summary,
            "rc": rc,
            "source_commit": "a" * 40,
            "tested_commit": "a" * 40,
        },
        run_id="35864000000",
        job_id="lf-contract-check",
        report_ref=".lf_gate_diagnostics/migration/report.json",
    )


def main() -> int:
    direct = candidate("FAIL_LF_MIGRATION_SOURCE_FIRST_SCOPE", "FAIL_LF_MIGRATION_SOURCE_FIRST_SCOPE: expected one migration")
    assert direct["codigo"] == "FAIL_LF_MIGRATION_SOURCE_FIRST_SCOPE"

    fallback = candidate("PROCESS_EXIT_NONZERO", "FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260923000000']", 2)
    assert fallback["codigo"] == "FAIL_LF_MIGRATION_VERSION_PARITY"
    evidence = json.loads(fallback["evidencia"])
    assert evidence["rc"] == 2
    assert evidence["run_id"] == "35864000000"
    assert evidence["job_id"] == "lf-contract-check"
    assert evidence["check_id"] == "CHECK-007"
    assert evidence["raw_error_class"] == "PROCESS_EXIT_NONZERO"

    generic = candidate("AssertionError", "AssertionError: fixture mismatch")
    assert generic["codigo"].startswith("CI-GATE-MIGRATION-CONTROL-")
    assert generic["codigo"] != "AssertionError"

    print("PASS_PRE_EKB_EXACT_FAIL_CODE=3/3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
