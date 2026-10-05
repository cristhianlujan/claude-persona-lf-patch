#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTEXT = HERE / "lf_migration_source_parity_ci_context.py"
CORE = HERE / "migration_source_parity_core.py"

def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

ctx = load("baseline_cut_context_test", CONTEXT)
core = load("baseline_cut_core_test", CORE)

BASELINE_END = "20261005203801"
SAME_BLOB = "a" * 40


def expect_system_exit(prefix: str, fn) -> None:
    try:
        fn()
    except SystemExit as exc:
        if not str(exc).startswith(prefix):
            raise AssertionError(f"expected {prefix}, got {exc}") from exc
    else:
        raise AssertionError(f"expected {prefix}")


def expect_core_error(code: str, fn) -> None:
    try:
        fn()
    except core.ParityCoreError as exc:
        assert exc.code == code, (exc.code, code)
    else:
        raise AssertionError(f"expected {code}")


def direct_fixture(version: str = "20261005203802", name: str = "lf_probe"):
    sql = "select 1;\n"
    sha = hashlib.sha256(ctx.canonical(sql)).hexdigest()
    return (
        {version: (name, sha, sql)},
        {version: (name, sha)},
        {version: 1},
    )


def main() -> int:
    checks = 0

    # 1. Historical identity that existed at the cut is accepted without exact parity.
    ctx.validate_historical_source_identity(
        version="20260901000000",
        classification_baseline_end=BASELINE_END,
        baseline_blob=SAME_BLOB,
        current_blob=SAME_BLOB,
        repo_path="supabase/migrations/20260901000000_lf_historical.sql",
    )
    checks += 1

    # 2. The known 20261003001000 name mismatch is explicitly inside the historical cut.
    ctx.validate_historical_source_identity(
        version="20261003001000",
        classification_baseline_end=BASELINE_END,
        baseline_blob=SAME_BLOB,
        current_blob=SAME_BLOB,
        repo_path="supabase/migrations/20261003001000_independent_assurance_oracle_independence_measure_v1.sql",
    )
    checks += 1

    # 3. Any mutation of grandfather count/hash fails closed.
    expect_system_exit(
        "FAIL_LF_MIGRATION_GRANDFATHER_BASELINE",
        lambda: ctx.validate_grandfather_attestation(
            "795",
            "0" * 64,
            "796",
            "94b5e2bb0b33e6e08b1b72b9af48423c2f3e8333945797313f8816a7ee18de38",
        ),
    )
    checks += 1

    # 4. Exact post-cut version/name/content passes.
    local, remote, counts = direct_fixture()
    result = core.evaluate_exact_parity(local, remote, counts)
    assert result.status == "PASS" and result.version_count == 1
    checks += 1

    # 5. Post-cut source only in Git fails version parity.
    local, _remote, _counts = direct_fixture()
    expect_core_error(
        "FAIL_LF_MIGRATION_VERSION_PARITY",
        lambda: core.evaluate_exact_parity(local, {}, {}),
    )
    checks += 1

    # 6. Post-cut source only in ledger fails version parity.
    _local, remote, counts = direct_fixture()
    expect_core_error(
        "FAIL_LF_MIGRATION_VERSION_PARITY",
        lambda: core.evaluate_exact_parity({}, remote, counts),
    )
    checks += 1

    # 7. Post-cut name and content mismatches both remain fail closed.
    local, remote, counts = direct_fixture()
    version = next(iter(local))
    expect_core_error(
        "FAIL_LF_MIGRATION_NAME_PARITY",
        lambda: core.evaluate_exact_parity(
            local,
            {version: ("lf_other_name", remote[version][1])},
            counts,
        ),
    )
    expect_core_error(
        "FAIL_LF_MIGRATION_CONTENT_PARITY",
        lambda: core.evaluate_exact_parity(
            local,
            {version: (remote[version][0], "0" * 64)},
            counts,
        ),
    )
    checks += 1

    # 8. A new old-timestamp source absent from the baseline tree is backdating.
    expect_system_exit(
        "FAIL_LF_MIGRATION_BACKDATED_SOURCE",
        lambda: ctx.validate_historical_source_identity(
            version="20261001000000",
            classification_baseline_end=BASELINE_END,
            baseline_blob=None,
            current_blob=SAME_BLOB,
            repo_path="supabase/migrations/20261001000000_lf_backdated.sql",
        ),
    )
    checks += 1

    print(f"PASS_MIGRATION_PARITY_BASELINE_CUT_TESTS={checks}/8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
