#!/usr/bin/env python3
"""Required regression matrix for the frozen migration-parity baseline."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
BASELINE = "20261005195626"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ctx = load("lf_migration_source_parity_ci_context_baseline_test", HERE / "lf_migration_source_parity_ci_context.py")
core = load("migration_source_parity_core_baseline_test", HERE / "migration_source_parity_core.py")


def expect_system_exit(fn, code: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert str(exc).startswith(code), (code, str(exc))
    else:
        raise AssertionError(f"expected {code}")


def expect_core_error(fn, code: str) -> None:
    try:
        fn()
    except core.ParityCoreError as exc:
        assert exc.code == code, (code, exc.code, exc.detail)
    else:
        raise AssertionError(f"expected {code}")


def exact_rows(local_rows, remote_rows):
    local = {v: row for v, row in local_rows.items() if ctx.exact_parity_applies(v, BASELINE)}
    remote = {v: row for v, row in remote_rows.items() if ctx.exact_parity_applies(v, BASELINE)}
    return local, remote


def direct(version: str, name: str, sql: str):
    sha = ctx.transport.direct_source_hash(sql)
    return (name, sha, sql)


def remote(name: str, sql: str):
    return (name, ctx.transport.direct_source_hash(sql))


def main() -> int:
    checks = 0

    # 1. Historical divergence is accepted because it is outside exact parity.
    old = "20261001120000"
    new = "20261005210000"
    local, remote_rows = exact_rows(
        {
            old: direct(old, "lf_old_git_name", "select 1;\n"),
            new: direct(new, "lf_new", "select 2;\n"),
        },
        {
            old: remote("lf_old_ledger_name", "select 999;\n"),
            new: remote("lf_new", "select 2;\n"),
        },
    )
    result = core.evaluate_exact_parity(local, remote_rows, {new: 1})
    assert result.status == "PASS" and result.version_count == 1
    checks += 1

    # 2. Explicit historical exception requested by the owner.
    mismatch_version = "20261003001000"
    assert not ctx.exact_parity_applies(mismatch_version, BASELINE)
    local, remote_rows = exact_rows(
        {mismatch_version: direct(mismatch_version, "independent_assurance_oracle_independence_measure_v1", "select 1;\n")},
        {mismatch_version: remote("ig_cv_m2_2_empty_collection_semantics_v1", "select 2;\n")},
    )
    assert local == {} and remote_rows == {}
    checks += 1

    # 3. Altering grandfather count/hash remains fail-closed.
    expect_system_exit(
        lambda: ctx.verify_grandfather_baseline(
            observed_count="793",
            observed_sha="0" * 64,
            expected_count="794",
            expected_sha="a49da6b22a15dd2b41588b78386cff3ccb9bfb4976ed563d8ed78e6c8e87cc9e",
        ),
        "FAIL_LF_MIGRATION_GRANDFATHER_BASELINE",
    )
    checks += 1

    # 4. Identical post-baseline migration passes exact parity.
    version = "20261005210100"
    sql = "select 42;\n"
    result = core.evaluate_exact_parity(
        {version: direct(version, "lf_post_cut", sql)},
        {version: remote("lf_post_cut", sql)},
        {version: 1},
    )
    assert result.status == "PASS"
    checks += 1

    # 5. Git-only post-baseline migration fails exact parity.
    expect_core_error(
        lambda: core.evaluate_exact_parity(
            {version: direct(version, "lf_post_cut", sql)},
            {},
            {},
        ),
        "FAIL_LF_MIGRATION_VERSION_PARITY",
    )
    checks += 1

    # 6. Ledger-only post-baseline migration fails exact parity.
    expect_core_error(
        lambda: core.evaluate_exact_parity(
            {},
            {version: remote("lf_post_cut", sql)},
            {version: 1},
        ),
        "FAIL_LF_MIGRATION_VERSION_PARITY",
    )
    checks += 1

    # 7. Name or content drift after the cut both fail.
    expect_core_error(
        lambda: core.evaluate_exact_parity(
            {version: direct(version, "lf_git_name", sql)},
            {version: remote("lf_ledger_name", sql)},
            {version: 1},
        ),
        "FAIL_LF_MIGRATION_NAME_PARITY",
    )
    expect_core_error(
        lambda: core.evaluate_exact_parity(
            {version: direct(version, "lf_post_cut", sql)},
            {version: remote("lf_post_cut", "select 43;\n")},
            {version: 1},
        ),
        "FAIL_LF_MIGRATION_CONTENT_PARITY",
    )
    checks += 1

    # 8. A new/modified migration at or before the frozen baseline is backdating.
    expect_system_exit(
        lambda: ctx.enforce_no_backdated_changed_migrations(
            "A\tsupabase/migrations/20261005190000_backdated.sql\n",
            BASELINE,
        ),
        "FAIL_LF_MIGRATION_BACKDATED_AFTER_BASELINE",
    )
    checks += 1

    assert checks == 8
    print("PASS_MIGRATION_SOURCE_PARITY_BASELINE_TESTS=8/8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
