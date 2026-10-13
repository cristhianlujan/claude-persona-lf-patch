#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote

# Reuse the canonical MIGRATION_SOURCE_PARITY comparator; no duplicate parity logic.
PARITY_PARENT = Path(__file__).resolve().parents[1]
if str(PARITY_PARENT) not in sys.path:
    sys.path.insert(0, str(PARITY_PARENT))
from migration_source_parity.migration_source_parity_core import evaluate_exact_parity
import migration_transport_normalization as transport

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


def read_only_query(url: str, sql: str) -> list[str]:
    proc = subprocess.run(
        ["psql", url, "-X", "-At", "-v", "ON_ERROR_STOP=1", "-f", "-"],
        input="BEGIN TRANSACTION READ ONLY;\n" + sql + "\nCOMMIT;\n",
        capture_output=True, text=True, check=False, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError("RECONCILE_READ_ONLY_QUERY_FAILED")
    return [line for line in proc.stdout.strip().splitlines() if line and line not in ("BEGIN","COMMIT")]


def validate_router(url: str, execution_id: str, repository: str, base_sha: str, head_sha: str) -> None:
    if re.fullmatch(r"EXEC-[A-Z0-9][A-Z0-9_-]*", execution_id or "") is None:
        raise RuntimeError("RECONCILE_ROUTER_EXECUTION_REQUIRED")
    if re.fullmatch(r"[a-f0-9]{40}", head_sha) is None or re.fullmatch(r"[a-f0-9]{40}",base_sha) is None:
        raise RuntimeError("RECONCILE_HEAD_IDENTITY_INVALID")
    # Binding issued by the existing ACT-0001 execution insert trigger, not supplied by caller.
    sql = (
        "select jsonb_build_object('execution_id',e.execution_id,'status',e.status,"
        "'operation_code',e.operation_code,'target_type',e.target_type,'target_code',e.target_code,"
        "'target_repo',e.target_repo,'target_path',e.target_path,"
        "'source_base',e.manifest->>'reconcile_base_sha',"
        "'source_head',e.manifest->>'reconcile_head_sha',"
        "'authority',public.lf_router_downstream_authority_validate_v1(e.execution_id)) "
        "from public.lf_operation_execution e "
        f"where e.execution_id='{execution_id}';"
    )
    rows=read_only_query(url,sql)
    if len(rows)!=1:
        raise RuntimeError("RECONCILE_ROUTER_EXECUTION_READBACK_MISSING")
    row=json.loads(rows[0])
    authority=row.get("authority") or {}
    expected={
        "status":"IN_PROGRESS","operation_code":"ACTUALIZACION_DB_LF",
        "target_type":"MIGRATION","target_code":"RECONCILE_GIT_ONLY",
        "target_repo":repository,"target_path":"supabase/migrations",
        "source_base":base_sha,"source_head":head_sha
    }
    if any(row.get(key)!=value for key,value in expected.items()):
        raise RuntimeError("RECONCILE_ROUTER_EXECUTION_BINDING_MISMATCH")
    if (authority.get("applicable") is not True or authority.get("valid") is not True
            or authority.get("code")!="ROUTER_DOWNSTREAM_AUTHORITY_VALID"):
        raise RuntimeError("RECONCILE_ROUTER_AUTHORITY_NOT_VALID")


def ledger_row(url: str, version: str) -> tuple[str, str, int] | None:
    if re.fullmatch(r"[0-9]{14}",version) is None:
        raise ValueError("RECONCILE_VERSION_INVALID")
    sql = (
        "select name||'|'||cardinality(statements)::text||'|'||encode(convert_to(statements[1],'UTF8'),'hex') "
        "from supabase_migrations.schema_migrations "
        f"where version='{version}';"
    )
    rows=read_only_query(url,sql)
    if not rows: return None
    if len(rows)!=1: raise RuntimeError("RECONCILE_LEDGER_CARDINALITY_INVALID")
    name,count,hex_sql=rows[0].split("|",2)
    return name,bytes.fromhex(hex_sql).decode("utf-8"),int(count)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--pr-files", required=True)
    ap.add_argument("--base-sha", required=True)
    ap.add_argument("--head-sha", required=True)
    ap.add_argument("--db-url")
    ap.add_argument("--router-execution-id",required=True)
    ap.add_argument("--repository",required=True)
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()
    pages = json.loads(Path(args.pr_files).read_text(encoding="utf-8"))
    rows = [r for page in pages for r in page] if pages and isinstance(pages[0], list) else pages
    mig = [r for r in rows if str(r.get("filename") or "").startswith("supabase/migrations/")]
    if len(rows)!=len(mig):
        raise RuntimeError("RECONCILE_MIXED_SCOPE_FORBIDDEN")
    if not 1 <= len(mig) <= 10:
        raise RuntimeError(f"RECONCILE_MIGRATION_COUNT_INVALID:{len(mig)}")
    url = args.db_url or db_url()
    validate_router(url,args.router_execution_id,args.repository,args.base_sha,args.head_sha)
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
        ledger_name, ledger_sql, statement_count = row_db
        if ledger_name != nm.group("name"):
            raise RuntimeError(
                f"RECONCILE_TARGET_NAME_MISMATCH:{nm.group('version')}:{ledger_name}:{nm.group('name')}"
            )
        if statement_count != 1:
            raise RuntimeError(f"RECONCILE_LEDGER_CARDINALITY_INVALID:{new}:{statement_count}")
        source_sql = after.decode("utf-8")
        try:
            result = evaluate_exact_parity(
                {nm.group("version"): (nm.group("name"), transport.direct_source_hash(source_sql), source_sql)},
                {nm.group("version"): (ledger_name, transport.sha256(transport.canonical(ledger_sql)))},
                {nm.group("version"): statement_count},
            )
        except (ValueError, RuntimeError) as error:
            raise RuntimeError(f"RECONCILE_CANONICAL_PARITY_FAILED:{new}:{error}") from error
        if result.status != "PASS" or result.version_count != 1:
            raise RuntimeError(f"RECONCILE_CANONICAL_PARITY_NOT_PASS:{new}")
        out.append({"old": old, "new": new, "version": nm.group("version"), "name": nm.group("name")})
    print(json.dumps({"status": "PASS", "code": "RECONCILE_GIT_ONLY_PASS", "count": len(out), "renames": out}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
