#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import os
import pathlib
import re
import subprocess

import migration_transport_normalization as transport

FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
SCOPED_PREFIXES = ("input_governance_", "programacion_input_governance_")
SCOPED_EXACT = {"retire_b2b_auth005_legacy_totp_screen"}
SHA_PROOF_RE = re.compile(r"^sha256:([0-9a-f]{64})$")
VERSION_RE = re.compile(r"^20\d{12}$")
PG_ENV_NAMES = ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE")
POSTGRES_IMAGE = "postgres:17.6"


def is_scoped(name: str) -> bool:
    return name.startswith(SCOPED_PREFIXES) or name in SCOPED_EXACT


def canonical(sql: str) -> bytes:
    return transport.canonical(sql)


def add_unique(target, version, value, source):
    if version in target:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_DUPLICATE_VERSION: version={version} source={source}"
        )
    target[version] = value


def content_sha256(field: str, version: str) -> str:
    proof = SHA_PROOF_RE.fullmatch(field)
    if proof:
        return proof.group(1)
    if field.startswith("sha256:"):
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_SHA_PROOF: version={version}"
        )
    try:
        sql = bytes.fromhex(field).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_LEDGER_SQL: version={version}"
        ) from exc
    return hashlib.sha256(canonical(sql)).hexdigest()


def load_local(migrations: pathlib.Path, cutover: str):
    local = {}
    for path in sorted(migrations.glob("*.sql")):
        match = FILENAME_RE.fullmatch(path.name)
        if not match:
            continue
        version, name = match.groups()
        if version < cutover or not is_scoped(name):
            continue
        sql = path.read_text(encoding="utf-8")
        add_unique(
            local,
            version,
            (name, sql, hashlib.sha256(canonical(sql)).hexdigest()),
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
        version, name, content_proof = row
        if not VERSION_RE.fullmatch(version):
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_VERSION_FORMAT: version={version}"
            )
        if version < cutover:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_BEFORE_CUTOVER: version={version}"
            )
        if not is_scoped(name):
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_MIGRATION_REMOTE_SCOPE: version={version} name={name}"
            )
        add_unique(
            remote,
            version,
            (name, content_sha256(content_proof, version)),
            f"ledger:{name}",
        )
    return remote


def _parse_statement_count_rows(text: str, *, source: str):
    counts = {}
    for row in csv.reader(io.StringIO(text)):
        if not row:
            continue
        if len(row) != 2:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_ROW: source={source} row={row!r}"
            )
        version, raw_count = row
        if not VERSION_RE.fullmatch(version):
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_VERSION: source={source} version={version}"
            )
        try:
            count = int(raw_count)
        except ValueError as exc:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_VALUE: source={source} version={version} value={raw_count!r}"
            ) from exc
        if count < 1:
            raise SystemExit(
                f"FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_VALUE: source={source} version={version} value={count}"
            )
        add_unique(counts, version, count, source)
    return counts


def load_statement_counts_csv(path: pathlib.Path):
    return _parse_statement_count_rows(path.read_text(encoding="utf-8"), source=str(path))


def query_remote_statement_counts(versions: list[str]):
    if not versions:
        return {}
    if any(not VERSION_RE.fullmatch(version) for version in versions):
        raise SystemExit("FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_VERSION_SET")
    missing = [name for name in PG_ENV_NAMES if not os.environ.get(name)]
    if missing:
        raise SystemExit(
            "FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_ENV_MISSING: " + ",".join(missing)
        )

    pg_array = "{" + ",".join(versions) + "}"
    sql = (
        "select version,coalesce(cardinality(statements),0)::text "
        "from supabase_migrations.schema_migrations "
        f"where version=any('{pg_array}'::text[]) order by version"
    )
    command = ["docker", "run", "--rm"]
    for name in PG_ENV_NAMES:
        command.extend(["-e", name])
    command.extend(
        [
            POSTGRES_IMAGE,
            "psql",
            "-X",
            "-v",
            "ON_ERROR_STOP=1",
            "--csv",
            "-t",
            "-c",
            sql,
        ]
    )
    try:
        proc = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_QUERY: {type(exc).__name__}"
        ) from exc
    if proc.returncode != 0:
        stderr_sha = hashlib.sha256(proc.stderr.encode("utf-8", "replace")).hexdigest()
        raise SystemExit(
            "FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_QUERY: "
            f"exit={proc.returncode} stderr_sha256={stderr_sha}"
        )
    return _parse_statement_count_rows(proc.stdout, source="remote-ledger")


def _validate_version_sets(local, remote):
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


