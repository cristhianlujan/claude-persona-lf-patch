#!/usr/bin/env python3
"""Deterministic runtime classifier for changed migration candidates.

Scope is intentionally narrow:
- live ledger version/name decides whether DDL may be replayed;
- MIGRATION_SOURCE_PARITY remains the independent authority for exact content.

No effect-guard receipt, source blob, or content hash is elevated into runtime
application state.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "lf-db-candidate-runtime-state/v3"
CLASSIFICATION_AUTHORITY = "LIVE_LEDGER_VERSION_NAME"
CONTENT_AUTHORITY = "MIGRATION_SOURCE_PARITY"
MODE_PENDING = "PENDING"
MODE_APPLIED = "ALL_APPLIED_IDENTITY_EXACT"

VERSION_RE = re.compile(r"^\d{14}$")
NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
BLOB_RE = re.compile(r"^[0-9a-f]{40}$")


class RuntimeClassificationError(ValueError):
    pass


def _manifest_rows(manifest: dict[str, Any]) -> list[dict[str, str]]:
    rows = manifest.get("migrations")
    if not isinstance(rows, list) or not rows:
        raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_STATE_EMPTY")
    declared = manifest.get("migration_count")
    if declared != len(rows):
        raise RuntimeClassificationError(
            f"BLOCK_DB_CANDIDATE_MANIFEST_COUNT_MISMATCH:declared={declared}:actual={len(rows)}"
        )

    result: list[dict[str, str]] = []
    versions: set[str] = set()
    for raw in rows:
        if not isinstance(raw, dict):
            raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_MANIFEST_ROW")
        version = str(raw.get("migration_version") or "")
        name = str(raw.get("migration_name") or "")
        blob = str(raw.get("source_git_blob_sha1") or "").lower()
        if VERSION_RE.fullmatch(version) is None:
            raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_VERSION_INVALID")
        if NAME_RE.fullmatch(name) is None:
            raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_NAME_INVALID")
        if BLOB_RE.fullmatch(blob) is None:
            raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_GIT_BLOB_INVALID")
        if version in versions:
            raise RuntimeClassificationError(
                f"BLOCK_DB_CANDIDATE_RUNTIME_DUPLICATE_VERSION:{version}"
            )
        versions.add(version)
        result.append(
            {
                "migration_version": version,
                "migration_name": name,
                "source_git_blob_sha1": blob,
            }
        )
    return result


def emit_query(manifest: dict[str, Any]) -> str:
    rows = _manifest_rows(manifest)
    values = ",".join(
        f"('{row['migration_version']}','{row['migration_name']}','{row['source_git_blob_sha1']}')"
        for row in rows
    )
    return f"""with expected(version,name,git_blob) as (
  values {values}
)
select
  e.version,
  e.name,
  e.git_blob,
  coalesce(m.name,'') as ledger_name
from expected e
left join supabase_migrations.schema_migrations m
  on m.version=e.version
