#!/usr/bin/env python3
"""Regression matrix for the pinned PR93 runtime source gate."""
from __future__ import annotations

import sys

import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as candidate

sys.dont_write_bytecode = True


def expect_error(name: str, code: str, changed: list[str], *, branch: str, blobs: dict[str, str], modes: dict[str, str] | None = None, main_merge_verified: bool = False) -> None:
    try:
        candidate.evaluate_controlled_runtime_scope(
            changed,
            branch=branch,
            blob_by_path=blobs,
            mode_by_path=modes,
            main_merge_verified=main_merge_verified,
        )
    except candidate.RuntimeScopeError as exc:
        if exc.code != code:
            raise SystemExit(f"{name}: expected {code}, got {exc.code}: {exc}")
        print(f"PASS_{name}={code}")
        return
    raise SystemExit(f"{name}: expected {code}, but scope was accepted")


def main() -> int:
    exact_blobs = dict(candidate.EXPECTED_RUNTIME_BLOBS)
    exact_modes = {path: "100644" for path in exact_blobs}
    edge = "supabase/functions/run-github-write-perfil-lf/index.ts"
    alert = candidate.RUNTIME_ALERT_PATH
    migration = candidate.RUNTIME_MIGRATION_PATH

    if candidate.evaluate_controlled_runtime_scope(
        ["sandbox/lf_contract_gate_test/example.txt"],
        branch=candidate.PR_BRANCH,
        blob_by_path={},
    ) is not False:
        raise SystemExit("NO_EDGE_DELEGATES: expected False")
    print("PASS_NO_EDGE_DELEGATES")

    assert candidate.evaluate_controlled_runtime_scope(
        [edge], branch=candidate.PR_BRANCH, blob_by_path=exact_blobs, mode_by_path=exact_modes
    ) is True
    print("PASS_PR_BRANCH_EXACT")

    assert candidate.evaluate_controlled_runtime_scope(
        [edge], branch=candidate.MAIN_BRANCH, blob_by_path=exact_blobs, mode_by_path=exact_modes, main_merge_verified=True
    ) is True
    print("PASS_MAIN_VERIFIED")

    expect_error("MAIN_NOT_MERGED", "FAIL_RUNTIME_MAIN_NOT_MERGED", [edge], branch=candidate.MAIN_BRANCH, blobs=exact_blobs, modes=exact_modes)
    expect_error("ARBITRARY_BRANCH", "FAIL_RUNTIME_BRANCH_MISMATCH", [edge], branch="feature/arbitrary", blobs=exact_blobs, modes=exact_modes)
    expect_error("MISSING_MIGRATION", "FAIL_RUNTIME_MIGRATION_PAIR_MISSING", [alert], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=exact_modes)
    expect_error("EXTRA_EDGE", "FAIL_RUNTIME_EDGE_SCOPE", [edge, "supabase/functions/other/index.ts"], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=exact_modes)

    wrong_blob = dict(exact_blobs)
    wrong_blob[edge] = "0" * 40
    expect_error("WRONG_BLOB", "FAIL_RUNTIME_BLOB_MISMATCH", [edge], branch=candidate.PR_BRANCH, blobs=wrong_blob, modes=exact_modes)

    missing_blob = dict(exact_blobs)
    del missing_blob[edge]
    expect_error("MISSING_BLOB", "FAIL_RUNTIME_BLOB_UNRESOLVED", [edge], branch=candidate.PR_BRANCH, blobs=missing_blob, modes=exact_modes)

    symlink_modes = dict(exact_modes)
    symlink_modes[edge] = "120000"
    expect_error("SYMLINK", "FAIL_RUNTIME_FILE_MODE", [edge], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=symlink_modes)

    expect_error("TRAVERSAL", "FAIL_RUNTIME_PATH_INVALID", ["supabase/functions/../other/index.ts"], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=exact_modes)
    expect_error("UNICODE", "FAIL_RUNTIME_PATH_INVALID", ["supabase/functions/run-github-write-perfil-lf/índex.ts"], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=exact_modes)
    expect_error("RENAME", "FAIL_RUNTIME_EDGE_SCOPE", ["supabase/functions/run-github-write-perfil-lf/renamed.ts"], branch=candidate.PR_BRANCH, blobs=exact_blobs, modes=exact_modes)

    assert candidate.evaluate_controlled_runtime_scope(
        [alert, migration], branch=candidate.PR_BRANCH, blob_by_path=exact_blobs, mode_by_path=exact_modes
    ) is True
    print("PASS_ALERT_PAIR")

    print("PASS_PR93_P0_RUNTIME_SCOPE_MATRIX=14/14")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
