#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

EXPECTED_MANIFEST_SHA256 = "0e449a1f5122333d57309e4c4b1daaa6be12f2c48956ea9a45138908a7715e9d"
EXPECTED_OWNER = "S30"
EXPECTED_BRANCH = "s30-operation-bootstrap-lf-20260914"


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
    raw = (here / "S30_PR_SCOPE_LOCK_V1.json").read_bytes()
    observed = hashlib.sha256(raw).hexdigest()
    if observed != EXPECTED_MANIFEST_SHA256:
        fail("BLOCK_S30_SCOPE_LOCK_MANIFEST_TAMPERED", f"expected={EXPECTED_MANIFEST_SHA256} observed={observed}")
    lock = json.loads(raw.decode("utf-8"))
    if lock.get("owner") != EXPECTED_OWNER or lock.get("head_branch") != EXPECTED_BRANCH:
        fail("BLOCK_S30_SCOPE_LOCK_IDENTITY")
    if lock.get("cross_owner_changes_allowed") is not False:
        fail("BLOCK_S30_SCOPE_LOCK_CROSS_OWNER_ENABLED")

    gha_head = (os.environ.get("GITHUB_HEAD_REF") or "").strip()
    if gha_head and gha_head != EXPECTED_BRANCH:
        fail("BLOCK_S30_SCOPE_LOCK_FOREIGN_HEAD", gha_head)

    anchor = lock.get("scope_anchor_revision")
    run(repo, "cat-file", "-e", f"{anchor}^{{commit}}")
    if subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", anchor, "HEAD"]).returncode != 0:
        fail("BLOCK_S30_SCOPE_LOCK_REBASE_UNAUTHORIZED", anchor)

    changed = set(filter(None, run(repo, "diff", "--name-only", anchor, "HEAD").splitlines()))
    allowed = set(lock.get("allowed_paths") or [])
    unexpected = sorted(changed - allowed)
    missing = sorted(allowed - changed)
    if unexpected:
        fail("BLOCK_S30_PR_SCOPE_INTRUSION", ",".join(unexpected))
    if missing:
        fail("BLOCK_S30_SCOPE_LOCK_EXPECTED_PATH_MISSING", ",".join(missing))

    print(json.dumps({"status":"PASS","scope":"S30_OPERATION_BOOTSTRAP_ONLY","changed_path_count":len(changed),"anchor":anchor,"manifest_sha256":observed}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
