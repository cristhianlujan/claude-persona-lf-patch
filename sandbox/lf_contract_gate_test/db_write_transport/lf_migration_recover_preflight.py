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

FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\.sql$")


def db_url() -> str:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if not (password and project and host):
        raise RuntimeError("RECOVER_DB_CONTEXT_MISSING")
    return f"postgresql://postgres.{project}:{quote(password, safe='')}@{host}:5432/postgres?sslmode=require"


def psql(url: str, sql: str) -> str:
    proc = subprocess.run(
        ["psql", url, "-X", "-At", "-v", "ON_ERROR_STOP=1", "-f", "-"],
        input=sql, text=True, capture_output=True, check=False, timeout=300,
    )
    if proc.returncode != 0:
        tail = " | ".join(proc.stderr.strip().splitlines()[-8:])
        raise RuntimeError(f"RECOVER_COMPATIBILITY_FAILED:{tail}")
    return proc.stdout.strip()


def strip_outer_transaction(sql: str) -> str:
    lines = sql.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    significant = [i for i, line in enumerate(lines) if line.strip() and not line.lstrip().startswith("--")]
    if len(significant) < 2:
        raise ValueError("RECOVER_SOURCE_TRANSACTION_SHAPE_INVALID")
    first, last = significant[0], significant[-1]
    if lines[first].strip().upper() not in {"BEGIN;", "BEGIN"}:
        raise ValueError("RECOVER_SOURCE_BEGIN_REQUIRED")
    if lines[last].strip().upper() not in {"COMMIT;", "COMMIT"}:
        raise ValueError("RECOVER_SOURCE_COMMIT_REQUIRED")
    lines[first] = ""
    lines[last] = ""
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--migration-path", required=True)
    parser.add_argument("--db-url")
    parser.add_argument("--readback",action="store_true")
    parser.add_argument("--train-state")
    args = parser.parse_args()
    path = Path(args.migration_path)
    match = FILENAME_RE.fullmatch(path.name)
    if match is None or not path.is_file():
        raise ValueError("RECOVER_MIGRATION_FILE_INVALID")
    version = match.group("version")
    name = match.group("name")
    url = args.db_url or db_url()

    if args.readback:
        data=json.loads(psql(url,(
            "select coalesce((select jsonb_build_object("
            "'version',version,'name',name,'statement_count',cardinality(statements),"
            "'source_sha256',encode(extensions.digest(convert_to(statements[1],'UTF8'),'sha256'),'hex'))"
            " from supabase_migrations.schema_migrations where version='"+version+"'),'{}'::jsonb);"
        )))
        expected_sha=hashlib.sha256(path.read_bytes()).hexdigest()
        if (data.get("version")!=version or data.get("name")!=name
                or data.get("statement_count")!=1 or data.get("source_sha256")!=expected_sha):
            raise RuntimeError("RECOVER_EXACT_LEDGER_CONTENT_MISMATCH")
        print(json.dumps({"status":"PASS","code":"RECOVER_EXACT_LEDGER_READBACK_PASS",
                          "migration_version":version,"migration_name":name,
                          "source_sha256":expected_sha},sort_keys=True))
        return 0

    if not args.train_state:
        raise RuntimeError("RECOVER_ROUTER_TRAIN_STATE_REQUIRED")
    state=json.loads(Path(args.train_state).read_text(encoding="utf-8"))
    execution=str((state.get("ids") or {}).get("execution_id") or "")
    if not re.fullmatch(r"EXEC-[A-Z0-9][A-Z0-9_-]*",execution):
        raise RuntimeError("RECOVER_ROUTER_EXECUTION_ID_INVALID")
    if (state.get("result")!="TRAIN_EXECUTION_READY_TO_APPLY"
            or (state.get("context") or {}).get("version")!=version
            or (state.get("context") or {}).get("name")!=name):
        raise RuntimeError("RECOVER_ROUTER_TRAIN_IDENTITY_MISMATCH")
    authority=json.loads(psql(url,
        "select public.lf_router_downstream_authority_validate_v1('"+execution+"');"))
    if (authority.get("applicable") is not True or authority.get("valid") is not True
            or authority.get("code")!="ROUTER_DOWNSTREAM_AUTHORITY_VALID"
            or authority.get("operation_code")!="ACTUALIZACION_DB_LF"):
        raise RuntimeError("RECOVER_ROUTER_AUTHORITY_NOT_VALID")

    before = psql(url, (
        "select jsonb_build_object("
        "'target_count',(select count(*) from supabase_migrations.schema_migrations where version='" + version + "'),"
        "'ledger_max',(select coalesce(max(version),'00000000000000') from supabase_migrations.schema_migrations));"
    ))
    state = json.loads(before)
    if int(state["target_count"]) != 0:
        raise RuntimeError(f"RECOVER_TARGET_ALREADY_IN_LEDGER:{version}")

    body = strip_outer_transaction(path.read_text(encoding="utf-8"))
    psql(url, "begin;\n" + body + "\nrollback;\n")

    after = json.loads(psql(url, (
        "select jsonb_build_object("
        "'target_count',(select count(*) from supabase_migrations.schema_migrations where version='" + version + "'),"
        "'ledger_max',(select coalesce(max(version),'00000000000000') from supabase_migrations.schema_migrations));"
    )))
    if int(after["target_count"]) != 0 or after["ledger_max"] != state["ledger_max"]:
        raise RuntimeError("RECOVER_PREFLIGHT_LEFT_LEDGER_RESIDUE")
    print(json.dumps({
        "status": "PASS",
        "code": "RECOVER_COMPATIBILITY_ROLLBACK_PASS",
        "migration_version": version,
        "migration_name": name,
        "ledger_max": state["ledger_max"],
        "residue": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
