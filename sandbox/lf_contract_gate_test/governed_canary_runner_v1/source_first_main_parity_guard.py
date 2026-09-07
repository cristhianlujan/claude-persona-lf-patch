#!/usr/bin/env python3
"""Fail-closed source-first guard for exact-version migration canaries.

The shared Supabase ledger must never move ahead of canonical Main merely because
an experimental branch can reach the database. Before any remote preflight or
DDL, every exact-version migration body to be executed must already exist on
origin/main with the identical Git blob identity.

This is an enforcement helper for the existing CI-MIGRATION-SOURCE-PARITY-001
rule. It creates no new governance authority and performs no database writes.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
from typing import Iterable


class SourceFirstParityError(RuntimeError):
    pass


def classify_pair(current: dict[str, str], main: dict[str, str], paths: Iterable[str]) -> dict[str, object]:
    ordered = tuple(paths)
    if not ordered or any(not path for path in ordered):
        raise SourceFirstParityError("SOURCE_FIRST_PATH_SET_INVALID")
    if len(set(ordered)) != len(ordered):
        raise SourceFirstParityError("SOURCE_FIRST_PATH_SET_DUPLICATE")

    missing = [path for path in ordered if path not in main]
    mismatched = [path for path in ordered if path in main and current.get(path) != main.get(path)]
    current_missing = [path for path in ordered if path not in current]

    if current_missing:
        raise SourceFirstParityError("SOURCE_FIRST_CURRENT_SOURCE_MISSING:" + ",".join(current_missing))
    if missing:
        raise SourceFirstParityError("SOURCE_FIRST_MAIN_SOURCE_MISSING:" + ",".join(missing))
    if mismatched:
        raise SourceFirstParityError("SOURCE_FIRST_MAIN_BLOB_MISMATCH:" + ",".join(mismatched))

    return {
        "schema": "LF_SOURCE_FIRST_MAIN_PARITY_V1",
        "result": "PASS",
        "path_count": len(ordered),
        "paths": list(ordered),
    }


def _run(args: list[str], *, cwd: Path, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise SourceFirstParityError(
            f"SOURCE_FIRST_GIT_COMMAND_FAILED:{Path(args[0]).name}:exit={proc.returncode}"
        )
    return proc


def repo_root() -> Path:
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    if proc.returncode != 0:
        raise SourceFirstParityError("SOURCE_FIRST_NOT_IN_GIT_REPOSITORY")
    return Path(proc.stdout.strip())


def _blob_for_worktree(root: Path, path: str) -> str:
    source = root / path
    if not source.is_file():
        raise SourceFirstParityError(f"SOURCE_FIRST_CURRENT_SOURCE_MISSING:{path}")
    return _run(["git", "hash-object", path], cwd=root, timeout=20).stdout.strip()


def _blob_for_ref(root: Path, ref: str, path: str) -> str | None:
    proc = subprocess.run(
        ["git", "rev-parse", f"{ref}:{path}"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    if proc.returncode != 0:
        return None
    value = proc.stdout.strip()
    return value or None


def verify_paths(paths: Iterable[str], *, main_ref: str = "origin/main", fetch_main: bool = True) -> dict[str, object]:
    ordered = tuple(paths)
    root = repo_root()
    if fetch_main:
        _run(["git", "fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main"], cwd=root, timeout=60)

    current = {path: _blob_for_worktree(root, path) for path in ordered}
    main = {}
    for path in ordered:
        blob = _blob_for_ref(root, main_ref, path)
        if blob is not None:
            main[path] = blob
    return classify_pair(current, main, ordered)


def self_test() -> None:
    paths = ("supabase/migrations/111_a.sql", "supabase/migrations/112_b.sql")
    current = {paths[0]: "aaa", paths[1]: "bbb"}
    main = dict(current)
    checks = 0

    out = classify_pair(current, main, paths)
    assert out["result"] == "PASS" and out["path_count"] == 2
    checks += 1

    try:
        classify_pair(current, {paths[0]: "aaa"}, paths)
    except SourceFirstParityError as exc:
        assert str(exc) == f"SOURCE_FIRST_MAIN_SOURCE_MISSING:{paths[1]}"
    else:
        raise AssertionError("missing-main path did not fail")
    checks += 1

    try:
        classify_pair(current, {paths[0]: "aaa", paths[1]: "ccc"}, paths)
    except SourceFirstParityError as exc:
        assert str(exc) == f"SOURCE_FIRST_MAIN_BLOB_MISMATCH:{paths[1]}"
    else:
        raise AssertionError("blob mismatch did not fail")
    checks += 1

    try:
        classify_pair({paths[0]: "aaa"}, main, paths)
    except SourceFirstParityError as exc:
        assert str(exc) == f"SOURCE_FIRST_CURRENT_SOURCE_MISSING:{paths[1]}"
    else:
        raise AssertionError("missing current path did not fail")
    checks += 1

    try:
        classify_pair(current, main, (paths[0], paths[0]))
    except SourceFirstParityError as exc:
        assert str(exc) == "SOURCE_FIRST_PATH_SET_DUPLICATE"
    else:
        raise AssertionError("duplicate path set did not fail")
    checks += 1

    print(f"SOURCE_FIRST_MAIN_PARITY_SELF_TEST_PASS {checks}/5")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--main-ref", default="origin/main")
    parser.add_argument("--no-fetch", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        result = verify_paths(args.paths, main_ref=args.main_ref, fetch_main=not args.no_fetch)
        print(f"SOURCE_FIRST_MAIN_PARITY_PASS {result['path_count']}/{result['path_count']}")
        return 0
    except (SourceFirstParityError, subprocess.TimeoutExpired, OSError) as exc:
        print(f"FAIL_SOURCE_FIRST_MAIN_PARITY:{type(exc).__name__}:{exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
