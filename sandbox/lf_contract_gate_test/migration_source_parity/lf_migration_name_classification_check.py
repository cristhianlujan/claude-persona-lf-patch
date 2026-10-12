#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from lf_migration_source_parity_ci_context import classified, managed  # noqa: E402

FILENAME_RE = re.compile(r"^\\d{14}_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\\.sql$")


def classify_path(raw_path: str, failure_code: str) -> tuple[str, str]:
    path = pathlib.PurePosixPath(raw_path.replace("\\\\", "/"))
    match = FILENAME_RE.fullmatch(path.name)
    if not match:
        raise ValueError(f"FAIL_MIGRATION_FILENAME:{raw_path}")
    name = match.group("name")
    if not classified(name):
        raise ValueError(f"{failure_code}:{name}")
    return name, "MANAGED" if managed(name) else "CLASSIFIED_EXTERNAL"


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify migration filenames using the canonical source-parity classifier.")
    parser.add_argument("--failure-code", default="FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    try:
        for raw_path in args.paths:
            name, classification = classify_path(raw_path, args.failure_code)
            print(f"PASS_MIGRATION_NAME_CLASSIFIED name={name} classification={classification}")
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
