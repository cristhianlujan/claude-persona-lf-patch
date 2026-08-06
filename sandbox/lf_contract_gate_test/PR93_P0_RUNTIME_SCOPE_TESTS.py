#!/usr/bin/env python3
"""Regression matrix for the narrow PR93 HMAC runtime scope exception."""
from __future__ import annotations

import sys

import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as candidate

sys.dont_write_bytecode = True


def expect_error(
    name: str,
    code: str,
    changed: list[str],
    branch: str,
    blobs: dict[str, str],
) -> None:
    try:
        candidate.evaluate_controlled_runtime_scope(
            changed,
            branch=branch,
            blob_by_path=blobs,
        )
    except candidate.RuntimeScopeError as exc:
        if exc.code != code:
            raise SystemExit(f"{name}: expected {code}, got {exc.code}: {exc}")
        print(f"PASS_{name}={code}")
        return
    raise SystemExit(f"{name}: expected {code}, but scope was accepted")


def main() -> int:
    edge = candidate.RUNTIME_EDGE_PATH
    migration = candidate.RUNTIME_MIGRATION_PATH
    exact_blobs = dict(candidate.EXPECTED_RUNTIME_BLOBS)

    if candidate.evaluate_controlled_runtime_scope(
        ["sandbox/lf_contract_gate_test/example.txt"],
        branch=candidate.RUNTIME_BRANCH,
        blob_by_path={},
    ) is not False:
        raise SystemExit("NO_EDGE_DELEGATES_TO_E16: expected False")
    print("PASS_NO_EDGE_DELEGATES_TO_E16")

    if candidate.evaluate_controlled_runtime_scope(
        [edge, migration],
        branch=candidate.RUNTIME_BRANCH,
        blob_by_path=exact_blobs,
    ) is not True:
        raise SystemExit("EXACT_PAIR: expected True")
    print("PASS_EXACT_PAIR")

    expect_error(
        "MISSING_MIGRATION",
        "FAIL_RUNTIME_MIGRATION_PAIR_MISSING",
        [edge],
        candidate.RUNTIME_BRANCH,
        exact_blobs,
    )
    expect_error(
        "EXTRA_EDGE",
        "FAIL_RUNTIME_EDGE_SCOPE",
        [edge, migration, "supabase/functions/other/index.ts"],
        candidate.RUNTIME_BRANCH,
        exact_blobs,
    )
    expect_error(
        "WRONG_BRANCH",
        "FAIL_RUNTIME_BRANCH_MISMATCH",
        [edge, migration],
        "main",
        exact_blobs,
    )

    wrong_edge = dict(exact_blobs)
    wrong_edge[edge] = "0" * 40
    expect_error(
        "WRONG_EDGE_BLOB",
        "FAIL_RUNTIME_BLOB_MISMATCH",
        [edge, migration],
        candidate.RUNTIME_BRANCH,
        wrong_edge,
    )

    wrong_migration = dict(exact_blobs)
    wrong_migration[migration] = "f" * 40
    expect_error(
        "WRONG_MIGRATION_BLOB",
        "FAIL_RUNTIME_BLOB_MISMATCH",
        [edge, migration],
        candidate.RUNTIME_BRANCH,
        wrong_migration,
    )

    print("PASS_PR93_P0_RUNTIME_SCOPE_MATRIX=7/7")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
