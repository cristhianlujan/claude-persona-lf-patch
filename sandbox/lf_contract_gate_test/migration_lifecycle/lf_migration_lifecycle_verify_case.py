#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True, type=Path)
    parser.add_argument("--migrations-dir", required=True, type=Path)
    args = parser.parse_args()

    case = json.loads(args.case.read_text(encoding="utf-8"))
    items = case.get("items")
    if not isinstance(items, list) or not items:
        raise SystemExit("FAIL_MIGRATION_LIFECYCLE_CASE_ITEMS")

    expected_count = case.get("expected_remote_only_count")
    if expected_count != len(items):
        raise SystemExit(
            f"FAIL_MIGRATION_LIFECYCLE_CASE_COUNT expected={expected_count} items={len(items)}"
        )

    seen: set[str] = set()
    verified: list[dict[str, object]] = []
    for item in items:
        version = item["version"]
        name = item["name"]
        if version in seen:
            raise SystemExit(f"FAIL_MIGRATION_LIFECYCLE_CASE_DUPLICATE_VERSION={version}")
        seen.add(version)
        path = args.migrations_dir / f"{version}_{name}.sql"
        if not path.is_file():
            raise SystemExit(f"FAIL_MIGRATION_LIFECYCLE_CASE_FILE_MISSING={path}")
        raw = path.read_bytes()
        actual = {
            "bytes": len(raw),
            "git_blob_sha1": git_blob_sha1(raw),
            "sha256": sha256(raw),
        }
        for key, value in actual.items():
            if value != item[key]:
                raise SystemExit(
                    f"FAIL_MIGRATION_LIFECYCLE_CASE_{key.upper()}={version}:"
                    f"expected={item[key]}:actual={value}"
                )
        verified.append({"version": version, **actual})

    print(
        json.dumps(
            {
                "state": "PASS",
                "case_id": case.get("case_id"),
                "verified_count": len(verified),
                "verified": verified,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
