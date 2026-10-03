#!/usr/bin/env python3
"""Build a governed external baseline delta from a detector report and exact checkout.

The builder is deliberately offline/read-only. It accepts the already-bound detector
report and a git checkout whose HEAD must equal the run GITHUB_SHA. Only detector
states NEW/STALE/MISSING become delta items.

For repository NEW/STALE items, GitHub main is the only source of baseline metadata:
path, git blob, SHA-256 of exact bytes, last commit touching the path, byte length,
and extension. Last-commit attribution is collected in one `git log --name-only`
pass for all changed repository paths; no per-file rev-list/log queries are used.

For MISSING items the authoritative object no longer exists, so content-derived
fields are intentionally null. Edge NEW/STALE items come only from the detector's
runtime evidence (ezbr_sha256/version/verify_jwt/source_state); MISSING runtime
fields are null.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
DELTA_STATES = ("NEW", "STALE", "MISSING")
EDGE_SOURCE_STATES = ("SOURCE_PRESENT", "RUNTIME_WITHOUT_SOURCE")
SCHEMA_VERSION = "LF_EXTERNAL_BASELINE_DELTA_V1"


class DeltaBuildError(RuntimeError):
    pass


def _fail(code: str) -> None:
    raise DeltaBuildError(code)


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - exact parser wording is irrelevant
        raise DeltaBuildError("DELTA_REPORT_JSON_INVALID") from exc
    if not isinstance(value, dict):
        _fail("DELTA_REPORT_SCHEMA_INVALID")
    return value


def _canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _git(checkout: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(checkout), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if proc.returncode != 0:
        raise DeltaBuildError(
            f"DELTA_GIT_COMMAND_FAILED:{args[0] if args else 'git'}"
        )
    return proc.stdout


def _checkout_head(checkout: Path) -> str:
    head = _git(checkout, "rev-parse", "HEAD").strip()
    if not HEX40.fullmatch(head):
        _fail("DELTA_CHECKOUT_HEAD_INVALID")
    return head


def _exact_checkout_bytes(checkout: Path, path: str) -> bytes:
    # Git stores a symlink blob as the link-target bytes, not the target file bytes.
    full = checkout / Path(*PurePosixPath(path).parts)
    try:
        if full.is_symlink():
            return os.fsencode(os.readlink(full))
        if not full.is_file():
            _fail(f"DELTA_REPO_FILE_MISSING:{path}")
        return full.read_bytes()
    except DeltaBuildError:
        raise
    except OSError as exc:
        raise DeltaBuildError(f"DELTA_REPO_FILE_READ_FAILED:{path}") from exc


def _last_commits_one_pass(checkout: Path, paths: Iterable[str]) -> dict[str, str]:
    wanted = list(dict.fromkeys(paths))
    if not wanted:
        return {}
    if any("\n" in path or "\r" in path for path in wanted):
        _fail("DELTA_REPO_PATH_NEWLINE_UNSUPPORTED")

    # One history traversal for every requested path. Git emits newest commits first,
    # therefore the first occurrence of a path is its last commit at HEAD.
    output = _git(
        checkout,
        "log",
        "--format=@@%H",
        "--name-only",
        "--no-renames",
        "HEAD",
        "--",
        *wanted,
    )
    wanted_set = set(wanted)
    result: dict[str, str] = {}
    current_commit: str | None = None
    for raw_line in output.splitlines():
        line = raw_line.strip("\r")
        if not line:
            continue
        if line.startswith("@@"):
            commit = line[2:]
            if not HEX40.fullmatch(commit):
                _fail("DELTA_FILE_HISTORY_COMMIT_INVALID")
            current_commit = commit
            continue
        if line in wanted_set and line not in result:
            if current_commit is None:
                _fail("DELTA_FILE_HISTORY_PARSE_INVALID")
            result[line] = current_commit
            if len(result) == len(wanted_set):
                break

    missing = sorted(wanted_set - set(result))
    if missing:
        _fail(f"DELTA_FILE_LAST_COMMIT_MISSING:{missing[0]}")
    return result


def _extension(path: str) -> str | None:
    suffix = PurePosixPath(path).suffix
    return suffix[1:].lower() if suffix.startswith(".") and len(suffix) > 1 else None


def _records(section: Any, kind: str) -> list[dict[str, Any]]:
    if not isinstance(section, dict) or not isinstance(section.get("records"), list):
        _fail(f"DELTA_{kind}_RECORDS_INVALID")
    rows = section["records"]
    if not all(isinstance(row, dict) for row in rows):
        _fail(f"DELTA_{kind}_RECORDS_INVALID")
    return rows


def _require_unique(rows: list[dict[str, Any]], key: str, code: str) -> None:
    seen: set[str] = set()
    for row in rows:
        value = row.get(key)
        if not isinstance(value, str) or not value:
            _fail(code.replace("DUPLICATE", "KEY_INVALID"))
        if value in seen:
            _fail(code)
        seen.add(value)


def _expected_count(section: dict[str, Any], state: str) -> int:
    counts = section.get("counts")
    if not isinstance(counts, dict) or not isinstance(counts.get(state), int):
        _fail("DELTA_REPORT_COUNTS_INVALID")
    value = counts[state]
    if value < 0:
        _fail("DELTA_REPORT_COUNTS_INVALID")
    return value


def _validate_report_identity(report: dict[str, Any], expected_sha: str) -> None:
    if not HEX40.fullmatch(expected_sha):
        _fail("DELTA_GITHUB_SHA_INVALID")
    repo = report.get("repository")
    if not isinstance(repo, dict):
        _fail("DELTA_REPORT_SCHEMA_INVALID")
    repo_sha = repo.get("observed_main_sha")
    top_sha = report.get("observed_main_sha")
    if repo_sha != expected_sha or top_sha != expected_sha:
        _fail("DELTA_REPORT_SHA_MISMATCH")
    if repo.get("tree_truncated") is not False:
        _fail("DELTA_TREE_TRUNCATED")
    if report.get("pass_unknown_currentness") is not True:
        _fail("DELTA_UNKNOWN_CURRENTNESS")
    if repo.get("unknown_currentness") not in (0, None):
        _fail("DELTA_UNKNOWN_CURRENTNESS")
    edge = report.get("edge")
    if not isinstance(edge, dict) or edge.get("unknown_currentness") not in (0, None):
        _fail("DELTA_UNKNOWN_CURRENTNESS")


def _repo_delta_items(
    report: dict[str, Any], checkout: Path
) -> list[dict[str, Any]]:
    section = report["repository"]
    rows = _records(section, "REPOSITORY")
    _require_unique(rows, "path", "DELTA_REPO_DUPLICATE_PATH")
    for row in rows:
        if row.get("state") == "UNKNOWN":
            _fail("DELTA_UNKNOWN_CURRENTNESS")

    delta_rows = [row for row in rows if row.get("state") in DELTA_STATES]
    for state in DELTA_STATES:
        actual = sum(1 for row in delta_rows if row.get("state") == state)
        if actual != _expected_count(section, state):
            _fail("DELTA_REPORT_COUNT_MISMATCH")

    present_rows = [row for row in delta_rows if row["state"] in ("NEW", "STALE")]
    for row in present_rows:
        blob = row.get("observed_git_blob")
        if not isinstance(blob, str) or not HEX40.fullmatch(blob):
            _fail(f"DELTA_REPO_BLOB_INVALID:{row['path']}")

    last_commits = _last_commits_one_pass(
        checkout, (row["path"] for row in present_rows)
    )
    items: list[dict[str, Any]] = []
    for row in delta_rows:
        path = row["path"]
        state = row["state"]
        if state == "MISSING":
            items.append(
                {
                    "kind": "REPO",
                    "state": state,
                    "path": path,
                    "git_blob": None,
                    "sha256": None,
                    "file_last_commit": None,
                    "bytes": None,
                    "extension": _extension(path),
                }
            )
            continue

        data = _exact_checkout_bytes(checkout, path)
        observed_blob = row["observed_git_blob"]
        exact_blob = _git_blob_sha1(data)
        if exact_blob != observed_blob:
            _fail(f"DELTA_REPO_BLOB_MISMATCH:{path}")
        digest = _sha256_bytes(data)
        if not HEX64.fullmatch(digest):
            _fail(f"DELTA_REPO_HASH_INVALID:{path}")
        last_commit = last_commits.get(path)
        if not last_commit or not HEX40.fullmatch(last_commit):
            _fail(f"DELTA_FILE_LAST_COMMIT_MISSING:{path}")
        items.append(
            {
                "kind": "REPO",
                "state": state,
                "path": path,
                "git_blob": observed_blob,
                "sha256": digest,
                "file_last_commit": last_commit,
                "bytes": len(data),
                "extension": _extension(path),
            }
        )
    return items


def _edge_delta_items(report: dict[str, Any]) -> list[dict[str, Any]]:
    section = report["edge"]
    rows = _records(section, "EDGE")
    _require_unique(rows, "slug", "DELTA_EDGE_DUPLICATE_SLUG")
    for row in rows:
        if row.get("state") == "UNKNOWN":
            _fail("DELTA_UNKNOWN_CURRENTNESS")

    delta_rows = [row for row in rows if row.get("state") in DELTA_STATES]
    for state in DELTA_STATES:
        actual = sum(1 for row in delta_rows if row.get("state") == state)
        if actual != _expected_count(section, state):
            _fail("DELTA_REPORT_COUNT_MISMATCH")

    items: list[dict[str, Any]] = []
    for row in delta_rows:
        slug = row["slug"]
        state = row["state"]
        if state == "MISSING":
            items.append(
                {
                    "kind": "EDGE",
                    "state": state,
                    "slug": slug,
                    "ezbr_sha256": None,
                    "runtime_version": None,
                    "verify_jwt": None,
                    "source_state": None,
                }
            )
            continue

        runtime_hash = row.get("runtime_sha256")
        runtime_version = row.get("runtime_version")
        source_state = row.get("source_state")
        verify_jwt = row.get("verify_jwt")
        if not isinstance(runtime_hash, str) or not HEX64.fullmatch(runtime_hash):
            _fail(f"DELTA_EDGE_HASH_INVALID:{slug}")
        if runtime_version in (None, ""):
            _fail(f"DELTA_EDGE_VERSION_INVALID:{slug}")
        if source_state not in EDGE_SOURCE_STATES:
            _fail(f"DELTA_EDGE_SOURCE_STATE_INVALID:{slug}")
        if not isinstance(verify_jwt, bool):
            _fail(f"DELTA_EDGE_VERIFY_JWT_INVALID:{slug}")
        items.append(
            {
                "kind": "EDGE",
                "state": state,
                "slug": slug,
                "ezbr_sha256": runtime_hash,
                "runtime_version": runtime_version,
                "verify_jwt": verify_jwt,
                "source_state": source_state,
            }
        )
    return items


def build_delta(report_path: Path, checkout: Path, github_sha: str) -> dict[str, Any]:
    checkout = checkout.resolve()
    report_path = report_path.resolve()
    report_bytes = report_path.read_bytes()
    report = _load_json(report_path)
    _validate_report_identity(report, github_sha)

    head = _checkout_head(checkout)
    if head != github_sha:
        _fail("DELTA_CHECKOUT_SHA_MISMATCH")

    repo_items = _repo_delta_items(report, checkout)
    edge_items = _edge_delta_items(report)
    all_items = sorted(
        [*repo_items, *edge_items],
        key=lambda item: (item["kind"], item.get("path") or item.get("slug") or ""),
    )
    keys = [
        f"{item['kind']}:{item.get('path') or item.get('slug')}" for item in all_items
    ]
    if len(keys) != len(set(keys)):
        _fail("DELTA_DUPLICATE_ITEM")
    if not all_items:
        _fail("DELTA_EMPTY")

    report_sha256 = _sha256_bytes(report_bytes)
    sync_key = _sha256_bytes(f"{github_sha}:{report_sha256}".encode("utf-8"))
    repo_counts = {
        state: sum(1 for item in repo_items if item["state"] == state)
        for state in DELTA_STATES
    }
    edge_counts = {
        state: sum(1 for item in edge_items if item["state"] == state)
        for state in DELTA_STATES
    }
    runtime_without_source = sum(
        1
        for item in edge_items
        if item.get("source_state") == "RUNTIME_WITHOUT_SOURCE"
    )

    return {
        "schema_version": SCHEMA_VERSION,
        "observed_main_sha": github_sha,
        "report_sha256": report_sha256,
        "sync_key": sync_key,
        "counts": {
            "repository": repo_counts,
            "edge": edge_counts,
            "runtime_without_source": runtime_without_source,
            "total": len(all_items),
        },
        "items": all_items,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--checkout", default=Path("."), type=Path)
    parser.add_argument("--github-sha", default=os.environ.get("GITHUB_SHA", ""))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    try:
        delta = build_delta(args.report, args.checkout, args.github_sha)
    except (DeltaBuildError, OSError) as exc:
        print(str(exc), file=os.sys.stderr)
        return 2

    payload = json.dumps(delta, sort_keys=True, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
