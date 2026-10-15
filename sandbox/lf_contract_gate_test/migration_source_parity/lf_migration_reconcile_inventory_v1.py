#!/usr/bin/env python3
"""Build a deterministic Git/ledger migration reconciliation inventory.

This is an offline source-only tool. It reads a checkout and a JSON export of
supabase_migrations.schema_migrations; it never connects to Supabase or writes
SQL. Only differences at or after the parity classifier cutover are classified.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import sys
from collections import Counter
from dataclasses import dataclass
from typing import Any

HERE = pathlib.Path(__file__).resolve().parent
CONTRACT_ROOT = HERE.parent
if str(CONTRACT_ROOT) not in sys.path:
    sys.path.insert(0, str(CONTRACT_ROOT))
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from migration_transport_normalization import (  # noqa: E402
    canonical,
    cli_statement_storage_hash,
)
from run_migration_source_parity_flow_v1 import (  # noqa: E402
    CUTOVER,
    LEGACY_END,
    LEGACY_START,
)
from lf_migration_source_parity_ci_context import MARKER_RE  # noqa: E402

FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
GITHUB_BLOB_POINTER_RE = re.compile(r"^github://[^#]+#blob=([0-9a-f]{40})$")
VERSION_SUFFIX_RE = re.compile(r"(?:_v\d+)+(?=_|$)", re.IGNORECASE)
THEME_QUALIFIER_SUFFIX_RE = re.compile(r"(?:_(?:train))+$", re.IGNORECASE)
THEME_ALIASES = {
    # The two M100 names use different descriptive wording but share the
    # explicitly reviewed family/theme anchor.
    "ig_m100_sandbox_technical_vs_operational_authority":
        "ig_m100_sandbox_admission_coherent",
}

CSV_FIELDS = (
    "era", "category", "git_version", "ledger_version", "name",
    "git_path", "ledger_name", "git_canonical_sha256",
    "ledger_canonical_sha256", "replacement_version", "replacement_name",
    "reason",
)


class InventoryError(ValueError):
    pass


@dataclass(frozen=True)
class GitMigration:
    version: str
    name: str
    path: str
    sql: str
    digest: str
    cli_digest: str
    blob_sha1: str


@dataclass(frozen=True)
class LedgerMigration:
    version: str
    name: str
    statements: tuple[str, ...]
    digest: str
    source_blob_sha1: str | None


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _git_blob_sha1(raw: bytes) -> str:
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


def _same_source(git_row: GitMigration, ledger_row: LedgerMigration) -> bool:
    return (
        git_row.digest == ledger_row.digest
        or git_row.cli_digest == ledger_row.digest
        or (
            ledger_row.source_blob_sha1 is not None
            and git_row.blob_sha1 == ledger_row.source_blob_sha1
        )
    )


def _theme(name: str) -> str:
    value = name.lower()
    value = re.sub(r"^(?:lf_)+", "", value)
    value = VERSION_SUFFIX_RE.sub("", value)
    value = THEME_QUALIFIER_SUFFIX_RE.sub("", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return THEME_ALIASES.get(value, value)


def _read_git(root: pathlib.Path) -> list[GitMigration]:
    directory = root / "supabase" / "migrations"
    if not directory.is_dir():
        raise InventoryError(f"MIGRATION_DIRECTORY_MISSING:{directory}")
    rows: list[GitMigration] = []
    for path in sorted(directory.glob("*.sql"), key=lambda item: item.name):
        match = FILENAME_RE.fullmatch(path.name)
        if not match:
            if re.match(r"^\d{14}_", path.name):
                raise InventoryError(f"MIGRATION_FILENAME_INVALID:{path.name}")
            # Historical unversioned files are grandfathered by the existing
            # baseline/classifier and cannot belong to POST_CUTOVER.
            continue
        version, name = match.groups()
        raw = path.read_bytes()
        try:
            sql = raw.decode("utf-8")
            cli_digest = cli_statement_storage_hash(sql)
        except (UnicodeDecodeError, ValueError) as exc:
            raise InventoryError(f"MIGRATION_SOURCE_NORMALIZATION_INVALID:{path.name}") from exc
        rows.append(GitMigration(
            version,
            name,
            path.relative_to(root).as_posix(),
            sql,
            _sha(canonical(sql)),
            cli_digest,
            _git_blob_sha1(raw),
        ))
    return rows


def _read_ledger(path: pathlib.Path) -> list[LedgerMigration]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InventoryError(f"LEDGER_EXPORT_INVALID:{type(exc).__name__}") from exc
    source: Any = payload.get("migrations") if isinstance(payload, dict) else payload
    if not isinstance(source, list):
        raise InventoryError("LEDGER_EXPORT_SHAPE_INVALID:expected list or migrations array")
    rows: list[LedgerMigration] = []
    seen: set[str] = set()
    for item in source:
        if not isinstance(item, dict):
            raise InventoryError("LEDGER_ROW_INVALID:expected object")
        version, name, statements = item.get("version"), item.get("name"), item.get("statements")
        if not isinstance(version, str) or not re.fullmatch(r"\d{14}", version):
            raise InventoryError("LEDGER_VERSION_INVALID")
        if not isinstance(name, str) or not name:
            raise InventoryError(f"LEDGER_NAME_INVALID:{version}")
        if version in seen:
            raise InventoryError(f"LEDGER_VERSION_DUPLICATE:{version}")
        if not isinstance(statements, list) or not statements or not all(isinstance(s, str) for s in statements):
            raise InventoryError(f"LEDGER_STATEMENTS_INVALID:{version}")
        seen.add(version)
        pointer_sha = None
        if len(statements) == 1:
            pointer_match = GITHUB_BLOB_POINTER_RE.fullmatch(statements[0].strip())
            if pointer_match:
                pointer_sha = pointer_match.group(1)
            elif statements[0].strip().startswith("github://"):
                raise InventoryError(f"LEDGER_GITHUB_BLOB_POINTER_INVALID:{version}")
        elif any(statement.strip().startswith("github://") for statement in statements):
            raise InventoryError(f"LEDGER_GITHUB_BLOB_POINTER_INVALID:{version}")
        sql = "\n".join(statements) if pointer_sha is None else ""
        digest = _sha(canonical(sql)) if pointer_sha is None else ""
        rows.append(LedgerMigration(version, name, tuple(statements), digest, pointer_sha))
    return sorted(rows, key=lambda row: (row.version, row.name))


def _checkpoint_status(root: pathlib.Path, ledger: list[LedgerMigration]) -> dict[str, Any]:
    markers: list[tuple[pathlib.Path, re.Match[str]]] = []
    for path in sorted((root / "supabase" / "migrations").glob("*.sql")):
        lines = path.read_text(encoding="utf-8").splitlines()
        match = MARKER_RE.fullmatch(lines[0]) if lines else None
        if match:
            markers.append((path, match))
    if len(markers) != 1:
        return {"status": "UNVERIFIED", "reason": "CHECKPOINT_MARKER_COUNT", "count": len(markers)}
    marker_path, match = markers[0]
    cutover, start, end, expected_count, expected_sha = match.groups()
    checkpoint_rows = [r for r in ledger if start <= r.version <= end]
    serialized = "\n--MIGRATION--\n".join(
        "\n".join((row.version, row.name, "\n--STATEMENT--\n".join(row.statements)))
        for row in checkpoint_rows
    )
    observed_sha = _sha(serialized.encode("utf-8"))
    ok = (cutover == CUTOVER and str(len(checkpoint_rows)) == expected_count
          and observed_sha == expected_sha)
    return {
        "status": "PASS" if ok else "FAIL",
        "path": marker_path.relative_to(root).as_posix(),
        "cutover": cutover,
        "legacy_start": start,
        "legacy_end": end,
        "expected_count": int(expected_count),
        "observed_count": len(checkpoint_rows),
        "expected_sha256": expected_sha,
        "observed_sha256": observed_sha,
    }


def build_inventory(root: pathlib.Path, ledger_json: pathlib.Path) -> tuple[list[dict[str, str]], dict[str, Any]]:
    git_all = _read_git(root)
    unversioned_legacy = sum(1 for path in (root / "supabase" / "migrations").glob("*.sql")
                             if FILENAME_RE.fullmatch(path.name) is None
                             and re.match(r"^\d{14}_", path.name) is None)
    ledger_all = _read_ledger(ledger_json)
    git_legacy = [row for row in git_all if row.version < CUTOVER]
    ledger_legacy = [row for row in ledger_all if row.version < CUTOVER]
    git = [row for row in git_all if row.version >= CUTOVER]
    ledger = [row for row in ledger_all if row.version >= CUTOVER]
    checkpoint = _checkpoint_status(root, ledger_all)

    git_by_identity = {(row.version, row.name): row for row in git}
    ledger_by_identity = {(row.version, row.name): row for row in ledger}
    exact_git: set[tuple[str, str]] = set()
    exact_ledger: set[tuple[str, str]] = set()
    result: list[dict[str, str]] = []

    def emit(category: str, g: GitMigration | None, l: LedgerMigration | None,
             reason: str, replacement: LedgerMigration | None = None) -> None:
        result.append({
            "era": "POST_CUTOVER",
            "category": category,
            "git_version": g.version if g else "",
            "ledger_version": l.version if l else "",
            "name": g.name if g else (l.name if l else ""),
            "git_path": g.path if g else "",
            "ledger_name": l.name if l else "",
            "git_canonical_sha256": g.digest if g else "",
            "ledger_canonical_sha256": l.digest if l else "",
            "replacement_version": replacement.version if replacement else "",
            "replacement_name": replacement.name if replacement else "",
            "reason": reason,
        })

    # Exact identities are either source matches (direct, CLI, or blob) or content drift (D).
    for identity in sorted(set(git_by_identity) & set(ledger_by_identity)):
        g, l = git_by_identity[identity], ledger_by_identity[identity]
        exact_git.add(identity); exact_ledger.add(identity)
        if not _same_source(g, l):
            emit("D_UNKNOWN", g, l, "SAME_VERSION_NAME_CONTENT_MISMATCH")

    remaining_git = [g for g in git if (g.version, g.name) not in exact_git]
    remaining_ledger = [l for l in ledger if (l.version, l.name) not in exact_ledger]
    git_matches = {
        (g.version, g.name): [l for l in remaining_ledger if _same_source(g, l)]
        for g in remaining_git
    }
    ledger_matches = {
        (l.version, l.name): [g for g in remaining_git if _same_source(g, l)]
        for l in remaining_ledger
    }

    paired_git: set[tuple[str, str]] = set()
    paired_ledger: set[tuple[str, str]] = set()
    ambiguous_git: set[tuple[str, str]] = set()
    ambiguous_ledger: set[tuple[str, str]] = set()
    for g in remaining_git:
        g_key = (g.version, g.name)
        matches = git_matches[g_key]
        if len(matches) == 1 and len(ledger_matches[(matches[0].version, matches[0].name)]) == 1:
            l = matches[0]
            l_key = (l.version, l.name)
            if g_key not in paired_git and l_key not in paired_ledger:
                paired_git.add(g_key); paired_ledger.add(l_key)
                emit("A_RENAME", g, l, "UNIQUE_SOURCE_CONTENT_MATCH")
    for g in remaining_git:
        g_key = (g.version, g.name)
        if g_key in paired_git:
            continue
        if git_matches[g_key]:
            ambiguous_git.add(g_key)
            emit("D_UNKNOWN", g, None, "AMBIGUOUS_SOURCE_CONTENT_MATCH")
    for l in remaining_ledger:
        l_key = (l.version, l.name)
        if l_key in paired_ledger:
            continue
        if ledger_matches[l_key]:
            ambiguous_ledger.add(l_key)
            emit("D_UNKNOWN", None, l, "AMBIGUOUS_SOURCE_CONTENT_MATCH")

    unmatched_git = [g for g in remaining_git
                     if (g.version, g.name) not in paired_git | ambiguous_git]
    unmatched_ledger = [l for l in remaining_ledger
                        if (l.version, l.name) not in paired_ledger | ambiguous_ledger]
    ledger_by_theme: dict[str, list[LedgerMigration]] = {}
    # A replacement is an applied ledger row even when its own Git source is
    # already perfectly reconciled, so search the full POST_CUTOVER ledger.
    for row in ledger:
        ledger_by_theme.setdefault(_theme(row.name), []).append(row)
    for g in unmatched_git:
        matches = [l for l in ledger_by_theme.get(_theme(g.name), [])
                   if l.version > g.version
                   ]
        if len(matches) == 1:
            replacement = matches[0]
            emit("C_RETIRE", g, None, "UNAPPLIED_GIT_SOURCE_SUPERSEDED_BY_UNIQUE_APPLIED_THEME", replacement)
        else:
            emit("D_UNKNOWN", g, None,
                 "NO_UNIQUE_APPLIED_SAME_THEME_REPLACEMENT" if not matches else "AMBIGUOUS_SAME_THEME_REPLACEMENT")
    for l in unmatched_ledger:
        emit("B_SOURCE_FROM_LEDGER", None, l, "LEDGER_SOURCE_WITHOUT_GIT_CONTENT_PAIR")

    result.sort(key=lambda row: (
        row["category"], row["git_version"] or row["ledger_version"],
        row["name"], row["git_path"],
    ))
    counts = Counter(row["category"] for row in result)
    summary = {
        "schema_version": "lf-migration-reconcile-inventory/v1",
        "cutover": CUTOVER,
        "legacy": {
            "git_files": len(git_legacy) + unversioned_legacy,
            "git_unversioned_grandfathered": unversioned_legacy,
            "ledger_rows": len(ledger_legacy),
            "reconciled": False,
            "parity_acceptance": "PASS" if checkpoint["status"] == "PASS" else "UNVERIFIED",
            "checkpoint": checkpoint,
        },
        "post_cutover": {
            "git_files": len(git),
            "ledger_rows": len(ledger),
            "exact_identity_matches": sum(1 for identity in set(git_by_identity) & set(ledger_by_identity)
                                           if _same_source(git_by_identity[identity], ledger_by_identity[identity])),
            "differences": len(result),
            "categories": {key: counts.get(key, 0) for key in (
                "A_RENAME", "B_SOURCE_FROM_LEDGER", "C_RETIRE", "D_UNKNOWN")},
        },
    }
    if checkpoint["status"] != "PASS":
        raise InventoryError("LEGACY_CHECKPOINT_NOT_ACCEPTED:" + checkpoint["status"])
    return result, summary


def write_inventory(rows: list[dict[str, str]], summary: dict[str, Any],
                    csv_path: pathlib.Path, summary_path: pathlib.Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=pathlib.Path, default=HERE.parents[2])
    parser.add_argument("--ledger-json", type=pathlib.Path, required=True)
    parser.add_argument("--csv-out", type=pathlib.Path, required=True)
    parser.add_argument("--summary-out", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        rows, summary = build_inventory(args.repo_root.resolve(), args.ledger_json.resolve())
        write_inventory(rows, summary, args.csv_out.resolve(), args.summary_out.resolve())
    except (InventoryError, OSError, UnicodeDecodeError) as exc:
        print(f"FAIL_LF_MIGRATION_RECONCILE_INVENTORY:{exc}", file=sys.stderr)
        return 2
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
