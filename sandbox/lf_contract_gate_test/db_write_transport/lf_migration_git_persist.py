#!/usr/bin/env python3
"""Guarded Git persistence transport for governed LF migration source.

This is a transport primitive consumed by ACTUALIZACION_DB_LF / DB_WRITE_TRANSPORT.
It grants no authority, never targets main, never merges, and never touches Supabase.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

SHA40 = re.compile(r"^[0-9a-f]{40}$")
PATH_RE = re.compile(r"^supabase/migrations/\d{14}_[A-Za-z0-9][A-Za-z0-9_]*\.sql$")
BRANCH_RE = re.compile(r"^lf/migration-source-(?:repair|persist)/[A-Za-z0-9._/-]+$")


@dataclass(frozen=True)
class Request:
    repository: str
    base_sha: str
    source_sha: str
    source_blob: str
    source_sha256: str
    target_path: str
    target_branch: str
    execution_id: str


@dataclass(frozen=True)
class Receipt:
    schema_version: str
    status: str
    code: str
    repository: str
    base_sha: str
    source_sha: str
    source_blob: str
    source_sha256: str
    target_path: str
    target_branch: str
    execution_id: str
    persisted_head_sha: str | None
    readback: bool


def _run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check, timeout=90)


def validate_request(raw: dict[str, object]) -> Request:
    required = (
        "repository", "base_sha", "source_sha", "source_blob", "source_sha256",
        "target_path", "target_branch", "execution_id",
    )
    missing = [key for key in required if not isinstance(raw.get(key), str) or not str(raw.get(key)).strip()]
    if missing:
        raise ValueError("MIGRATION_GIT_PERSIST_FIELDS_MISSING:" + ",".join(missing))
    request = Request(**{key: str(raw[key]).strip() for key in required})
    if SHA40.fullmatch(request.base_sha) is None or SHA40.fullmatch(request.source_sha) is None:
        raise ValueError("MIGRATION_GIT_PERSIST_COMMIT_SHA_INVALID")
    if SHA40.fullmatch(request.source_blob) is None:
        raise ValueError("MIGRATION_GIT_PERSIST_BLOB_SHA_INVALID")
    if re.fullmatch(r"[0-9a-f]{64}", request.source_sha256) is None:
        raise ValueError("MIGRATION_GIT_PERSIST_SOURCE_SHA256_INVALID")
    if PATH_RE.fullmatch(request.target_path) is None:
        raise ValueError("MIGRATION_GIT_PERSIST_PATH_INVALID")
    if BRANCH_RE.fullmatch(request.target_branch) is None or request.target_branch in {"main", "master"}:
        raise ValueError("MIGRATION_GIT_PERSIST_BRANCH_INVALID")
    if ".." in request.target_branch.split("/"):
        raise ValueError("MIGRATION_GIT_PERSIST_BRANCH_INVALID")
    return request


def verify_source(request: Request) -> bytes:
    _run(["git", "fetch", "--no-tags", "origin", request.source_sha])
    blob = _run(["git", "rev-parse", f"{request.source_sha}:{request.target_path}"]).stdout.strip().lower()
    if blob != request.source_blob:
        raise ValueError("MIGRATION_GIT_PERSIST_SOURCE_BLOB_MISMATCH")
    source = subprocess.run(
        ["git", "show", f"{request.source_sha}:{request.target_path}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=60,
    ).stdout
    if hashlib.sha256(source).hexdigest() != request.source_sha256:
        raise ValueError("MIGRATION_GIT_PERSIST_SOURCE_SHA256_MISMATCH")
    return source


def persist(request: Request) -> Receipt:
    source = verify_source(request)
    _run(["git", "fetch", "--no-tags", "origin", request.base_sha])
    base_has = subprocess.run(
        ["git", "cat-file", "-e", f"{request.base_sha}:{request.target_path}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=30,
    ).returncode == 0
    if base_has:
        existing = subprocess.run(
            ["git", "show", f"{request.base_sha}:{request.target_path}"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=60,
        ).stdout
        if hashlib.sha256(existing).hexdigest() != request.source_sha256:
            raise ValueError("MIGRATION_GIT_PERSIST_BASE_PATH_CONFLICT")
        return Receipt(
            "lf-migration-git-persist/v1", "PASS", "ALREADY_PERSISTED_EXACT",
            request.repository, request.base_sha, request.source_sha, request.source_blob,
            request.source_sha256, request.target_path, request.target_branch,
            request.execution_id, request.base_sha, True,
        )

    current = _run(["git", "status", "--porcelain"]).stdout
    if current.strip():
        raise ValueError("MIGRATION_GIT_PERSIST_WORKTREE_DIRTY")

    _run(["git", "checkout", "--detach", request.base_sha])
    _run(["git", "checkout", "-B", request.target_branch])
    path = Path(request.target_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(source)
    _run(["git", "add", "--", request.target_path])
    _run(["git", "commit", "-m", f"fix(governance): restore migration source {path.name}"])
    head = _run(["git", "rev-parse", "HEAD"]).stdout.strip().lower()
    if SHA40.fullmatch(head) is None:
        raise ValueError("MIGRATION_GIT_PERSIST_HEAD_INVALID")
    _run(["git", "push", "origin", f"{head}:refs/heads/{request.target_branch}"])
    remote = _run(["git", "ls-remote", "origin", f"refs/heads/{request.target_branch}"]).stdout.strip().split()
    if len(remote) < 1 or remote[0].lower() != head:
        raise ValueError("MIGRATION_GIT_PERSIST_REMOTE_READBACK_MISMATCH")
    return Receipt(
        "lf-migration-git-persist/v1", "PASS", "PERSISTED_WITH_REMOTE_READBACK",
        request.repository, request.base_sha, request.source_sha, request.source_blob,
        request.source_sha256, request.target_path, request.target_branch,
        request.execution_id, head, True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    raw = json.loads(Path(args.request).read_text(encoding="utf-8"))
    request = validate_request(raw)
    receipt = persist(request)
    print(json.dumps(asdict(receipt), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
