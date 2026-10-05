#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re

FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\.sql$")
VERSION_RE = re.compile(r"^\d{14}$")


@dataclass(frozen=True)
class Assignment:
    old_path: Path
    new_path: Path
    version: str
    changed: bool


def _require_version(value: str, label: str) -> str:
    value = (value or "").strip()
    if VERSION_RE.fullmatch(value) is None:
        raise ValueError(f"{label}_INVALID:{value!r}")
    datetime.strptime(value, "%Y%m%d%H%M%S")
    return value


def _plus_one_second(version: str) -> str:
    dt = datetime.strptime(version, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
    return (dt + timedelta(seconds=1)).strftime("%Y%m%d%H%M%S")


def choose_version(
    *,
    current_version: str,
    main_max_version: str,
    ledger_max_version: str,
    utc_now_version: str,
) -> str:
    current = _require_version(current_version, "CURRENT_VERSION")
    main_max = _require_version(main_max_version, "MAIN_MAX_VERSION")
    ledger_max = _require_version(ledger_max_version, "LEDGER_MAX_VERSION")
    now = _require_version(utc_now_version, "UTC_NOW_VERSION")
    floor = max(main_max, ledger_max)

    # Idempotent retry: a candidate already strictly above the live floor stays put.
    if current > floor:
        return current
    if now > floor:
        return now
    return _plus_one_second(floor)


def assign_path(
    migration_path: Path,
    *,
    main_max_version: str,
    ledger_max_version: str,
    utc_now_version: str,
    perform_rename: bool = True,
) -> Assignment:
    match = FILENAME_RE.fullmatch(migration_path.name)
    if match is None:
        raise ValueError(f"MIGRATION_FILENAME_INVALID:{migration_path.name}")
    if not migration_path.is_file():
        raise FileNotFoundError(migration_path)

    version = choose_version(
        current_version=match.group("version"),
        main_max_version=main_max_version,
        ledger_max_version=ledger_max_version,
        utc_now_version=utc_now_version,
    )
    target = migration_path.with_name(f"{version}_{match.group('name')}.sql")
    changed = target != migration_path

    if changed and target.exists():
        raise FileExistsError(f"MIGRATION_TARGET_COLLISION:{target}")
    if changed and perform_rename:
        migration_path.rename(target)

    return Assignment(migration_path, target, version, changed)


def _utc_now_version() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("migration_path")
    parser.add_argument("--main-max", required=True)
    parser.add_argument("--ledger-max", required=True)
    parser.add_argument("--utc-now")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    result = assign_path(
        Path(args.migration_path),
        main_max_version=args.main_max,
        ledger_max_version=args.ledger_max,
        utc_now_version=args.utc_now or _utc_now_version(),
        perform_rename=not args.dry_run,
    )
    print(
        "PASS_MIGRATION_ASSIGN_VERSION "
        f"changed={str(result.changed).lower()} "
        f"version={result.version} "
        f"path={result.new_path.as_posix()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
