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

Edge states use source_version + definition_sha256 against runtime version +
ezbr_sha256 with the same semantics.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

KNOWN_STATES = ("CURRENT", "STALE", "MISSING", "NEW")
DIAGNOSTIC_STATE = "UNKNOWN"


def _load(path: str) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


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
    runtime_snapshot: Any,
    inventory_snapshot: Any,
) -> dict[str, Any]:
    live_rows = _rows(runtime_snapshot, "functions")
    inventory_rows = _rows(inventory_snapshot)

    live_by_slug = {
        row["slug"]: row
        for row in live_rows
        if isinstance(row.get("slug"), str) and row["slug"]
    }
    inventory_by_slug: dict[str, dict[str, Any]] = {}
    records: list[dict[str, Any]] = []

    for row in inventory_rows:
        slug = _edge_slug(row)
        inventory_by_slug[slug] = row
        live = live_by_slug.get(slug)
        stored_version = row.get("source_version")
        stored_hash = row.get("definition_sha256")
        if live is None:
            state = "MISSING"
        elif stored_version in (None, "") or stored_hash in (None, ""):
            state = DIAGNOSTIC_STATE
        elif (
            str(stored_version) == str(live.get("version"))
            and stored_hash == live.get("ezbr_sha256")
        ):
            state = "CURRENT"
        else:
            state = "STALE"
        records.append(
            {
                "slug": slug,
                "state": state,
                "inventory_active": row.get("active"),
                "inventory_version": stored_version,
                "runtime_version": live.get("version") if live else None,
                "inventory_sha256": stored_hash,
                "runtime_sha256": live.get("ezbr_sha256") if live else None,
            }
        )

    for slug, live in live_by_slug.items():
        if slug not in inventory_by_slug:
            records.append(
                {
                    "slug": slug,
                    "state": "NEW",
                    "inventory_active": None,
                    "inventory_version": None,
                    "runtime_version": live.get("version"),
                    "inventory_sha256": None,
                    "runtime_sha256": live.get("ezbr_sha256"),
                }
            )

    records.sort(key=lambda item: (item["state"], item["slug"]))
    counts = _count(records)
    return {
        "counts": counts,
        "inventory_objects": len(inventory_by_slug),
        "runtime_functions": len(live_by_slug),
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
    edge = detect_edge(edge_runtime, edge_inventory)
    return {
        "schema_version": "LF_EXTERNAL_CURRENTNESS_REPORT_V1",
        "mode": "DRY_RUN_READ_ONLY",
        "scope_policy_version": policy.get("schema_version"),
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