def evaluate_parity(local, remote, statement_counts):
    _validate_version_sets(local, remote)
    if set(statement_counts) != set(remote):
        only_counts = sorted(set(statement_counts) - set(remote))
        missing_counts = sorted(set(remote) - set(statement_counts))
        raise SystemExit(
            "FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_SET: "
            f"missing={missing_counts} extra={only_counts}"
        )

    name_mismatches = [
        version
        for version in sorted(local)
        if local[version][0] != remote[version][0]
    ]
    if name_mismatches:
        raise SystemExit(
            f"FAIL_INPUT_GOVERNANCE_MIGRATION_NAME_PARITY: {name_mismatches}"
        )

    comparisons = {}
    failures = []
    for version in sorted(local):
        local_name, source_sql, _source_sha = local[version]
        remote_name, remote_sha = remote[version]
        try:
            comparisons[version] = transport.compare_exact_source(
                version=version,
                source_name=local_name,
                source_sql=source_sql,
                remote_name=remote_name,
                remote_sha256=remote_sha,
                remote_statement_count=statement_counts[version],
            )
        except transport.TransportNormalizationError as exc:
            failures.append((version, str(exc)))
    if failures:
        raise SystemExit(
            "FAIL_INPUT_GOVERNANCE_MIGRATION_CONTENT_PARITY: " + repr(failures)
        )

    digest = hashlib.sha256(
        "\n".join(
            f"{version}|{local[version][0]}|{local[version][2]}"
            for version in sorted(local)
        ).encode("utf-8")
    ).hexdigest()
    direct_count = sum(
        item.representation == "DIRECT_SOURCE" for item in comparisons.values()
    )
    cli_count = sum(
        item.representation == "CLI_STATEMENT_STORAGE"
        for item in comparisons.values()
    )
    return digest, comparisons, direct_count, cli_count


def self_test():
    sql = "select 1;\n"
    expected = hashlib.sha256(canonical(sql)).hexdigest()
    if content_sha256("sha256:" + expected, "SELFTEST") != expected:
        raise SystemExit("FAIL_INPUT_GOVERNANCE_COMPACT_SHA_PARSER_SELFTEST")
    if content_sha256(sql.encode("utf-8").hex(), "SELFTEST") != expected:
        raise SystemExit("FAIL_INPUT_GOVERNANCE_LEGACY_HEX_PARSER_SELFTEST")

    direct = transport.compare_exact_source(
        version="20260907010101",
        source_name="input_governance_selftest_direct",
        source_sql="select 1;\n",
        remote_name="input_governance_selftest_direct",
        remote_sha256=transport.direct_source_hash("select 1;\n"),
        remote_statement_count=1,
    )
    if direct.representation != "DIRECT_SOURCE":
        raise SystemExit("FAIL_INPUT_GOVERNANCE_TRANSPORT_DIRECT_SELFTEST")

    cli_sql = "-- header\n\nselect 1;\n"
    cli = transport.compare_exact_source(
        version="20260907010102",
        source_name="input_governance_selftest_cli",
        source_sql=cli_sql,
        remote_name="input_governance_selftest_cli",
        remote_sha256=transport.cli_statement_storage_hash(cli_sql),
        remote_statement_count=1,
    )
    if cli.representation != "CLI_STATEMENT_STORAGE":
        raise SystemExit("FAIL_INPUT_GOVERNANCE_TRANSPORT_CLI_SELFTEST")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrations", default="supabase/migrations")
    parser.add_argument("--remote", required=True)
    parser.add_argument("--cutover", required=True)
    parser.add_argument(
        "--statement-counts",
        help="Optional two-column version,count CSV. If omitted, counts are read-only queried from the same PostgreSQL ledger using the already-exported PG* environment.",
    )
    args = parser.parse_args()

    if not re.fullmatch(r"\d{14}", args.cutover):
        raise SystemExit("FAIL_INPUT_GOVERNANCE_MIGRATION_CUTOVER_FORMAT")

    self_test()
    local = load_local(pathlib.Path(args.migrations), args.cutover)
    remote = load_remote(pathlib.Path(args.remote), args.cutover)
    _validate_version_sets(local, remote)

    if args.statement_counts:
        statement_counts = load_statement_counts_csv(pathlib.Path(args.statement_counts))
    else:
        statement_counts = query_remote_statement_counts(sorted(remote))

    digest, comparisons, direct_count, cli_count = evaluate_parity(
        local, remote, statement_counts
    )
    print(
        "PASS_INPUT_GOVERNANCE_MIGRATION_SOURCE_PARITY_COMPACT: "
        f"cutover={args.cutover} count={len(local)} sha256={digest} "
        f"direct={direct_count} cli_statement_storage={cli_count}"
    )
    for version in sorted(comparisons):
        comparison = comparisons[version]
        print(
            "PASS_INPUT_GOVERNANCE_MIGRATION_TRANSPORT: "
            f"version={version} representation={comparison.representation} "
            f"remote_statements={comparison.remote_statement_count}"
        )


if __name__ == "__main__":
    main()
