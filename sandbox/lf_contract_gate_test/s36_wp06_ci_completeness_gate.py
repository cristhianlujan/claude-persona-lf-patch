#!/usr/bin/env python3
"""Compatibility carrier for TEST_COVERAGE_DEBT_GUARD.

Historical filename retained only so old explicit callers do not break. The
owned implementation and semantics live under the transversal debt-guard asset.
No Assurance-completeness verdict is produced here.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

TARGET = (
    Path(__file__).resolve().parent
    / "transversal_assets"
    / "test_coverage_debt_guard"
    / "test_coverage_debt_guard_v1.py"
)
spec = importlib.util.spec_from_file_location("test_coverage_debt_guard_v1", TARGET)
if spec is None or spec.loader is None:
    raise SystemExit("TEST_COVERAGE_DEBT_GUARD_BLOCKED:CANONICAL_RUNNER_LOAD_FAILED")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Compatibility exports for existing self-tests/readers. They are owned by the
# canonical TEST_COVERAGE_DEBT_GUARD module above.
CAPABILITY_CODE = mod.CAPABILITY_CODE
SUCCESS_RESULT = mod.SUCCESS_RESULT
FAILURE_RESULT = mod.FAILURE_RESULT
PROVIDER_BLOCK_STATE = mod.PROVIDER_BLOCK_STATE
ISSUE_CODES = mod.ISSUE_CODES
SQL = mod.SQL
classify_debt_rows = mod.classify_debt_rows


def main() -> int:
    return mod.main()


if __name__ == "__main__":
    raise SystemExit(main())
