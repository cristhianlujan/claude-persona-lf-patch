#!/usr/bin/env python3
"""Read-only detector for LF external inventory currentness.

This tool compares already-fetched snapshots. It performs no network or database
writes. Live acquisition and persistence are intentionally separate concerns.

Repository states:
- CURRENT: inventory git_blob equals the blob in observed main.
- STALE: path exists in main but blob differs.
- MISSING: inventory path no longer exists in observed main.
- NEW: path exists in observed main but is absent from inventory.
- UNKNOWN: diagnostic error state only; an inventory row lacks comparison data.

Edge currentness uses definition_sha256 against runtime ezbr_sha256 as the code
authority. Runtime version is informational only and version_drift reports whether
inventory/runtime version labels differ without affecting CURRENT/STALE. Runtime/source
traceability is reported as a separate dimension:
- SOURCE_PRESENT: main contains at least one blob under supabase/functions/<slug>/.
- RUNTIME_WITHOUT_SOURCE: the function is deployed but no source directory exists
  on the observed main tree. This is debt evidence only; A4a does not retire it.

Every report hashes the exact five comparison inputs using canonical JSON SHA-256,
so the dry-run result can be reproduced against the same evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

KNOWN_STATES = ("CURRENT", "STALE", "MISSING", "NEW")
DIAGNOSTIC_STATE = "UNKNOWN"
EDGE_SOURCE_PRESENT = "SOURCE_PRESENT"
EDGE_RUNTIME_WITHOUT_SOURCE = "RUNTIME_WITHOUT_SOURCE"
INPUT_DIGEST_CONTRACT = "SHA256_CANONICAL_JSON_V1"


def _load(path: str) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _digest(value: Any) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _rows(value: Any, preferred_key: str | None = None) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return value
    if not isinstance(value, dict):
        raise ValueError("snapshot must be a JSON object or array")
    if preferred_key and isinstance(value.get(preferred_key), list):
        return value[preferred_key]
    for key in ("rows", "objects", "result", "data"):
        if isinstance(value.get(key), list):
            return value[key]
    raise ValueError("could not locate row array in snapshot")


def _repo_path(row: dict[str, Any]) -> str:
    path = row.get("path")
    if isinstance(path, str) and path:
        return path
    ref = row.get("object_ref")
    if isinstance(ref, str) and ref.startswith("repo://"):
        return ref[len("repo://") :]
    raise ValueError(f"repository inventory row lacks path/object_ref: {row!r}")


def _repo_blob(row: dict[str, Any]) -> str | None:
    blob = row.get("git_blob")
    if isinstance(blob, str) and blob:
        return blob
    metadata = row.get("metadata")
    if isinstance(metadata, dict):
        blob = metadata.get("git_blob")
        if isinstance(blob, str) and blob:
            return blob
    return None


def _edge_slug(row: dict[str, Any]) -> str:
    slug = row.get("slug")
    if isinstance(slug, str) and slug:
        return slug
    ref = row.get("object_ref")
    if isinstance(ref, str) and ref.startswith("edge://"):
        return ref[len("edge://") :]
    raise ValueError(f"edge inventory row lacks slug/object_ref: {row!r}")


def _in_scope(path: str, policy: dict[str, Any]) -> bool:
    repo_policy = policy.get("repository", {})
    exclude_prefixes = tuple(repo_policy.get("exclude_prefixes", []))
    include_prefixes = tuple(repo_policy.get("include_prefixes", []))
    if exclude_prefixes and path.startswith(exclude_prefixes):
        return False
    if repo_policy.get("mode") == "ALL_GIT_BLOBS":
        return True
    return bool(include_prefixes) and path.startswith(include_prefixes)


def _edge_source_root(policy: dict[str, Any]) -> str:
    root = policy.get("edge_runtime", {}).get(
        "source_root", "supabase/functions/"
    )
    if not isinstance(root, str) or not root:
        raise ValueError("edge_runtime.source_root must be a non-empty string")
    return root if root.endswith("/") else root + "/"


def _count(records: Iterable[dict[str, Any]]) -> dict[str, int]:
    counts = Counter(record["state"] for record in records)
    return {
        state: counts.get(state, 0)
        for state in (*KNOWN_STATES, DIAGNOSTIC_STATE)
    }


def detect_repository(
    git_tree: dict[str, Any],
    inventory_snapshot: Any,
    policy: dict[str, Any],
) -> dict[str, Any]:
    tree_entries = git_tree.get("tree")
    if not isinstance(tree_entries, list):
        raise ValueError("git tree snapshot must contain a tree array")

    main_blobs = {
        entry["path"]: entry["sha"]
        for entry in tree_entries
        if entry.get("type") == "blob"
        and isinstance(entry.get("path"), str)
        and isinstance(entry.get("sha"), str)
        and _in_scope(entry["path"], policy)
    }

    inventory_rows = _rows(inventory_snapshot)
    inventory_by_path: dict[str, dict[str, Any]] = {}
    records: list[dict[str, Any]] = []

    for row in inventory_rows:
        path = _repo_path(row)
        if not _in_scope(path, policy):
            continue
        inventory_by_path[path] = row
        stored_blob = _repo_blob(row)
        observed_blob = main_blobs.get(path)
        if not stored_blob:
            state = DIAGNOSTIC_STATE
        elif observed_blob is None:
            state = "MISSING"
        elif stored_blob == observed_blob:
            state = "CURRENT"
        else:
            state = "STALE"
        records.append(
            {
                "path": path,
                "state": state,
                "inventory_active": row.get("active"),
                "inventory_git_blob": stored_blob,
                "observed_git_blob": observed_blob,
            }
        )

    for path, observed_blob in main_blobs.items():
        if path not in inventory_by_path:
            records.append(
                {
                    "path": path,
                    "state": "NEW",
                    "inventory_active": None,
                    "inventory_git_blob": None,
                    "observed_git_blob": observed_blob,
                }
            )

    records.sort(key=lambda item: (item["state"], item["path"]))
    counts = _count(records)
    return {
        "observed_main_sha": git_tree.get("sha"),
        "tree_truncated": bool(git_tree.get("truncated", False)),
        "counts": counts,
        "known_inventory_objects": sum(
            1 for record in records if record["state"] != "NEW"
        ),
        "observed_main_blobs": len(main_blobs),
        "unknown_currentness": counts[DIAGNOSTIC_STATE],
        "pass_unknown_currentness": counts[DIAGNOSTIC_STATE] == 0
        and not bool(git_tree.get("truncated", False)),
        "records": records,
    }


def detect_edge(
    git_tree: dict[str, Any],
    runtime_snapshot: Any,
    inventory_snapshot: Any,
    policy: dict[str, Any],
) -> dict[str, Any]:
    tree_entries = git_tree.get("tree")
    if not isinstance(tree_entries, list):
        raise ValueError("git tree snapshot must contain a tree array")
    main_paths = {
        entry["path"]
        for entry in tree_entries
        if entry.get("type") == "blob" and isinstance(entry.get("path"), str)
    }

    source_root = _edge_source_root(policy)
    live_rows = _rows(runtime_snapshot, "functions")
    inventory_rows = _rows(inventory_snapshot)

    live_by_slug = {
        row["slug"]: row
        for row in live_rows
        if isinstance(row.get("slug"), str) and row["slug"]
    }
    inventory_by_slug: dict[str, dict[str, Any]] = {}
    records: list[dict[str, Any]] = []

    def source_state(slug: str) -> str:
        prefix = f"{source_root}{slug}/"
        return (
            EDGE_SOURCE_PRESENT
            if any(path.startswith(prefix) for path in main_paths)
            else EDGE_RUNTIME_WITHOUT_SOURCE
        )

    for row in inventory_rows:
        slug = _edge_slug(row)
        inventory_by_slug[slug] = row
        live = live_by_slug.get(slug)
        stored_version = row.get("source_version")
        stored_hash = row.get("definition_sha256")
        runtime_version = live.get("version") if live else None
        runtime_hash = live.get("ezbr_sha256") if live else None
        version_drift = str(stored_version) != str(runtime_version)
        if live is None:
            state = "MISSING"
            runtime_source_state = None
        elif stored_hash in (None, "") or runtime_hash in (None, ""):
            state = DIAGNOSTIC_STATE
            runtime_source_state = source_state(slug)
        elif stored_hash == runtime_hash:
            state = "CURRENT"
            runtime_source_state = source_state(slug)
        else:
            state = "STALE"
            runtime_source_state = source_state(slug)
        records.append(
            {
                "slug": slug,
                "state": state,
                "source_state": runtime_source_state,
                "verify_jwt": live.get("verify_jwt") if live else None,
                "inventory_active": row.get("active"),
                "inventory_version": stored_version,
                "runtime_version": runtime_version,
                "version_drift": version_drift,
                "inventory_sha256": stored_hash,
                "runtime_sha256": runtime_hash,
            }
        )

    for slug, live in live_by_slug.items():
        if slug not in inventory_by_slug:
            records.append(
                {
                    "slug": slug,
                    "state": "NEW",
                    "source_state": source_state(slug),
                    "verify_jwt": live.get("verify_jwt"),
                    "inventory_active": None,
                    "inventory_version": None,
                    "runtime_version": live.get("version"),
                    "version_drift": live.get("version") not in (None, ""),
                    "inventory_sha256": None,
                    "runtime_sha256": live.get("ezbr_sha256"),
                }
            )

    records.sort(key=lambda item: (item["state"], item["slug"]))
    counts = _count(records)
    runtime_without_source = [
        record
        for record in records
        if record.get("source_state") == EDGE_RUNTIME_WITHOUT_SOURCE
    ]
    return {
        "counts": counts,
        "inventory_objects": len(inventory_by_slug),
        "runtime_functions": len(live_by_slug),
        "source_root": source_root,
        "runtime_without_source_count": len(runtime_without_source),
        "runtime_without_source_verify_jwt_false_count": sum(
            1
            for record in runtime_without_source
            if record.get("verify_jwt") is False
        ),
        "runtime_without_source": [
            record["slug"] for record in runtime_without_source
        ],
        "unknown_currentness": counts[DIAGNOSTIC_STATE],
        "pass_unknown_currentness": counts[DIAGNOSTIC_STATE] == 0,
        "records": records,
    }


def build_report(
    git_tree: dict[str, Any],
    repo_inventory: Any,
    edge_runtime: Any,
    edge_inventory: Any,
    policy: dict[str, Any],
) -> dict[str, Any]:
    repository = detect_repository(git_tree, repo_inventory, policy)
    edge = detect_edge(git_tree, edge_runtime, edge_inventory, policy)
    return {
        "schema_version": "LF_EXTERNAL_CURRENTNESS_REPORT_V1",
        "mode": "DRY_RUN_READ_ONLY",
        "scope_policy_version": policy.get("schema_version"),
        "input_digest_contract": INPUT_DIGEST_CONTRACT,
        "input_sha256": {
            "git_tree": _digest(git_tree),
            "repo_inventory": _digest(repo_inventory),
            "edge_runtime": _digest(edge_runtime),
            "edge_inventory": _digest(edge_inventory),
            "scope_policy": _digest(policy),
        },
        "repository": repository,
        "edge": edge,
        "pass_unknown_currentness": (
            repository["pass_unknown_currentness"]
            and edge["pass_unknown_currentness"]
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--git-tree", required=True)
    parser.add_argument("--repo-inventory", required=True)
    parser.add_argument("--edge-runtime", required=True)
    parser.add_argument("--edge-inventory", required=True)
    parser.add_argument("--scope-policy", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    report = build_report(
        _load(args.git_tree),
        _load(args.repo_inventory),
        _load(args.edge_runtime),
        _load(args.edge_inventory),
        _load(args.scope_policy),
    )
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0 if report["pass_unknown_currentness"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
