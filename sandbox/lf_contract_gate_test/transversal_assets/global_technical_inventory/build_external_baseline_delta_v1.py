#!/usr/bin/env python3
"""Build the governed repo/Edge baseline delta from a currentness report.

Authority and fail-closed invariants:
- the report, checkout HEAD, and --expected-sha must be the same 40-hex commit;
- repository tree must not be truncated and UNKNOWN currentness must be zero;
- repo NEW/STALE identities come from the exact Git blob bytes at that commit;
- file_last_commit is resolved for all changed repo paths in one git-log pass;
- Edge NEW/STALE identities come from runtime ezbr_sha256; version is informational;
- CURRENT rows are omitted; only NEW/STALE/MISSING become baseline items.

The output is deterministic canonical JSON and includes report_sha256 + sync_key,
where sync_key = sha256(observed_main_sha + ':' + report_sha256), matching INV-9.5a.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
from typing import Any, Iterable

SCHEMA_VERSION = "LF_EXTERNAL_BASELINE_DELTA_V1"
REPORT_SCHEMA_VERSION = "LF_EXTERNAL_CURRENTNESS_REPORT_V1"
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
DELTA_STATES = {"NEW", "STALE", "MISSING"}
EDGE_SOURCE_STATES = {"SOURCE_PRESENT", "RUNTIME_WITHOUT_SOURCE"}


class DeltaError(ValueError):
    pass


def _fail(code: str, detail: str = "") -> None:
    raise DeltaError(f"{code}:{detail}" if detail else code)


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        _fail("BASELINE_DELTA_JSON_READ_FAILED", f"{path}:{type(exc).__name__}")


def _run_git(repo_root: Path, *args: str, text: bool = True) -> subprocess.CompletedProcess[Any]:
    proc = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() if text else proc.stderr.decode("utf-8", "replace").strip()
        _fail("BASELINE_DELTA_GIT_FAILED", f"{' '.join(args)}:{stderr[:500]}")
    return proc


def _git_head(repo_root: Path) -> str:
    head = _run_git(repo_root, "rev-parse", "HEAD").stdout.strip().lower()
    if SHA40_RE.fullmatch(head) is None:
        _fail("BASELINE_DELTA_HEAD_INVALID", head)
    return head


def _safe_repo_path(path: str) -> str:
    if not path or "\x00" in path or path.startswith("/"):
        _fail("BASELINE_DELTA_REPO_PATH_INVALID", repr(path))
    posix = PurePosixPath(path)
    if any(part in ("", ".", "..") for part in posix.parts):
        _fail("BASELINE_DELTA_REPO_PATH_INVALID", repr(path))
    normalized = posix.as_posix()
    if normalized != path:
        _fail("BASELINE_DELTA_REPO_PATH_NONCANONICAL", repr(path))
    return path


def _git_tree_map(repo_root: Path, sha: str) -> dict[str, str]:
    raw = _run_git(repo_root, "ls-tree", "-r", "-z", sha, text=False).stdout
    result: dict[str, str] = {}
    for entry in raw.split(b"\x00"):
        if not entry:
            continue
        try:
            meta, raw_path = entry.split(b"\t", 1)
            mode, obj_type, obj_sha = meta.decode("ascii").split(" ")
            path = raw_path.decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            _fail("BASELINE_DELTA_GIT_TREE_PARSE_FAILED", type(exc).__name__)
        if obj_type != "blob":
            continue
        if SHA40_RE.fullmatch(obj_sha) is None:
            _fail("BASELINE_DELTA_GIT_BLOB_INVALID", f"{path}:{obj_sha}")
        if path in result:
            _fail("BASELINE_DELTA_GIT_TREE_DUPLICATE", path)
        result[path] = obj_sha
    return result


def _last_commit_map(repo_root: Path, sha: str, target_paths: Iterable[str]) -> dict[str, str]:
    paths = sorted(set(target_paths))
    if not paths:
        return {}
    # One git-log process for every target path. The first appearance of a path in
    # reverse-chronological output is its last commit at the exact observed SHA.
    proc = _run_git(
        repo_root,
        "log",
        "--format=@@%H",
        "--name-only",
        "--no-renames",
        sha,
        "--",
        *paths,
    )
    targets = set(paths)
    commits: dict[str, str] = {}
    current_commit = ""
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("@@"):
            current_commit = line[2:].strip().lower()
            if SHA40_RE.fullmatch(current_commit) is None:
                _fail("BASELINE_DELTA_GIT_LOG_COMMIT_INVALID", current_commit)
            continue
        if line in targets and line not in commits:
            if not current_commit:
                _fail("BASELINE_DELTA_GIT_LOG_ORDER_INVALID", line)
            commits[line] = current_commit
            if len(commits) == len(targets):
                break
    missing = sorted(targets - set(commits))
    if missing:
        _fail("BASELINE_DELTA_LAST_COMMIT_MISSING", ",".join(missing[:20]))
    return commits


def _cat_blob_batch(repo_root: Path, blob_shas: Iterable[str]) -> dict[str, bytes]:
    ordered = list(dict.fromkeys(blob_shas))
    if not ordered:
        return {}
    for sha in ordered:
        if SHA40_RE.fullmatch(sha) is None:
            _fail("BASELINE_DELTA_GIT_BLOB_INVALID", sha)

    proc = subprocess.Popen(
        ["git", "-C", str(repo_root), "cat-file", "--batch"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.stdin is not None and proc.stdout is not None and proc.stderr is not None
    try:
        proc.stdin.write(("\n".join(ordered) + "\n").encode("ascii"))
        proc.stdin.flush()
        proc.stdin.close()
        result: dict[str, bytes] = {}
        for requested in ordered:
            header = proc.stdout.readline()
            if not header:
                _fail("BASELINE_DELTA_CAT_FILE_EOF", requested)
            parts = header.decode("ascii", "replace").strip().split()
            if len(parts) != 3:
                _fail("BASELINE_DELTA_CAT_FILE_HEADER_INVALID", header.decode("ascii", "replace").strip())
            actual_sha, obj_type, raw_size = parts
            if actual_sha != requested or obj_type != "blob":
                _fail("BASELINE_DELTA_CAT_FILE_IDENTITY_MISMATCH", f"{requested}:{actual_sha}:{obj_type}")
            try:
                size = int(raw_size)
            except ValueError:
                _fail("BASELINE_DELTA_CAT_FILE_SIZE_INVALID", raw_size)
            body = proc.stdout.read(size)
            terminator = proc.stdout.read(1)
            if len(body) != size or terminator != b"\n":
                _fail("BASELINE_DELTA_CAT_FILE_BODY_INVALID", requested)
            result[requested] = body
        rc = proc.wait(timeout=30)
        if rc != 0:
            stderr = proc.stderr.read().decode("utf-8", "replace").strip()
            _fail("BASELINE_DELTA_CAT_FILE_FAILED", stderr[:500])
        return result
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if proc.stdout is not None:
            proc.stdout.close()
        if proc.stderr is not None:
            proc.stderr.close()


def _validate_report(report: Any, expected_sha: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if not isinstance(report, dict) or report.get("schema_version") != REPORT_SCHEMA_VERSION:
        _fail("BASELINE_DELTA_REPORT_SCHEMA_INVALID")
    if SHA40_RE.fullmatch(expected_sha) is None:
        _fail("BASELINE_DELTA_EXPECTED_SHA_INVALID", expected_sha)
    if report.get("observed_main_sha") != expected_sha:
        _fail("BASELINE_DELTA_REPORT_SHA_MISMATCH")

    repo = report.get("repository")
    edge = report.get("edge")
    if not isinstance(repo, dict) or not isinstance(edge, dict):
        _fail("BASELINE_DELTA_REPORT_SECTION_INVALID")
    if repo.get("observed_main_sha") != expected_sha:
        _fail("BASELINE_DELTA_REPOSITORY_SHA_MISMATCH")
    if repo.get("tree_truncated") is True:
        _fail("BASELINE_DELTA_TREE_TRUNCATED")
    if report.get("pass_unknown_currentness") is not True:
        _fail("BASELINE_DELTA_UNKNOWN_CURRENTNESS")
    if repo.get("unknown_currentness") != 0 or edge.get("unknown_currentness") != 0:
        _fail("BASELINE_DELTA_UNKNOWN_CURRENTNESS")

    repo_records = repo.get("records")
    edge_records = edge.get("records")
    if not isinstance(repo_records, list) or not all(isinstance(x, dict) for x in repo_records):
        _fail("BASELINE_DELTA_REPOSITORY_RECORDS_INVALID")
    if not isinstance(edge_records, list) or not all(isinstance(x, dict) for x in edge_records):
        _fail("BASELINE_DELTA_EDGE_RECORDS_INVALID")

    repo_paths = [str(x.get("path") or "") for x in repo_records]
    edge_slugs = [str(x.get("slug") or "") for x in edge_records]
    if len(repo_paths) != len(set(repo_paths)):
        _fail("BASELINE_DELTA_REPOSITORY_DUPLICATE")
    if len(edge_slugs) != len(set(edge_slugs)):
        _fail("BASELINE_DELTA_EDGE_DUPLICATE")

    for records, section, key in (
        (repo_records, repo, "path"),
        (edge_records, edge, "slug"),
    ):
        actual = Counter(str(row.get("state") or "") for row in records)
        counts = section.get("counts")
        if not isinstance(counts, dict):
            _fail("BASELINE_DELTA_COUNTS_INVALID", key)
        for state in ("CURRENT", "STALE", "MISSING", "NEW", "UNKNOWN"):
            if int(counts.get(state, -1)) != actual.get(state, 0):
                _fail("BASELINE_DELTA_COUNTS_MISMATCH", f"{key}:{state}")
    return repo_records, edge_records


def build_delta(report: Any, repo_root: Path, expected_sha: str) -> dict[str, Any]:
    expected_sha = expected_sha.lower()
    repo_records, edge_records = _validate_report(report, expected_sha)
    head = _git_head(repo_root)
    if head != expected_sha:
        _fail("BASELINE_DELTA_CHECKOUT_SHA_MISMATCH", f"expected={expected_sha}:head={head}")

    tree = _git_tree_map(repo_root, expected_sha)
    repo_delta = [r for r in repo_records if r.get("state") in DELTA_STATES]
    edge_delta = [r for r in edge_records if r.get("state") in DELTA_STATES]

    material_paths: list[str] = []
    path_to_blob: dict[str, str] = {}
    for row in repo_delta:
        path = _safe_repo_path(str(row.get("path") or ""))
        state = str(row.get("state"))
        if state in ("NEW", "STALE"):
            observed_blob = str(row.get("observed_git_blob") or "").lower()
            if SHA40_RE.fullmatch(observed_blob) is None:
                _fail("BASELINE_DELTA_REPO_BLOB_MISSING", path)
            actual_blob = tree.get(path)
            if actual_blob is None or actual_blob != observed_blob:
                _fail("BASELINE_DELTA_REPO_BLOB_MISMATCH", path)
            material_paths.append(path)
            path_to_blob[path] = observed_blob
        elif row.get("observed_git_blob") not in (None, ""):
            _fail("BASELINE_DELTA_MISSING_REPO_STILL_PRESENT", path)

    last_commits = _last_commit_map(repo_root, expected_sha, material_paths)
    blob_bytes = _cat_blob_batch(repo_root, path_to_blob.values())

    items: list[dict[str, Any]] = []
    for row in repo_delta:
        path = str(row["path"])
        state = str(row["state"])
        item: dict[str, Any] = {"source_kind": "REPO", "object_key": path, "state": state}
        if state in ("NEW", "STALE"):
            blob = path_to_blob[path]
            body = blob_bytes.get(blob)
            if body is None:
                _fail("BASELINE_DELTA_REPO_BYTES_MISSING", path)
            last_commit = last_commits.get(path, "")
            if SHA40_RE.fullmatch(last_commit) is None:
                _fail("BASELINE_DELTA_LAST_COMMIT_INVALID", path)
            suffix = PurePosixPath(path).suffix
            item.update(
                {
                    "definition_sha256": _sha256_hex(body),
                    "source_version": last_commit,
                    "git_blob": blob,
                    "bytes": len(body),
                    "extension": suffix[1:].lower() if suffix else None,
                }
            )
        items.append(item)

    for row in edge_delta:
        slug = str(row.get("slug") or "")
        if not slug or "/" in slug or "\x00" in slug:
            _fail("BASELINE_DELTA_EDGE_SLUG_INVALID", repr(slug))
        state = str(row.get("state"))
        item = {"source_kind": "EDGE", "object_key": slug, "state": state}
        if state in ("NEW", "STALE"):
            runtime_hash = str(row.get("runtime_sha256") or "").lower()
            runtime_version = row.get("runtime_version")
            verify_jwt = row.get("verify_jwt")
            source_state = row.get("source_state")
            if SHA64_RE.fullmatch(runtime_hash) is None:
                _fail("BASELINE_DELTA_EDGE_HASH_MISSING", slug)
            if runtime_version in (None, ""):
                _fail("BASELINE_DELTA_EDGE_VERSION_MISSING", slug)
            if not isinstance(verify_jwt, bool):
                _fail("BASELINE_DELTA_EDGE_VERIFY_JWT_INVALID", slug)
            if source_state not in EDGE_SOURCE_STATES:
                _fail("BASELINE_DELTA_EDGE_SOURCE_STATE_INVALID", slug)
            item.update(
                {
                    "definition_sha256": runtime_hash,
                    "source_version": str(runtime_version),
                    "verify_jwt": verify_jwt,
                    "source_state": source_state,
                }
            )
        else:
            if row.get("runtime_sha256") not in (None, ""):
                _fail("BASELINE_DELTA_MISSING_EDGE_STILL_PRESENT", slug)
        items.append(item)

    items.sort(key=lambda x: (x["source_kind"], x["object_key"], x["state"]))
    if len({(x["source_kind"], x["object_key"]) for x in items}) != len(items):
        _fail("BASELINE_DELTA_ITEM_DUPLICATE")

    repo_counts = Counter(x["state"] for x in items if x["source_kind"] == "REPO")
    edge_counts = Counter(x["state"] for x in items if x["source_kind"] == "EDGE")
    report_sha256 = _sha256_hex(_canonical_bytes(report))
    sync_key = _sha256_hex(f"{expected_sha}:{report_sha256}".encode("ascii"))
    runtime_without_source_count = sum(
        1
        for item in items
        if item["source_kind"] == "EDGE"
        and item["state"] in ("NEW", "STALE")
        and item.get("source_state") == "RUNTIME_WITHOUT_SOURCE"
    )

    return {
        "schema_version": SCHEMA_VERSION,
        "observed_main_sha": expected_sha,
        "report_sha256": report_sha256,
        "sync_key": sync_key,
        "expected_item_count": len(items),
        "runtime_without_source_count": runtime_without_source_count,
        "counts": {
            "repository": {state: repo_counts.get(state, 0) for state in ("NEW", "STALE", "MISSING")},
            "edge": {state: edge_counts.get(state, 0) for state in ("NEW", "STALE", "MISSING")},
        },
        "items": items,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--expected-sha", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    try:
        delta = build_delta(_load_json(args.report), args.repo_root, args.expected_sha)
    except DeltaError as exc:
        print(str(exc))
        return 2

    args.output.write_text(
        json.dumps(delta, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "schema_version": delta["schema_version"],
                "sync_key": delta["sync_key"],
                "expected_item_count": delta["expected_item_count"],
                "runtime_without_source_count": delta["runtime_without_source_count"],
                "counts": delta["counts"],
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
