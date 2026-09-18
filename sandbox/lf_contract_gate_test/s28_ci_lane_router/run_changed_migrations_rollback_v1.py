#!/usr/bin/env python3
"""Prepare changed LF migrations for a rollback-only sandbox probe.

The exact source artifact is always bound by SHA-256. For the repository's
canonical single outer transaction frame (BEGIN/COMMIT), CI removes only those
two framing statements so the unchanged interior candidate material can run
inside the probe's own BEGIN/ROLLBACK envelope. Any other transaction control
or non-transaction-safe statement fails closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "lf-db-candidate-rollback-probe/v2"
MIGRATION_PREFIX = "supabase/migrations/"

TX_STMT = re.compile(
    r"(?im)^[ \t]*(BEGIN(?:[ \t]+TRANSACTION)?|START[ \t]+TRANSACTION|COMMIT|ROLLBACK)[ \t]*;"
)
FORBIDDEN_TOP_LEVEL = (
    re.compile(r"^\s*VACUUM\b", re.I | re.M),
    re.compile(r"^\s*ALTER\s+SYSTEM\b", re.I | re.M),
    re.compile(r"^\s*(?:CREATE|DROP)\s+DATABASE\b", re.I | re.M),
    re.compile(
        r"^\s*(?:CREATE\s+(?:UNIQUE\s+)?INDEX|DROP\s+INDEX|REINDEX\b[^;]*)\s+CONCURRENTLY\b",
        re.I | re.M,
    ),
    re.compile(r"^\s*REFRESH\s+MATERIALIZED\s+VIEW\s+CONCURRENTLY\b", re.I | re.M),
)


class ProbeError(ValueError):
    pass


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def changed_migrations(repo: Path, base: str, head: str) -> list[tuple[str, str]]:
    raw = subprocess.check_output(
        [
            "git",
            "-C",
            str(repo),
            "diff",
            "--name-status",
            "--no-renames",
            base,
            head,
            "--",
            "supabase/migrations",
        ],
        text=True,
    )
    rows: list[tuple[str, str]] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise ProbeError(f"FAIL_DB_CANDIDATE_DIFF_SHAPE:{line}")
        status, path = parts
        if not path.startswith(MIGRATION_PREFIX) or not path.endswith(".sql"):
            continue
        if status not in {"A", "M"}:
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_NON_ADDITIVE_OR_MODIFIED:{status}:{path}"
            )
        rows.append((status, path))
    if not rows:
        raise ProbeError("FAIL_DB_CANDIDATE_NO_CHANGED_MIGRATIONS")
    return sorted(rows, key=lambda x: x[1])


def strip_non_code(sql: str) -> str:
    """Blank comments/string/dollar bodies while preserving offsets/newlines."""
    out = list(sql)
    n = len(sql)
    i = 0
    while i < n:
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            if j < 0:
                j = n
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            if j < 0:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_BLOCK_COMMENT")
            for k in range(i, j + 2):
                if out[k] != "\n":
                    out[k] = " "
            i = j + 2
            continue
        if sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_STRING")
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if sql[i] == "$":
            m = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i + len(tag))
                if j < 0:
                    raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_DOLLAR_QUOTE")
                end = j + len(tag)
                for k in range(i, end):
                    if out[k] != "\n":
                        out[k] = " "
                i = end
                continue
        i += 1
    return "".join(out)


def _tx_kind(match: re.Match[str]) -> str:
    return re.sub(r"\s+", " ", match.group(1).upper()).strip()


def _blank_span_preserve_newlines(text: str, start: int, end: int) -> str:
    chars = list(text)
    for i in range(start, end):
        if chars[i] != "\n":
            chars[i] = " "
    return "".join(chars)


def prepare_transaction_payload(path: str, text: str) -> tuple[str, dict[str, Any]]:
    """Return transaction-safe probe payload plus explicit frame provenance."""
    code = strip_non_code(text)
    tx = list(TX_STMT.finditer(code))

    if not tx:
        payload = text
        frame: dict[str, Any] = {
            "mode": "NONE",
            "source_transaction_statements": 0,
            "interior_material_preserved": True,
        }
    else:
        kinds = [_tx_kind(m) for m in tx]
        outer_begin = kinds[0] in {"BEGIN", "BEGIN TRANSACTION", "START TRANSACTION"}
        outer_commit = kinds[-1] == "COMMIT"
        only_outer_pair = len(tx) == 2 and outer_begin and outer_commit
        prefix_empty = code[: tx[0].start()].strip() == ""
        suffix_empty = code[tx[-1].end() :].strip() == ""

        if not (only_outer_pair and prefix_empty and suffix_empty):
            raise ProbeError(
                f"BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL:{path}:"
                f"kinds={','.join(kinds)}"
            )

        payload = _blank_span_preserve_newlines(text, tx[0].start(), tx[0].end())
        payload = _blank_span_preserve_newlines(
            payload, tx[-1].start(), tx[-1].end()
        )
        frame = {
            "mode": "SINGLE_OUTER_BEGIN_COMMIT_NORMALIZED",
            "source_transaction_statements": 2,
            "source_open_kind": kinds[0],
            "source_close_kind": kinds[-1],
            "open_span": [tx[0].start(), tx[0].end()],
            "close_span": [tx[-1].start(), tx[-1].end()],
            "interior_material_preserved": True,
        }

    payload_code = strip_non_code(payload)
    residual_tx = list(TX_STMT.finditer(payload_code))
    if residual_tx:
        kinds = ",".join(_tx_kind(m) for m in residual_tx)
        raise ProbeError(
            f"BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL_REMAINS:{path}:{kinds}"
        )

    for pattern in FORBIDDEN_TOP_LEVEL:
        hit = pattern.search(payload_code)
        if hit:
            snippet = payload_code[hit.start() : hit.end() + 80].splitlines()[0][:160]
            raise ProbeError(
                f"BLOCK_DB_CANDIDATE_NONTRANSACTIONAL:{path}:{snippet}"
            )

    frame["source_sha256"] = sha(text.encode("utf-8"))
    frame["execution_payload_sha256"] = sha(payload.encode("utf-8"))
    frame["source_bytes"] = len(text.encode("utf-8"))
    frame["execution_payload_bytes"] = len(payload.encode("utf-8"))
    return payload, frame


def validate_transaction_safe(path: str, text: str) -> None:
    prepare_transaction_payload(path, text)


def _failure_manifest(args: argparse.Namespace, exc: ProbeError) -> None:
    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    raw = str(exc)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "status": "BLOCKED",
        "base_sha": args.base,
        "head_sha": args.head,
        "blocking_code": raw.split(":", 1)[0],
        "error": raw,
        "transaction_escape_scan": "BLOCKED",
    }
    manifest_out.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _build(args: argparse.Namespace) -> dict[str, Any]:
    repo = Path(args.repo_root).resolve()
    rows = changed_migrations(repo, args.base, args.head)
    manifest_rows = []
    chunks = [
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SET LOCAL statement_timeout = '120s';",
        "SET LOCAL lock_timeout = '15s';",
    ]

    for status, path in rows:
        target = repo / path
        raw = target.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"FAIL_DB_CANDIDATE_NON_UTF8:{path}") from exc

        payload, frame = prepare_transaction_payload(path, text)
        source_digest = sha(raw)
        payload_digest = sha(payload.encode("utf-8"))
        if frame["source_sha256"] != source_digest:
            raise ProbeError(f"FAIL_DB_CANDIDATE_SOURCE_DIGEST_INTERNAL:{path}")
        if frame["execution_payload_sha256"] != payload_digest:
            raise ProbeError(f"FAIL_DB_CANDIDATE_PAYLOAD_DIGEST_INTERNAL:{path}")

        manifest_rows.append(
            {
                "status": status,
                "path": path,
                "source_sha256": source_digest,
                "source_bytes": len(raw),
                "execution_payload_sha256": payload_digest,
                "transaction_frame": frame,
            }
        )
        chunks.extend(
            [
                (
                    f"\\echo LF_DB_CANDIDATE_BEGIN {path} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest} "
                    f"frame={frame['mode']}"
                ),
                payload,
                (
                    f"\\echo LF_DB_CANDIDATE_APPLIED {path} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest}"
                ),
            ]
        )

    probe_rows = []
    for probe_rel in args.probe_sql:
        probe_path = repo / probe_rel
        if not probe_path.is_file():
            raise ProbeError(f"FAIL_DB_CANDIDATE_PROBE_MISSING:{probe_rel}")
        raw_probe = probe_path.read_bytes()
        try:
            probe_text = raw_probe.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"FAIL_DB_CANDIDATE_PROBE_NON_UTF8:{probe_rel}") from exc

        probe_payload, probe_frame = prepare_transaction_payload(
            probe_rel, probe_text
        )
        source_digest = sha(raw_probe)
        payload_digest = sha(probe_payload.encode("utf-8"))
        probe_rows.append(
            {
                "path": probe_rel,
                "source_sha256": source_digest,
                "source_bytes": len(raw_probe),
                "execution_payload_sha256": payload_digest,
                "transaction_frame": probe_frame,
            }
        )
        chunks.extend(
            [
                (
                    f"\\echo LF_DB_CANDIDATE_PROBE_BEGIN {probe_rel} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest}"
                ),
                probe_payload,
                (
                    f"\\echo LF_DB_CANDIDATE_PROBE_PASS {probe_rel} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest}"
                ),
            ]
        )

    chunks.extend(
        [
            "SELECT 'LF_DB_CANDIDATE_ALL_APPLIED_BEFORE_ROLLBACK' AS probe_result;",
            "ROLLBACK;",
            "SELECT 'LF_DB_CANDIDATE_ROLLBACK_COMPLETE' AS probe_result;",
        ]
    )
    sql_out = Path(args.sql_out)
    sql_out.parent.mkdir(parents=True, exist_ok=True)
    sql_out.write_text("\n".join(chunks) + "\n", encoding="utf-8")

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "status": "READY",
        "base_sha": args.base,
        "head_sha": args.head,
        "migration_count": len(manifest_rows),
        "migrations": manifest_rows,
        "combined_sql_sha256": sha(sql_out.read_bytes()),
        "transaction_escape_scan": "PASS",
        "post_apply_probes": probe_rows,
        "source_material_binding": "EXACT_SOURCE_SHA_WITH_EXPLICIT_OUTER_FRAME_NORMALIZATION",
    }
    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", default=".")
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--sql-out", required=True)
    p.add_argument("--manifest-out", required=True)
    p.add_argument("--probe-sql", action="append", default=[])
    args = p.parse_args()

    try:
        manifest = _build(args)
    except ProbeError as exc:
        _failure_manifest(args, exc)
        print(str(exc))
        return 2

    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
