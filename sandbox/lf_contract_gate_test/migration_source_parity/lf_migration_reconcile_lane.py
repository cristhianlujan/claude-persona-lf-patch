#!/usr/bin/env python3
"""Read-only verifier for source-only migration reconciliation PRs.

The ledger input is either a JSON snapshot with schema
``lf-migration-reconcile-ledger-snapshot/v1`` and ``rows`` containing
``version``, ``name`` and ``statements`` (a list of SQL statement strings), or
a PostgreSQL URL supplied through the environment variable named by
``--database-url-env``.  Database access is a single SELECT and the session is
forced read-only with PGOPTIONS.  This tool never applies SQL or writes to Git
or Supabase.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

HERE = Path(__file__).resolve().parent
CONTRACT_GATE = HERE.parent
for import_path in (CONTRACT_GATE, HERE):
    if str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))
import migration_transport_normalization as transport
from lf_migration_source_parity_ci_context import classified, reconciliation_source_metadata

RECEIPT_SCHEMA = "lf-migration-reconcile-lane-receipt/v1"
LEDGER_SCHEMA = "lf-migration-reconcile-ledger-snapshot/v1"
MIGRATIONS_DIR = "supabase/migrations/"
FILENAME_RE = re.compile(r"^(20\d{12})_(.+)\.sql$")
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
MAX_BATCH = 100
OWNER_DECISION_PENDING_NAME_SUFFIXES = ("lf_pilot_srcr_g12",)
PASS, FAIL, BLOCKED = 0, 1, 2


class LaneFailure(RuntimeError):
    """The supplied Git change does not satisfy source-only reconciliation."""


class LaneBlocked(RuntimeError):
    """The verifier cannot establish a trustworthy comparison."""


@dataclass(frozen=True)
class LedgerEntry:
    version: str
    name: str
    statements: tuple[str, ...]
    statement_count: int

    @property
    def canonical_hash(self) -> str:
        return transport.direct_source_hash("\n".join(self.statements))


@dataclass(frozen=True)
class Change:
    status: str
    path: str
    previous_path: str | None = None


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(
            ["git", *args], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False, timeout=45,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise LaneBlocked(f"GIT_READ_FAILED:{type(exc).__name__}") from exc
    if check and result.returncode != 0:
        raise LaneBlocked(f"GIT_READ_FAILED:{args[0] if args else 'command'}")
    return result


def _require_sha(value: str, label: str) -> str:
    value = (value or "").strip().lower()
    if SHA40_RE.fullmatch(value) is None:
        raise LaneBlocked(f"SHA_INVALID:{label}")
    return value


def _parse_filename(path: str) -> tuple[str, str]:
    normalized = PurePosixPath(path).as_posix()
    if not normalized.startswith(MIGRATIONS_DIR):
        raise LaneFailure(f"PATH_OUTSIDE_MIGRATIONS:{path}")
    match = FILENAME_RE.fullmatch(PurePosixPath(normalized).name)
    if match is None:
        raise LaneFailure(f"MIGRATION_FILENAME_INVALID:{path}")
    return match.group(1), match.group(2)


def _read_git_blob(repo: Path, sha: str, path: str) -> tuple[str, str]:
    blob = _git(repo, "show", f"{sha}:{path}")
    try:
        sql = blob.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise LaneFailure(f"SQL_SOURCE_NOT_UTF8:{path}") from exc
    oid = _git(repo, "rev-parse", f"{sha}:{path}").stdout.decode().strip().lower()
    if SHA40_RE.fullmatch(oid) is None:
        raise LaneBlocked(f"GIT_BLOB_SHA_INVALID:{path}")
    return sql, oid


def _parse_diff(repo: Path, base_sha: str, head_sha: str) -> list[Change]:
    result = _git(repo, "diff", "--name-status", "-z", "--find-renames", base_sha, head_sha, "--")
    try:
        fields = result.stdout.decode("utf-8", errors="strict").split("\0")
    except UnicodeDecodeError as exc:
        raise LaneFailure("GIT_PATH_NOT_UTF8") from exc
    if fields and fields[-1] == "":
        fields.pop()
    changes: list[Change] = []
    i = 0
    while i < len(fields):
        status = fields[i]
        i += 1
        if status.startswith("R") or status.startswith("C"):
            if i + 1 >= len(fields):
                raise LaneBlocked("GIT_DIFF_MALFORMED")
            previous, path = fields[i], fields[i + 1]
            i += 2
            changes.append(Change(status[0], path, previous))
        else:
            if i >= len(fields):
                raise LaneBlocked("GIT_DIFF_MALFORMED")
            path = fields[i]
            i += 1
            changes.append(Change(status[0], path))
    return changes


def _load_ledger_json(path: Path) -> list[LedgerEntry]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise LaneBlocked("LEDGER_JSON_UNREADABLE") from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != LEDGER_SCHEMA:
        raise LaneBlocked("LEDGER_JSON_SCHEMA_INVALID")
    rows = payload.get("rows")
    if not isinstance(rows, list):
        raise LaneBlocked("LEDGER_JSON_ROWS_INVALID")
    entries: list[LedgerEntry] = []
    for row in rows:
        if not isinstance(row, dict):
            raise LaneBlocked("LEDGER_JSON_ROW_INVALID")
        version, name, statements = row.get("version"), row.get("name"), row.get("statements")
        if (not isinstance(version, str) or not re.fullmatch(r"20\d{12}", version)
                or not isinstance(name, str) or not name or not isinstance(statements, list)
                or not statements or any(not isinstance(s, str) for s in statements)):
            raise LaneBlocked("LEDGER_JSON_ROW_INVALID")
        entries.append(LedgerEntry(version, name, tuple(statements), len(statements)))
    _validate_ledger_entries(entries)
    return entries


def _load_ledger_database(env_name: str) -> list[LedgerEntry]:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", env_name or ""):
        raise LaneBlocked("DATABASE_URL_ENV_NAME_INVALID")
    dsn = os.environ.get(env_name, "").strip()
    if not (dsn.startswith("postgres://") or dsn.startswith("postgresql://")):
        raise LaneBlocked("READ_ONLY_DATABASE_URL_MISSING_OR_INVALID")
    sql = (
        "select version,coalesce(name,''),coalesce(cardinality(statements),0),"
        "encode(convert_to(coalesce(array_to_string(statements,E'\\n'),''),'UTF8'),'hex') "
        "from supabase_migrations.schema_migrations order by version"
    )
    env = dict(os.environ)
    env["PGOPTIONS"] = "-c default_transaction_read_only=on"
    env["PGCONNECT_TIMEOUT"] = "10"
    try:
        result = subprocess.run(
            ["psql", dsn, "-X", "-A", "-t", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", sql],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=30, env=env,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise LaneBlocked(f"READ_ONLY_LEDGER_QUERY_FAILED:{type(exc).__name__}") from exc
    if result.returncode != 0:
        # Do not include stderr: libpq/psql errors can echo the secret connection URL.
        raise LaneBlocked(f"READ_ONLY_LEDGER_QUERY_FAILED:exit={result.returncode}")
    entries: list[LedgerEntry] = []
    try:
        for raw in result.stdout.decode("utf-8").splitlines():
            if not raw:
                continue
            version, name, count_text, statements_hex = raw.split("\t", 3)
            statements_sql = bytes.fromhex(statements_hex).decode("utf-8")
            statement_count = int(count_text)
            statements = (statements_sql,) if statement_count else ()
            entries.append(LedgerEntry(version, name, statements, statement_count))
    except (ValueError, UnicodeDecodeError) as exc:
        raise LaneBlocked("READ_ONLY_LEDGER_RESULT_INVALID") from exc
    _validate_ledger_entries(entries, allow_empty=True)
    return entries


def _validate_ledger_entries(entries: list[LedgerEntry], *, allow_empty: bool = False) -> None:
    if not entries and not allow_empty:
        raise LaneBlocked("LEDGER_EMPTY")
    seen: set[str] = set()
    for entry in entries:
        if not re.fullmatch(r"20\d{12}", entry.version) or not entry.name:
            raise LaneBlocked("LEDGER_ROW_INVALID")
        if entry.statement_count < 1 or not entry.statements:
            raise LaneBlocked(f"LEDGER_STATEMENTS_EMPTY:{entry.version}")
        if entry.version in seen:
            raise LaneBlocked(f"LEDGER_VERSION_DUPLICATE:{entry.version}")
        seen.add(entry.version)
        try:
            # Exercise the canonical lexer for malformed/unusable statements.
            transport.split_postgres_statements("\n".join(entry.statements))
        except transport.TransportNormalizationError as exc:
            raise LaneBlocked(f"LEDGER_SQL_INVALID:{entry.version}") from exc


def _ledger_map(entries: list[LedgerEntry]) -> dict[str, LedgerEntry]:
    return {row.version: row for row in entries}


def _entry_result(
    *, path: str, version: str, name: str, git_hash: str, git_sql: str,
    ledger: LedgerEntry | None, verdict: str,
) -> dict[str, str]:
    return {
        "path": path,
        "version": version,
        "name": name,
        "git_hash": git_hash,
        "ledger_hash": ledger.canonical_hash if ledger else "NOT_APPLICABLE",
        "canonical_git_hash": transport.direct_source_hash(git_sql),
        "verdict": verdict,
    }


def _match_destination(
    *, path: str, sql: str, git_hash: str, ledger_by_version: dict[str, LedgerEntry],
) -> tuple[LedgerEntry, dict[str, str]]:
    version, name = _parse_filename(path)
    ledger = ledger_by_version.get(version)
    if ledger is None:
        raise LaneFailure(f"VERSION_OUTSIDE_LEDGER:{version}:{path}")
    if ledger.name != name:
        raise LaneFailure(f"LEDGER_NAME_MISMATCH:{version}:{name}:{ledger.name}")
    if any(name == suffix or name.endswith("_" + suffix)
           for suffix in OWNER_DECISION_PENDING_NAME_SUFFIXES):
        raise LaneFailure(f"OWNER_NAME_DECISION_PENDING:{name}")
    if not classified(name) and not reconciliation_source_metadata(sql, version=version, name=name):
        raise LaneFailure(f"MIGRATION_NAME_UNCLASSIFIED:{version}:{name}")
    try:
        transport.compare_exact_source(
            version=version, source_name=name, source_sql=sql,
            remote_name=ledger.name, remote_sha256=ledger.canonical_hash,
            remote_statement_count=ledger.statement_count,
        )
    except transport.TransportNormalizationError as exc:
        raise LaneFailure(f"LEDGER_CONTENT_MISMATCH:{version}:{exc}") from exc
    return ledger, _entry_result(
        path=path, version=version, name=name, git_hash=git_hash, git_sql=sql,
        ledger=ledger, verdict="PASS_LEDGER_EXACT",
    )


def _is_exact_ledger_source(path: str, sql: str, ledger_by_version: dict[str, LedgerEntry]) -> bool:
    try:
        version, name = _parse_filename(path)
    except LaneFailure:
        return False
    ledger = ledger_by_version.get(version)
    if ledger is None or ledger.name != name:
        return False
    try:
        transport.compare_exact_source(
            version=version, source_name=name, source_sql=sql,
            remote_name=ledger.name, remote_sha256=ledger.canonical_hash,
            remote_statement_count=ledger.statement_count,
        )
    except transport.TransportNormalizationError:
        return False
    return True


def _head_versions(repo: Path, head_sha: str) -> None:
    tree = _git(repo, "ls-tree", "-r", "--name-only", head_sha, "--", MIGRATIONS_DIR)
    seen: dict[str, str] = {}
    try:
        paths = tree.stdout.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError as exc:
        raise LaneBlocked("HEAD_TREE_PATH_NOT_UTF8") from exc
    for raw in paths:
        if not raw.endswith(".sql"):
            continue
        try:
            version, _name = _parse_filename(raw)
        except LaneFailure:
            # Existing unrelated legacy paths are not a new change; changed files are strict.
            continue
        if version in seen:
            raise LaneFailure(f"HEAD_DUPLICATE_VERSION:{version}:{seen[version]}:{raw}")
        seen[version] = raw


def _pair_deletions(
    changes: list[Change], repo: Path, base_sha: str, head_sha: str,
    ledger_by_version: dict[str, LedgerEntry],
) -> tuple[list[dict[str, str]], set[int]]:
    deletions = [(i, c) for i, c in enumerate(changes) if c.status == "D"]
    destinations = [(i, c) for i, c in enumerate(changes) if c.status in ("A", "M")]
    paired_dest_indices: set[int] = set()
    output: list[dict[str, str]] = []
    dest_content: dict[int, tuple[str, dict[str, str]]] = {}
    for i, change in destinations:
        sql, oid = _read_git_blob(repo, head_sha, change.path)
        _ledger, row = _match_destination(
            path=change.path, sql=sql, git_hash=oid, ledger_by_version=ledger_by_version,
        )
        dest_content[i] = (transport.direct_source_hash(sql), row)
        output.append(row)

    for del_i, deletion in deletions:
        _version, _name = _parse_filename(deletion.path)
        source_sql, source_oid = _read_git_blob(repo, base_sha, deletion.path)
        if _is_exact_ledger_source(deletion.path, source_sql, ledger_by_version):
            raise LaneFailure(f"DELETE_EXACT_LEDGER_ENTRY:{deletion.path}")
        source_hash = transport.direct_source_hash(source_sql)
        matches = [i for i, (digest, _row) in dest_content.items()
                   if i not in paired_dest_indices and digest == source_hash]
        if len(matches) != 1:
            raise LaneFailure(f"DELETE_WITHOUT_UNIQUE_IDENTICAL_DESTINATION:{deletion.path}")
        dest_i = matches[0]
        paired_dest_indices.add(dest_i)
        output.append(_entry_result(
            path=deletion.path, version=_version, name=_name, git_hash=source_oid, git_sql=source_sql,
            ledger=None, verdict="PASS_PAIRED_SOURCE_NOT_LEDGER",
        ))
    return output, paired_dest_indices


def _verify_changes(
    *, repo: Path, base_sha: str, head_sha: str, changes: list[Change],
    ledger_entries: list[LedgerEntry], max_batch: int = MAX_BATCH,
) -> list[dict[str, str]]:
    if not changes:
        raise LaneFailure("NO_SOURCE_CHANGES")
    if len(changes) > max_batch:
        raise LaneFailure(f"BATCH_EXCEEDS_MAX:{max_batch}")
    for change in changes:
        for path in (change.path, change.previous_path):
            if path is not None and not path.startswith(MIGRATIONS_DIR):
                raise LaneFailure(f"PATH_OUTSIDE_MIGRATIONS:{path}")
        if change.status not in {"A", "M", "D", "R"}:
            raise LaneFailure(f"CHANGE_STATUS_NOT_ALLOWED:{change.status}")
    ledger_by_version = _ledger_map(ledger_entries)
    _head_versions(repo, head_sha)

    rows, paired_dest_indices = _pair_deletions(
        changes, repo, base_sha, head_sha, ledger_by_version,
    )
    for i, change in enumerate(changes):
        if change.status == "D":
            continue
        if change.status == "R":
            assert change.previous_path is not None
            dest_sql, dest_oid = _read_git_blob(repo, head_sha, change.path)
            _ledger, dest_row = _match_destination(
                path=change.path, sql=dest_sql, git_hash=dest_oid,
                ledger_by_version=ledger_by_version,
            )
            source_sql, source_oid = _read_git_blob(repo, base_sha, change.previous_path)
            if _is_exact_ledger_source(change.previous_path, source_sql, ledger_by_version):
                raise LaneFailure(f"RENAME_ORIGIN_IS_EXACT_LEDGER_ENTRY:{change.previous_path}")
            if transport.direct_source_hash(source_sql) != transport.direct_source_hash(dest_sql):
                raise LaneFailure(f"RENAME_CONTENT_NOT_IDENTICAL:{change.previous_path}:{change.path}")
            _v, old_name = _parse_filename(change.previous_path)
            old_version, _ = _parse_filename(change.previous_path)
            rows.append(_entry_result(
                path=change.previous_path, version=old_version, name=old_name,
                git_hash=source_oid, git_sql=source_sql,
                ledger=None, verdict="PASS_PAIRED_SOURCE_NOT_LEDGER",
            ))
            rows.append(dest_row)
        elif change.status in ("A", "M"):
            if i in paired_dest_indices:
                continue
            sql, oid = _read_git_blob(repo, head_sha, change.path)
            _ledger, row = _match_destination(
                path=change.path, sql=sql, git_hash=oid, ledger_by_version=ledger_by_version,
            )
            # A/M rows were already materialized for pairing with D; avoid duplicates.
            if not any(r["git_hash"] == oid and r["version"] == row["version"] for r in rows):
                rows.append(row)
    return sorted(rows, key=lambda r: (r["version"], r["name"], r["verdict"], r["git_hash"]))


def _failure_file_rows(
    *, repo: Path, base_sha: str, head_sha: str, changes: list[Change],
    ledger_entries: list[LedgerEntry], reason: str,
) -> list[dict[str, str]]:
    """Retain per-file hashes even when a semantic check fails closed."""
    ledger_by_version = _ledger_map(ledger_entries)
    rows: list[dict[str, str]] = []
    for change in changes:
        sides = [(base_sha, change.previous_path, "origin")] if change.status == "D" else []
        if change.status == "R" and change.previous_path:
            sides.append((base_sha, change.previous_path, "origin"))
        if change.status != "D":
            sides.append((head_sha, change.path, "destination"))
        for commit_sha, path, _side in sides:
            if not path:
                continue
            try:
                sql, oid = _read_git_blob(repo, commit_sha, path)
            except LaneBlocked:
                continue
            try:
                version, name = _parse_filename(path)
            except LaneFailure:
                version, name = "NOT_OBSERVED", PurePosixPath(path).name
            ledger = ledger_by_version.get(version)
            rows.append({
                "path": path,
                "version": version,
                "name": name,
                "git_hash": oid,
                "ledger_hash": ledger.canonical_hash if ledger else "NOT_APPLICABLE",
                "canonical_git_hash": transport.direct_source_hash(sql),
                "verdict": "FAIL:" + reason,
            })
    return sorted(rows, key=lambda r: (r["version"], r["name"], r["path"]))


def _receipt_digest(receipt: dict[str, Any]) -> str:
    unsigned = {k: v for k, v in receipt.items() if k != "receipt_sha256"}
    canonical_json = json.dumps(unsigned, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()


def _write_receipt(path: str | None, receipt: dict[str, Any]) -> None:
    receipt["receipt_sha256"] = _receipt_digest(receipt)
    rendered = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
    if path:
        try:
            Path(path).write_text(rendered, encoding="utf-8")
        except OSError as exc:
            raise LaneBlocked("RECEIPT_WRITE_FAILED") from exc
    print(rendered, end="")


def _base_receipt(repo_label: str, pr: int | None, base_sha: str, head_sha: str) -> dict[str, Any]:
    return {
        "schema_version": RECEIPT_SCHEMA,
        "lane": "RECONCILE_SOURCE_ONLY",
        "repo": repo_label,
        "pr": pr,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "main_sha": base_sha,
        "files": [],
        "verdict": "BLOCKED",
    }


def verify(
    *, repo: Path, repo_label: str, pr: int | None, base_sha: str, head_sha: str,
    ledger_entries: list[LedgerEntry],
) -> tuple[int, dict[str, Any]]:
    receipt = _base_receipt(repo_label, pr, base_sha, head_sha)
    changes: list[Change] = []
    try:
        _validate_ledger_entries(ledger_entries, allow_empty=True)
        base_sha = _require_sha(base_sha, "base")
        head_sha = _require_sha(head_sha, "head")
        receipt.update({"base_sha": base_sha, "head_sha": head_sha, "main_sha": base_sha})
        ancestor = _git(repo, "merge-base", "--is-ancestor", base_sha, head_sha, check=False)
        if ancestor.returncode == 1:
            raise LaneFailure("HEAD_DOES_NOT_CONTAIN_MAIN")
        if ancestor.returncode != 0:
            raise LaneBlocked("GIT_ANCESTRY_READ_FAILED")
        changes = _parse_diff(repo, base_sha, head_sha)
        files = _verify_changes(
            repo=repo, base_sha=base_sha, head_sha=head_sha,
            changes=changes, ledger_entries=ledger_entries,
        )
        receipt["files"] = files
        receipt["verdict"] = "PASS"
        return PASS, receipt
    except LaneFailure as exc:
        receipt.update({"verdict": "FAIL", "reason": str(exc)})
        if changes:
            receipt["files"] = _failure_file_rows(
                repo=repo, base_sha=base_sha, head_sha=head_sha, changes=changes,
                ledger_entries=ledger_entries, reason=str(exc),
            )
        return FAIL, receipt
    except LaneBlocked as exc:
        receipt.update({"verdict": "BLOCKED", "reason": str(exc)})
        return BLOCKED, receipt


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--repo-label", help="canonical owner/repository string for the receipt")
    parser.add_argument("--base-sha", required=True, help="trusted current main SHA")
    parser.add_argument("--head-sha", required=True, help="exact PR head SHA")
    parser.add_argument("--pr-number", type=int, default=None)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--ledger-json")
    source.add_argument("--database-url-env")
    parser.add_argument("--out")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    repo = Path(args.repo).resolve()
    try:
        if args.ledger_json:
            ledger_entries = _load_ledger_json(Path(args.ledger_json))
        else:
            ledger_entries = _load_ledger_database(args.database_url_env)
        status, receipt = verify(
            repo=repo, repo_label=args.repo_label or args.repo, pr=args.pr_number,
            base_sha=args.base_sha, head_sha=args.head_sha,
            ledger_entries=ledger_entries,
        )
    except LaneFailure as exc:
        status, receipt = FAIL, _base_receipt(args.repo, args.pr_number, args.base_sha, args.head_sha)
        receipt.update({"verdict": "FAIL", "reason": str(exc)})
    except LaneBlocked as exc:
        status, receipt = BLOCKED, _base_receipt(args.repo, args.pr_number, args.base_sha, args.head_sha)
        receipt.update({"verdict": "BLOCKED", "reason": str(exc)})
    try:
        _write_receipt(args.out, receipt)
    except LaneBlocked as exc:
        print(str(exc), file=sys.stderr)
        return BLOCKED
    return status


if __name__ == "__main__":
    raise SystemExit(main())