order by e.version;
"""


def classify_rows(
    manifest: dict[str, Any],
    ledger_lines: list[str],
) -> dict[str, Any]:
    expected_rows = _manifest_rows(manifest)
    expected = {
        (row["migration_version"], row["migration_name"], row["source_git_blob_sha1"])
        for row in expected_rows
    }
    if len(expected) != len(expected_rows):
        raise RuntimeClassificationError("BLOCK_DB_CANDIDATE_RUNTIME_EXPECTED_DUPLICATE")

    evidence: list[dict[str, Any]] = []
    states: set[str] = set()
    seen: set[tuple[str, str, str]] = set()

    for line in ledger_lines:
        if not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 4:
            raise RuntimeClassificationError(
                "BLOCK_DB_CANDIDATE_RUNTIME_STATE_SHAPE:" + line.rstrip("\n")
            )
        version, name, blob, ledger_name = parts
        identity = (version, name, blob.lower())
        if identity not in expected:
            raise RuntimeClassificationError(
                f"BLOCK_DB_CANDIDATE_RUNTIME_IDENTITY_MISMATCH:{version}:{name}:{blob}"
            )
        if identity in seen:
            raise RuntimeClassificationError(
                f"BLOCK_DB_CANDIDATE_RUNTIME_DUPLICATE_LEDGER_ROW:{version}"
            )
        seen.add(identity)

        if not ledger_name:
            state = "UNAPPLIED"
        elif ledger_name == name:
            state = "APPLIED_IDENTITY_EXACT"
        else:
            raise RuntimeClassificationError(
                f"BLOCK_DB_CANDIDATE_APPLIED_NAME_MISMATCH:{version}:"
                f"expected={name}:ledger={ledger_name}"
            )

        states.add(state)
        evidence.append(
            {
                "migration_version": version,
                "migration_name": name,
                "source_git_blob_sha1": blob.lower(),
                "state": state,
                "ledger_name": ledger_name or None,
            }
        )

    if seen != expected:
        missing = sorted(expected - seen)
        extra = sorted(seen - expected)
        raise RuntimeClassificationError(
            f"BLOCK_DB_CANDIDATE_RUNTIME_STATE_COUNT_MISMATCH:"
            f"missing={missing}:extra={extra}"
        )

    if states == {"UNAPPLIED"}:
        mode = MODE_PENDING
    elif states == {"APPLIED_IDENTITY_EXACT"}:
        mode = MODE_APPLIED
    else:
        raise RuntimeClassificationError(
            "BLOCK_DB_CANDIDATE_MIXED_RUNTIME_STATE:"
            + json.dumps(
                {"states": sorted(states), "evidence": evidence},
                sort_keys=True,
                separators=(",", ":"),
            )
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "mode": mode,
        "classification_authority": CLASSIFICATION_AUTHORITY,
        "content_authority": CONTENT_AUTHORITY,
        "provenance": sorted(evidence, key=lambda row: row["migration_version"]),
    }


def _fixture() -> dict[str, Any]:
    return {
        "migration_count": 2,
        "migrations": [
            {
                "migration_version": "20260919010101",
                "migration_name": "lf_runtime_probe_a",
                "source_git_blob_sha1": "a" * 40,
            },
            {
                "migration_version": "20260919010102",
                "migration_name": "lf_runtime_probe_b",
                "source_git_blob_sha1": "b" * 40,
            },
        ],
    }


def self_test() -> None:
    manifest = _fixture()
    query = emit_query(manifest)
    assert "supabase_migrations.schema_migrations" in query
    assert "lf_operation_effect_guard" not in query

    pending = classify_rows(
        manifest,
        [
            f"20260919010101\tlf_runtime_probe_a\t{'a'*40}\t",
            f"20260919010102\tlf_runtime_probe_b\t{'b'*40}\t",
        ],
    )
    assert pending["mode"] == MODE_PENDING
    assert pending["content_authority"] == CONTENT_AUTHORITY

    applied = classify_rows(
        manifest,
        [
            f"20260919010101\tlf_runtime_probe_a\t{'a'*40}\tlf_runtime_probe_a",
            f"20260919010102\tlf_runtime_probe_b\t{'b'*40}\tlf_runtime_probe_b",
        ],
    )
    assert applied["mode"] == MODE_APPLIED

    negatives = [
        (
            [
                f"20260919010101\tlf_runtime_probe_a\t{'a'*40}\tlf_runtime_probe_a",
                f"20260919010102\tlf_runtime_probe_b\t{'b'*40}\t",
            ],
            "BLOCK_DB_CANDIDATE_MIXED_RUNTIME_STATE",
        ),
        (
            [
                f"20260919010101\tlf_runtime_probe_a\t{'a'*40}\twrong_name",
                f"20260919010102\tlf_runtime_probe_b\t{'b'*40}\tlf_runtime_probe_b",
            ],
            "BLOCK_DB_CANDIDATE_APPLIED_NAME_MISMATCH",
        ),
        (
            [f"20260919010101\tlf_runtime_probe_a\t{'a'*40}\t"],
            "BLOCK_DB_CANDIDATE_RUNTIME_STATE_COUNT_MISMATCH",
        ),
    ]
    for lines, prefix in negatives:
        try:
            classify_rows(manifest, lines)
        except RuntimeClassificationError as exc:
            assert str(exc).startswith(prefix), (prefix, str(exc))
        else:
            raise AssertionError(prefix)

    print("DB_CANDIDATE_RUNTIME_CLASSIFIER_SELFTEST_PASS cases=5")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    emit = sub.add_parser("emit-query")
    emit.add_argument("--manifest", required=True)
    emit.add_argument("--query-out", required=True)

    classify = sub.add_parser("classify")
    classify.add_argument("--manifest", required=True)
    classify.add_argument("--ledger-tsv", required=True)
    classify.add_argument("--state-out", required=True)
    classify.add_argument("--github-output")

    sub.add_parser("self-test")

    args = parser.parse_args()

    try:
        if args.command == "self-test":
            self_test()
            return 0

        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        if args.command == "emit-query":
            target = Path(args.query_out)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(emit_query(manifest), encoding="utf-8")
            return 0

        ledger_lines = Path(args.ledger_tsv).read_text(encoding="utf-8").splitlines()
        state = classify_rows(manifest, ledger_lines)
        target = Path(args.state_out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(state, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if args.github_output:
            with open(args.github_output, "a", encoding="utf-8") as handle:
                handle.write(f"mode={state['mode']}\n")
        print("DB_CANDIDATE_RUNTIME_STATE", json.dumps(state, sort_keys=True))
        return 0
    except (OSError, json.JSONDecodeError, RuntimeClassificationError) as exc:
        print(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
