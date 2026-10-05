#!/usr/bin/env python3
"""Deterministic migration-version ordering check.

Pure checker only: callers resolve the PR's newly-added migration paths and the
current maxima from main and the Supabase migration ledger.
"""
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass

PASS = "PASS"
FAIL_NOT_MONOTONIC = "FAIL_MIGRATION_VERSION_NOT_MONOTONIC"
FAIL_MULTIPLE = "FAIL_MIGRATION_MULTIPLE_PER_PR"

VERSION_RE = re.compile(r"^\d{14}$")
MIGRATION_PATH_RE = re.compile(
    r"^supabase/migrations/(?P<version>\d{14})_[A-Za-z0-9][A-Za-z0-9_]*\.sql$"
)


@dataclass(frozen=True)
class Verdict:
    code: str
    exit_code: int


def _require_version(value: str, label: str) -> str:
    value = (value or "").strip()
    if VERSION_RE.fullmatch(value) is None:
        raise ValueError(f"{label}_INVALID")
    return value


def evaluate(
    new_migration_paths: list[str],
    *,
    main_max_version: str,
    ledger_max_version: str,
) -> Verdict:
    main_max = _require_version(main_max_version, "MAIN_MAX_VERSION")
    ledger_max = _require_version(ledger_max_version, "LEDGER_MAX_VERSION")

    normalized = [path.replace("\\", "/").strip() for path in new_migration_paths if path.strip()]
    if not normalized:
        return Verdict(PASS, 0)
    if len(normalized) > 1:
        return Verdict(FAIL_MULTIPLE, 2)

    match = MIGRATION_PATH_RE.fullmatch(normalized[0])
    if match is None:
        return Verdict(FAIL_NOT_MONOTONIC, 2)

    candidate = match.group("version")
    floor = max(main_max, ledger_max)
    if candidate <= floor:
        return Verdict(FAIL_NOT_MONOTONIC, 2)
    return Verdict(PASS, 0)


def self_test() -> None:
    base = "20261005190000"
    ledger = "20261005193000"
    assert evaluate([], main_max_version=base, ledger_max_version=ledger).code == PASS
    assert evaluate(
        ["supabase/migrations/20261005192959_probe.sql"],
        main_max_version=base,
        ledger_max_version=ledger,
    ).code == FAIL_NOT_MONOTONIC
    assert evaluate(
        ["supabase/migrations/20261005193000_probe.sql"],
        main_max_version=base,
        ledger_max_version=ledger,
    ).code == FAIL_NOT_MONOTONIC
    assert evaluate(
        ["supabase/migrations/20261005193001_probe.sql"],
        main_max_version=base,
        ledger_max_version=ledger,
    ).code == PASS
    assert evaluate(
        [
            "supabase/migrations/20261005193001_a.sql",
            "supabase/migrations/20261005193002_b.sql",
        ],
        main_max_version=base,
        ledger_max_version=ledger,
    ).code == FAIL_MULTIPLE
    print("PASS_MIGRATION_VERSION_ORDER_CHECK_SELFTEST")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--new-migration", action="append", default=[])
    parser.add_argument("--main-max")
    parser.add_argument("--ledger-max")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    if not args.main_max or not args.ledger_max:
        parser.error("--main-max and --ledger-max are required")

    verdict = evaluate(
        args.new_migration,
        main_max_version=args.main_max,
        ledger_max_version=args.ledger_max,
    )
    print(verdict.code)
    return verdict.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
