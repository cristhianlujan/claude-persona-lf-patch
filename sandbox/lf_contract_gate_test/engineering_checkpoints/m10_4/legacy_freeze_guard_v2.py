#!/usr/bin/env python3
"""M10.4 legacy-only source freeze, v2. Executed from trusted main by independent admission.

v2 = v1 + one rule: a path-only rename whose bytes are identical at the base
(old path) and at the head (new path) is not a mutation of a frozen function.
A rename changes no SQL and applies nothing to the database; it only realigns
Git file names with the migration ledger (RECONCILE_SOURCE_ONLY lane).

Everything else is unchanged and reused from v1: the frozen manifest, its
integrity checks, the DDL-target detection and the GitHub reads. v1 and its
manifest are not modified. v2 additionally protects itself, its test and the
admission workflow that selects it.

Read-only GitHub API; no database changes, grants or production activation.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
_V1_PATH = HERE / "legacy_freeze_guard.py"
_spec = importlib.util.spec_from_file_location("lf_m104_legacy_freeze_guard_v1", _V1_PATH)
if _spec is None or _spec.loader is None:  # pragma: no cover - fail closed
    raise SystemExit("FAIL_M104_V2_V1_UNLOADABLE")
v1 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v1)

M104_DIR = "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/"
PROTECTED = frozenset(v1.PROTECTED | {
    M104_DIR + "legacy_freeze_guard_v2.py",
    M104_DIR + "test_legacy_freeze_guard_v2.py",
    ".github/workflows/lf-independent-change-admission.yml",
})


def is_exact_rename(change: dict, old_text: str | None, new_text: str | None) -> bool:
    """True only for a path-only rename with byte-identical content."""
    if change.get("status") != "renamed":
        return False
    old = change.get("previous_filename")
    new = change.get("filename")
    if not old or not new or old == new:
        return False
    if change.get("changes", 1) != 0 or change.get("additions", 1) != 0 or change.get("deletions", 1) != 0:
        return False
    if old_text is None or new_text is None:
        return False
    return old_text == new_text


def _changed_files(repo: str, number: int) -> list[dict]:
    changed: list[dict] = []
    for page in range(1, 41):
        batch = v1.rest(repo, f"pulls/{number}/files?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("FAIL_M104_FILES_RESPONSE")
        changed.extend(batch)
        if len(batch) < 100:
            return changed
    raise ValueError("FAIL_M104_TOO_MANY_FILES")


def check_pr(repo: str, number: int) -> str:
    manifest, targets = v1.load_manifest()
    pr = v1.rest(repo, f"pulls/{number}")
    if pr["head"]["repo"]["full_name"] != repo:
        raise ValueError("FAIL_M104_FOREIGN_HEAD")
    head = pr["head"]["sha"]
    base = pr["base"]["sha"]
    changed = _changed_files(repo, number)

    exact_renames = 0
    for f in changed:
        path = f["filename"]
        old = f.get("previous_filename", path)
        if path in PROTECTED or old in PROTECTED:
            raise ValueError("FAIL_M104_FROZEN_GUARD_ASSET_CHANGED:" + path)
        if not v1.source_candidate(path) and not v1.source_candidate(old):
            continue
        new_text = old_text = None
        if f["status"] != "removed" and v1.source_candidate(path):
            new_text = v1.file_text(repo, path, head)
        if f["status"] in ("removed", "modified", "renamed") and v1.source_candidate(old):
            old_text = v1.file_text(repo, old, base)
        if is_exact_rename(f, old_text, new_text):
            exact_renames += 1
            continue
        for source_path, text in ((path, new_text), (old, old_text)):
            if text is None:
                continue
            hits = v1.touched_targets(text, targets)
            if hits:
                raise ValueError(
                    "FAIL_M104_FROZEN_LEGACY_MUTATION:"
                    + source_path + ":" + ",".join(hits)
                )
    line = (
        "PASS_M104_LEGACY_FREEZE"
        f" pr={number} head={head} sources={len(changed)}"
        f" frozen_identities={len(manifest['legacy_functions'])}"
        f" exact_renames_not_mutation={exact_renames}"
        " legacy_edge=0 guard=v2"
    )
    print(line)
    return line


def self_test() -> None:
    v1.self_test()
    same = "create or replace function programacion.x() returns int language sql as $$select 1$$;\n"
    ok = {"status": "renamed", "previous_filename": "supabase/migrations/1_a.sql",
          "filename": "supabase/migrations/2_a.sql", "changes": 0, "additions": 0, "deletions": 0}
    assert is_exact_rename(ok, same, same)
    assert not is_exact_rename(ok, same, same + "select 1;\n")
    assert not is_exact_rename({**ok, "changes": 2, "additions": 2}, same, same)
    assert not is_exact_rename({**ok, "status": "modified"}, same, same)
    assert not is_exact_rename({**ok, "filename": ok["previous_filename"]}, same, same)
    assert not is_exact_rename(ok, None, same)
    assert v1.PROTECTED <= PROTECTED and len(PROTECTED) == len(v1.PROTECTED) + 3
    print("PASS_M104_GUARD_V2_SELF_TEST 6/6 exact-rename + v1 8/8")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("self-test", "check-pr"))
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    p.add_argument("--pr", type=int)
    args = p.parse_args()
    try:
        if args.mode == "self-test":
            self_test()
        else:
            if not args.repo or not args.pr:
                raise ValueError("FAIL_M104_PR_CONTEXT_REQUIRED")
            check_pr(args.repo, args.pr)
    except (ValueError, AssertionError, KeyError, UnicodeDecodeError) as exc:
        print(str(exc) or type(exc).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
