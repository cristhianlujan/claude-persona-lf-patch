#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_version_order_check.py"
spec = importlib.util.spec_from_file_location("lf_migration_version_order_check", TARGET)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
assert spec.loader is not None
spec.loader.exec_module(module)

PASS = module.PASS
NOT_MONOTONIC = module.FAIL_NOT_MONOTONIC
MULTIPLE = module.FAIL_MULTIPLE


def verdict(paths, main, ledger):
    return module.evaluate(
        paths,
        main_max_version=main,
        ledger_max_version=ledger,
    ).code


def main() -> int:
    # PR without migrations -> direct PASS.
    assert verdict([], "20261005190000", "20261005193000") == PASS

    # Lower than main, while main is the effective floor.
    assert verdict(
        ["supabase/migrations/20261005189959_lower_main.sql"],
        "20261005190000",
        "20261005185000",
    ) == NOT_MONOTONIC

    # Lower than ledger, while ledger is the effective floor.
    assert verdict(
        ["supabase/migrations/20261005192959_lower_ledger.sql"],
        "20261005190000",
        "20261005193000",
    ) == NOT_MONOTONIC

    # Equal to the effective max is not strictly monotonic.
    assert verdict(
        ["supabase/migrations/20261005193000_equal.sql"],
        "20261005190000",
        "20261005193000",
    ) == NOT_MONOTONIC

    # Strictly greater than both surfaces -> PASS.
    assert verdict(
        ["supabase/migrations/20261005193001_greater.sql"],
        "20261005190000",
        "20261005193000",
    ) == PASS

    # More than one new migration in the same PR is rejected before ordering.
    assert verdict(
        [
            "supabase/migrations/20261005193001_first.sql",
            "supabase/migrations/20261005193002_second.sql",
        ],
        "20261005190000",
        "20261005193000",
    ) == MULTIPLE

    print("PASS_MIGRATION_VERSION_ORDER_CHECK_TESTS=6/6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
