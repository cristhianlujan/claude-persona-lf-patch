#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

EXPECTED_MANIFEST_SHA256 = "665bb6366e91327fe3485739b14ce612281230b608dc48d89ffe4ff6dc5d7620"
EXPECTED_OWNER = "S30"
EXPECTED_PR = 774
EXPECTED_BRANCH = "s30-material-currentness-auto-20260914"


def fail(code: str, detail: str = "") -> None:
    raise SystemExit(f"{code}{(': ' + detail) if detail else ''}")


def run(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if cp.returncode != 0:
        fail("BLOCK_S30_SCOPE_LOCK_GIT", f"{' '.join(args)}::{cp.stderr.strip()}")
    return cp.stdout.strip()


def main() -> int:
    here = Path(__file__).resolve().parent
    repo = here.parents[2]
    manifest_path = here / "S30_PR_SCOPE_LOCK_V1.json"
    raw = manifest_path.read_bytes()
    observed_sha = hashlib.sha256(raw).hexdigest()
    if observed_sha != EXPECTED_MANIFEST_SHA256:
        fail("BLOCK_S30_SCOPE_LOCK_MANIFEST_TAMPERED", f"expected={EXPECTED_MANIFEST_SHA256} observed={observed_sha}")

    lock = json.loads(raw.decode("utf-8"))
    if lock.get("owner") != EXPECTED_OWNER or lock.get("pr_number") != EXPECTED_PR:
        fail("BLOCK_S30_SCOPE_LOCK_IDENTITY")
    if lock.get("head_branch") != EXPECTED_BRANCH:
        fail("BLOCK_S30_SCOPE_LOCK_BRANCH_DECLARATION")
    if lock.get("mode") != "EXACT_FILE_ALLOWLIST_FAIL_CLOSED" or lock.get("cross_owner_changes_allowed") is not False:
        fail("BLOCK_S30_SCOPE_LOCK_MODE")

    gha_head = (os.environ.get("GITHUB_HEAD_REF") or "").strip()
    if gha_head and gha_head != EXPECTED_BRANCH:
        fail("BLOCK_S30_SCOPE_LOCK_FOREIGN_HEAD", gha_head)

    anchor = lock.get("scope_anchor_revision")
    if not isinstance(anchor, str) or len(anchor) != 40:
        fail("BLOCK_S30_SCOPE_LOCK_ANCHOR_FORMAT")
    run(repo, "cat-file", "-e", f"{anchor}^{{commit}}")
    ancestor = subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", anchor, "HEAD"])
    if ancestor.returncode != 0:
        fail("BLOCK_S30_SCOPE_LOCK_REBASE_UNAUTHORIZED", anchor)

    changed = set(filter(None, run(repo, "diff", "--name-only", anchor, "HEAD").splitlines()))
    allowed = set(lock.get("allowed_paths") or [])
    if not allowed:
        fail("BLOCK_S30_SCOPE_LOCK_ALLOWLIST_EMPTY")

    unexpected = sorted(changed - allowed)
    missing = sorted(allowed - changed)
    if unexpected:
        fail("BLOCK_S30_PR_SCOPE_INTRUSION", ",".join(unexpected))
    if missing:
        fail("BLOCK_S30_SCOPE_LOCK_EXPECTED_PATH_MISSING", ",".join(missing))

    print(json.dumps({
        "status": "PASS",
        "scope_lock": "S30_PR_SCOPE_LOCK_V1",
        "pr_number": EXPECTED_PR,
        "head_branch": EXPECTED_BRANCH,
        "anchor": anchor,
        "changed_path_count": len(changed),
        "changed_paths": sorted(changed),
        "manifest_sha256": observed_sha,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
