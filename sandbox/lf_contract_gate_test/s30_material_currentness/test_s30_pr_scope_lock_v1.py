#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

EXPECTED_MANIFEST_SHA256 = "0fa40b3168beb95e9bc1ac7128fdcb725ec2d0a624ac766b25e7da700d9549c9"
EXPECTED_OWNER = "S30"
EXPECTED_PR = 774
EXPECTED_BRANCH = "s30-material-currentness-auto-20260914"
HEX40 = re.compile(r"^[0-9a-f]{40}$")


def fail(code: str, detail: str = "") -> None:
    raise SystemExit(f"{code}{(': ' + detail) if detail else ''}")


def run(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if cp.returncode != 0:
        fail("BLOCK_S30_SCOPE_LOCK_GIT", f"{' '.join(args)}::{cp.stderr.strip()}")
    return cp.stdout.strip()


def owned_head(repo: Path) -> str:
    event_name = (os.environ.get("GITHUB_EVENT_NAME") or "").strip()
    event_path = (os.environ.get("GITHUB_EVENT_PATH") or "").strip()
    if event_name == "pull_request" and event_path:
        payload = json.loads(Path(event_path).read_text(encoding="utf-8"))
        pr = payload.get("pull_request") or {}
        number = pr.get("number") or payload.get("number")
        head = ((pr.get("head") or {}).get("sha") or "").strip()
        ref = ((pr.get("head") or {}).get("ref") or "").strip()
        if number != EXPECTED_PR:
            fail("BLOCK_S30_SCOPE_LOCK_FOREIGN_PR", str(number))
        if ref != EXPECTED_BRANCH:
            fail("BLOCK_S30_SCOPE_LOCK_FOREIGN_HEAD", ref)
        if not HEX40.fullmatch(head):
            fail("BLOCK_S30_SCOPE_LOCK_PR_HEAD_INVALID", head)
        return head

    gha_head = (os.environ.get("GITHUB_HEAD_REF") or "").strip()
    if gha_head and gha_head != EXPECTED_BRANCH:
        fail("BLOCK_S30_SCOPE_LOCK_FOREIGN_HEAD", gha_head)
    head = run(repo, "rev-parse", "HEAD")
    if not HEX40.fullmatch(head):
        fail("BLOCK_S30_SCOPE_LOCK_LOCAL_HEAD_INVALID", head)
    return head


def ensure_full_history(repo: Path, anchor: str, branch_head: str) -> None:
    # Earlier shared CI performs depth=1 fetches after checkout, which can mark
    # otherwise-full commits as shallow boundaries and make merge-base lie.
    shallow = run(repo, "rev-parse", "--is-shallow-repository").lower() == "true"
    if shallow:
        cp = subprocess.run(["git", "-C", str(repo), "fetch", "--unshallow", "origin", "--no-tags"], text=True, capture_output=True)
        if cp.returncode != 0:
            fail("BLOCK_S30_SCOPE_LOCK_UNSHALLOW_FAILED", cp.stderr.strip())
    cp = subprocess.run(["git", "-C", str(repo), "fetch", "origin", anchor, branch_head, "--no-tags"], text=True, capture_output=True)
    if cp.returncode != 0:
        fail("BLOCK_S30_SCOPE_LOCK_FETCH_OWNED_HISTORY", cp.stderr.strip())
    run(repo, "cat-file", "-e", f"{anchor}^{{commit}}")
    run(repo, "cat-file", "-e", f"{branch_head}^{{commit}}")


def main() -> int:
    here = Path(__file__).resolve().parent
    repo = Path(run(here, "rev-parse", "--show-toplevel"))
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

    anchor = lock.get("scope_anchor_revision")
    if not isinstance(anchor, str) or not HEX40.fullmatch(anchor):
        fail("BLOCK_S30_SCOPE_LOCK_ANCHOR_FORMAT")
    branch_head = owned_head(repo)
    ensure_full_history(repo, anchor, branch_head)

    merge_base = run(repo, "merge-base", anchor, branch_head)
    if merge_base != anchor:
        fail("BLOCK_S30_SCOPE_LOCK_REBASE_UNAUTHORIZED", f"anchor={anchor} merge_base={merge_base} head={branch_head}")

    changed = set(filter(None, run(repo, "diff", "--name-only", anchor, branch_head).splitlines()))
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
        "merge_base": merge_base,
        "owned_head": branch_head,
        "synthetic_merge_head_ignored": run(repo, "rev-parse", "HEAD") != branch_head,
        "changed_path_count": len(changed),
        "changed_paths": sorted(changed),
        "manifest_sha256": observed_sha,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
