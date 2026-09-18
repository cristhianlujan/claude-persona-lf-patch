#!/usr/bin/env python3
"""Prepare exact changed LF migration bytes for a rollback-only sandbox probe.

The control is fail-closed for deleted/renamed migrations and SQL that can
escape a surrounding PostgreSQL transaction. It never connects to a database;
the workflow executes the emitted SQL through the existing sandbox DB channel.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

SCHEMA_VERSION = "lf-db-candidate-rollback-probe/v1"
MIGRATION_PREFIX = "supabase/migrations/"

FORBIDDEN_TOP_LEVEL = (
    re.compile(r"^\s*(?:BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK)\b", re.I | re.M),
    re.compile(r"^\s*VACUUM\b", re.I | re.M),
    re.compile(r"^\s*ALTER\s+SYSTEM\b", re.I | re.M),
    re.compile(r"^\s*(?:CREATE|DROP)\s+DATABASE\b", re.I | re.M),
    re.compile(r"^\s*(?:CREATE\s+(?:UNIQUE\s+)?INDEX|DROP\s+INDEX|REINDEX\b[^;]*)\s+CONCURRENTLY\b", re.I | re.M),
    re.compile(r"^\s*REFRESH\s+MATERIALIZED\s+VIEW\s+CONCURRENTLY\b", re.I | re.M),
)


class ProbeError(ValueError):
    pass


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def changed_migrations(repo: Path, base: str, head: str) -> list[tuple[str,str]]:
    raw = subprocess.check_output(
        ["git","-C",str(repo),"diff","--name-status","--no-renames",base,head,"--","supabase/migrations"],
        text=True,
    )
    rows: list[tuple[str,str]] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise ProbeError(f"FAIL_DB_CANDIDATE_DIFF_SHAPE:{line}")
        status,path = parts
        if not path.startswith(MIGRATION_PREFIX) or not path.endswith(".sql"):
            continue
        if status not in {"A","M"}:
            raise ProbeError(f"FAIL_DB_CANDIDATE_NON_ADDITIVE_OR_MODIFIED:{status}:{path}")
        rows.append((status,path))
    if not rows:
        raise ProbeError("FAIL_DB_CANDIDATE_NO_CHANGED_MIGRATIONS")
    return sorted(rows,key=lambda x:x[1])


def strip_non_code(sql: str) -> str:
    # Preserve newlines so ^ anchors continue to represent top-level statement lines.
    out = list(sql)
    n = len(sql)
    i = 0
    while i < n:
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            if j < 0:
                j = n
            for k in range(i,j):
                out[k] = " "
            i = j
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i+2)
            if j < 0:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_BLOCK_COMMENT")
            for k in range(i,j+2):
                if out[k] != "\n":
                    out[k] = " "
            i = j+2
            continue
        if sql[i] == "'":
            j = i+1
            while j < n:
                if sql[j] == "'":
                    if j+1 < n and sql[j+1] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_STRING")
            for k in range(i,j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if sql[i] == "$":
            m = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i+len(tag))
                if j < 0:
                    raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_DOLLAR_QUOTE")
                end = j+len(tag)
                for k in range(i,end):
                    if out[k] != "\n":
                        out[k] = " "
                i = end
                continue
        i += 1
    return "".join(out)


def validate_transaction_safe(path: str, text: str) -> None:
    code = strip_non_code(text)
    for pattern in FORBIDDEN_TOP_LEVEL:
        hit = pattern.search(code)
        if hit:
            snippet = code[hit.start():hit.end()+80].splitlines()[0][:160]
            raise ProbeError(f"BLOCK_DB_CANDIDATE_NONTRANSACTIONAL:{path}:{snippet}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", default=".")
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--sql-out", required=True)
    p.add_argument("--manifest-out", required=True)
    args = p.parse_args()

    repo = Path(args.repo_root).resolve()
    rows = changed_migrations(repo,args.base,args.head)
    manifest_rows = []
    chunks = [
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SET LOCAL statement_timeout = '120s';",
        "SET LOCAL lock_timeout = '15s';",
    ]
    for status,path in rows:
        target = repo/path
        raw = target.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"FAIL_DB_CANDIDATE_NON_UTF8:{path}") from exc
        validate_transaction_safe(path,text)
        digest = sha(raw)
        manifest_rows.append({"status":status,"path":path,"sha256":digest,"bytes":len(raw)})
        chunks.extend([
            f"\\echo LF_DB_CANDIDATE_BEGIN {path} sha256={digest}",
            text,
            f"\\echo LF_DB_CANDIDATE_APPLIED {path} sha256={digest}",
        ])
    chunks.extend([
        "SELECT 'LF_DB_CANDIDATE_ALL_APPLIED_BEFORE_ROLLBACK' AS probe_result;",
        "ROLLBACK;",
        "SELECT 'LF_DB_CANDIDATE_ROLLBACK_COMPLETE' AS probe_result;",
    ])
    sql_out = Path(args.sql_out)
    sql_out.parent.mkdir(parents=True,exist_ok=True)
    sql_out.write_text("\n".join(chunks)+"\n",encoding="utf-8")
    manifest = {
        "schema_version":SCHEMA_VERSION,
        "base_sha":args.base,
        "head_sha":args.head,
        "migration_count":len(manifest_rows),
        "migrations":manifest_rows,
        "combined_sql_sha256":sha(sql_out.read_bytes()),
        "transaction_escape_scan":"PASS",
    }
    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True,exist_ok=True)
    manifest_out.write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps(manifest,sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProbeError as exc:
        print(str(exc))
        raise SystemExit(2)
