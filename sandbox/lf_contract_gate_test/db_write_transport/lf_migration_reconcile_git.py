#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote

FILE_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\.sql$")


def canonical(sql: str) -> bytes:
    sql = sql.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line for line in sql.split("\n") if not line.lstrip().startswith("--")).rstrip("\n").encode()


def git_show(root: Path, ref: str, path: str) -> bytes:
    p = subprocess.run(["git", "show", f"{ref}:{path}"], cwd=root, capture_output=True, check=False)
    if p.returncode != 0:
        raise RuntimeError(f"RECONCILE_GIT_SHOW_FAILED:{ref}:{path}")
    return p.stdout


def db_url() -> str:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if not (password and project and host):
        raise RuntimeError("RECONCILE_DB_CONTEXT_MISSING")
    return f"postgresql://postgres.{project}:{quote(password, safe='')}@{host}:5432/postgres?sslmode=require"


def ledger_row(url: str, version: str) -> tuple[str, str] | None:
    sql = (
        "select name,encode(convert_to(statements[1],'UTF8'),'hex') "
        "from supabase_migrations.schema_migrations "
        f"where version='{version}';"
    )
    p = subprocess.run(["psql", url, "-X", "-At", "-F", "|", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True, check=False, timeout=120)
    if p.returncode != 0:
        raise RuntimeError("RECONCILE_LEDGER_READ_FAILED")
    raw = p.stdout.strip()
    if not raw:
        return None
    name, hex_sql = raw.split("|", 1)
    return name, bytes.fromhex(hex_sql).decode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--pr-files", required=True)
    ap.add_argument("--base-sha", required=True)
    ap.add_argument("--head-sha", required=True)
    ap.add_argument("--db-url")
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()
    pages = json.loads(Path(args.pr_files).read_text(encoding="utf-8"))
    rows = [r for page in pages for r in page] if pages and isinstance(pages[0], list) else pages
    mig = [r for r in rows if str(r.get("filename") or "").startswith("supabase/migrations/")]
    if not 1 <= len(mig) <= 10:
        raise RuntimeError(f"RECONCILE_MIGRATION_COUNT_INVALID:{len(mig)}")
    url = args.db_url or db_url()
    out = []
    for row in mig:
        if row.get("status") != "renamed":
            raise RuntimeError(f"RECONCILE_NOT_RENAME_ONLY:{row.get('status')}:{row.get('filename')}")
        old = str(row.get("previous_filename") or "")
        new = str(row.get("filename") or "")
        old_name = Path(old).name
        new_name = Path(new).name
        om = FILE_RE.fullmatch(old_name)
        nm = FILE_RE.fullmatch(new_name)
        if om is None or nm is None:
            raise RuntimeError("RECONCILE_FILENAME_INVALID")
        if old_name == new_name:
            raise RuntimeError("RECONCILE_IDENTITY_UNCHANGED")
        before = git_show(root, args.base_sha, old)
        after = git_show(root, args.head_sha, new)
        if before != after:
            raise RuntimeError(f"RECONCILE_CONTENT_CHANGED:{old}->{new}")
        row_db = ledger_row(url, nm.group("version"))
        if row_db is None:
            raise RuntimeError(f"RECONCILE_TARGET_LEDGER_VERSION_MISSING:{nm.group('version')}")
        ledger_name, ledger_sql = row_db
        if ledger_name != nm.group("name"):
            raise RuntimeError(
                f"RECONCILE_TARGET_NAME_MISMATCH:{nm.group('version')}:{ledger_name}:{nm.group('name')}"
            )
        if hashlib.sha256(canonical(after.decode("utf-8"))).hexdigest() != hashlib.sha256(canonical(ledger_sql)).hexdigest():
            raise RuntimeError(f"RECONCILE_CONTENT_LEDGER_MISMATCH:{new}")
        out.append({"old": old, "new": new, "version": nm.group("version"), "name": nm.group("name")})
    print(json.dumps({"status": "PASS", "code": "RECONCILE_GIT_ONLY_PASS", "count": len(out), "renames": out}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
