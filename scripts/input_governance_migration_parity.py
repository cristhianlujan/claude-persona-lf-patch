#!/usr/bin/env python3
import argparse
import csv
import hashlib
import pathlib
import re

FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
SCOPED_PREFIXES = ("input_governance_", "programacion_input_governance_")
SCOPED_EXACT = {"retire_b2b_auth005_legacy_totp_screen"}


def is_scoped(name: str) -> bool:
    return name.startswith(SCOPED_PREFIXES) or name in SCOPED_EXACT


def canonical(sql: str) -> bytes:
    sql = sql.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line for line in sql.split("\n") if not line.lstrip().startswith("--")]
    return "\n".join(lines).rstrip("\n").encode("utf-8")


def add_unique(target, version, value, source):
    if version in target:
        raise SystemExit(f"FAIL_INPUT_GOVERNANCE_MIGRATION_DUPLICATE_VERSION: version={version} source={source}")
    target[version] = value


def load_local(migrations: pathlib.Path, cutover: str):
    local = {}
    for path in sorted(migrations.glob("*.sql")):
        match = FILENAME_RE.fullmatch(path.name)
        if not match:
            continue
        version, name = match.groups()
        if version < cutover or not is_scoped(name):
            continue
        add_unique(
            local,
            version,
            (name, hashlib.sha256(canonical(path.read_text(encoding="utf-8"))).hexdigest()),
            path.name,
        )
    return local


def load_remote(remote_csv: pathlib.Path, cutover: str):
    remote = {}
    with remote_csv.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    for row in rows:
        if len(row) != 3:
            raise SystemExit(f"FAIL_INPUT_GOVERNANCE_MIGRATION_LEDGER_ROW: {row!r}")
        version, name, sql_hex = row
        if version < cutover:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_BEFORE_CUTOVER: version={version}"
            )
        if not is_scoped(name):
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_SCOPE: version={version} name={name}"
            )
        try:
            sql = bytes.fromhex(sql_hex).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_LEDGER_SQL: version={version}"
            ) from exc
        add_unique(
            remote,
            version,
            (name, hashlib.sha256(canonical(sql)).hexdigest()),
            f"ledger:{name}",
        )
    return remote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrations", default="supabase/migrations")
    parser.add_argument("--remote", required=True)
    parser.add_argument("--cutover", required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"\d{14}", args.cutover):
        raise SystemExit("FAIL_INPUT_GOVERNANCE_MIGRATION_CUTOVER_FORMAT")

    local = load_local(pathlib.Path(args.migrations), args.cutover)
    remote = load_remote(pathlib.Path(args.remote), args.cutover)

    if not local:
        raise SystemExit("FAIL_INPUT_GOVERNANCE_MIGRATION_LOCAL_EMPTY")
    if not remote:
        raise SystemExit("FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_EMPTY")

    if set(local) != set(remote):
        only_local = sorted(set(local) - set(remote))
        only_remote = sorted(set(remote) - set(local))
        raise SystemExit(
            "FAIL_INPUT_GOVERNANCE_MIGRATION_VERSION_PARITY: "
            f"only_git={only_local} only_remote={only_remote}"
        )

    name_mismatches = [
        version for version in sorted(local)
        if local[version][0] != remote[version][0]
    ]
    if name_mismatches:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_NAME_PARITY: {name_mismatches}"
        )

    content_mismatches = [
        version for version in sorted(local)
        if local[version][1] != remote[version][1]
    ]
    if content_mismatches:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_CONTENT_PARITY: {content_mismatches}"
        )

    digest = hashlib.sha256(
        "\n".join(
            f"{version}|{local[version][0]}|{local[version][1]}"
            for version in sorted(local)
        ).encode("utf-8")
    ).hexdigest()
    print(
        "PASS_INPUT_GOVERNANCE_MIGRATION_SOURCE_PARITY: "
        f"cutover={args.cutover} count={len(local)} sha256={digest}"
    )


if __name__ == "__main__":
    main()
