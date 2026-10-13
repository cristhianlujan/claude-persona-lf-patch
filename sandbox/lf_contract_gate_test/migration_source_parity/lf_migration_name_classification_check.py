#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from lf_migration_source_parity_ci_context import (  # noqa: E402
    classified,
    managed,
    reconciliation_source_metadata,
)

FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\.sql$")


def classify_path(
    raw_path: str,
    failure_code: str,
    *,
    allow_reconciliation_source: bool = False,
    root: pathlib.Path | None = None,
) -> tuple[str, str]:
    """Classify one migration path.

    Strict by default (Merge Train pre-apply). With allow_reconciliation_source
    (PR-time check only), an unclassified legacy name is accepted when:
      * the path no longer exists in the tree (deleted/renamed-away source: no
        migration is introduced by it), or
      * the file carries a valid LF_MIGRATION_RECONCILIATION_SOURCE_V1 header bound
        to its exact version and name (same rule the source-parity context applies).
    The Train never passes the flag, so a header cannot admit an unclassified
    migration into an apply.
    """
    path = pathlib.PurePosixPath(raw_path.replace("\\", "/"))
    match = FILENAME_RE.fullmatch(path.name)
    if not match:
        raise ValueError(f"FAIL_MIGRATION_FILENAME:{raw_path}")
    version, name = match.group("version"), match.group("name")
    if classified(name):
        return name, "MANAGED" if managed(name) else "CLASSIFIED_EXTERNAL"
    if allow_reconciliation_source:
        disk = (root or pathlib.Path.cwd()) / pathlib.Path(*path.parts)
        if not disk.exists():
            return name, "REMOVED_SOURCE"
        try:
            sql = disk.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            sql = ""
        if reconciliation_source_metadata(sql, version=version, name=name):
            return name, "RECONCILIATION_SOURCE"
    raise ValueError(f"{failure_code}:{name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify migration filenames using the canonical source-parity classifier.")
    parser.add_argument("--failure-code", default="FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY")
    parser.add_argument(
        "--allow-reconciliation-source",
        action="store_true",
        help="PR-time only: accept removed sources and files with a valid reconciliation header. Never used by the Train.",
    )
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    try:
        for raw_path in args.paths:
            name, classification = classify_path(
                raw_path,
                args.failure_code,
                allow_reconciliation_source=args.allow_reconciliation_source,
            )
            print(f"PASS_MIGRATION_NAME_CLASSIFIED name={name} classification={classification}")
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
