#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
TRANSPORT_PATH = HERE / "lf_db_write_transport.py"
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
VERSION_TOKEN_RE = re.compile(r"(?<!\d)(20\d{12})(?!\d)")


@dataclass(frozen=True)
class ApplyReceipt:
    schema_version: str
    status: str
    code: str
    executor: str
    fallback_used: bool
    migration_version: str
    migration_name: str
    ledger_version: str
    ledger_name: str


def _load_transport():
    spec = importlib.util.spec_from_file_location("lf_db_write_transport_apply", TRANSPORT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("DB_WRITE_TRANSPORT_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


TRANSPORT = _load_transport()


def _run(argv: list[str], *, cwd: Path, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=300,
    )


def build_db_url() -> str:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if not password:
        raise RuntimeError("LF_SUPABASE_DB_PASSWORD_MISSING")
    if not project or not host:
        raise RuntimeError("SUPABASE_DB_CONTEXT_MISSING")
    return (
        f"postgresql://postgres.{project}:{quote(password, safe='')}@"
        f"{host}:5432/postgres?sslmode=require"
    )


def _psql(db_url: str, sql: str, *, cwd: Path) -> str:
    proc = _run(
        ["psql", db_url, "-X", "-v", "ON_ERROR_STOP=1", "-At", "-c", sql],
        cwd=cwd,
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else f"rc={proc.returncode}"
        raise RuntimeError(f"EXACT_APPLY_PSQL_FAILED:{detail}")
    return proc.stdout.strip()


def read_ledger(db_url: str, version: str, *, cwd: Path) -> tuple[str | None, str | None, str | None]:
    sql = (
        "select coalesce(version,''),coalesce(name,''),"
        "coalesce(to_jsonb(sm)->>'created_by','') "
        "from supabase_migrations.schema_migrations sm "
        f"where version='{version}' limit 1;"
    )
    raw = _psql(db_url, sql, cwd=cwd)
    if not raw:
        return None, None, None
    parts = raw.split("|", 2)
    if len(parts) != 3:
        raise RuntimeError("EXACT_APPLY_LEDGER_READBACK_SHAPE")
    return parts[0], parts[1], parts[2]


def read_ledger_max(db_url: str, *, cwd: Path) -> str:
    raw = _psql(
        db_url,
        "select coalesce(max(version),'00000000000000') from supabase_migrations.schema_migrations;",
        cwd=cwd,
    )
    if re.fullmatch(r"\d{14}", raw) is None:
        raise RuntimeError(f"EXACT_APPLY_LEDGER_MAX_INVALID:{raw!r}")
    return raw


def pending_versions_from_dry_run(text: str) -> list[str]:
    return sorted(set(VERSION_TOKEN_RE.findall(text)))


def _supabase_push_help(project_root: Path) -> str:
    proc = _run(["supabase", "db", "push", "--help"], cwd=project_root)
    if proc.returncode != 0:
        raise RuntimeError("EXACT_APPLY_SUPABASE_HELP_FAILED")
    return proc.stdout + proc.stderr


def _primary_cli(
    *,
    project_root: Path,
    db_url: str,
    version: str,
) -> tuple[bool, str]:
    dry = _run(["supabase", "db", "push", "--db-url", db_url, "--dry-run"], cwd=project_root)
    dry_text = dry.stdout + "\n" + dry.stderr
    if dry.returncode != 0:
        return False, f"DRY_RUN_FAILED:{dry_text.strip()}"
    pending = pending_versions_from_dry_run(dry_text)
    if pending != [version]:
        raise RuntimeError(f"EXACT_APPLY_PENDING_SET_MISMATCH:expected={[version]} observed={pending}")

    argv = ["supabase", "db", "push", "--db-url", db_url]
    help_text = _supabase_push_help(project_root)
    input_text = None
    if "--yes" in help_text:
        argv.append("--yes")
    else:
        input_text = "y\n"
    pushed = _run(argv, cwd=project_root, input_text=input_text)
    return pushed.returncode == 0, (pushed.stdout + "\n" + pushed.stderr).strip()


def _dollar_tag(source: str) -> str:
    for suffix in range(1000):
        tag = f"$lfmig{suffix}$"
        if tag not in source:
            return tag
    raise RuntimeError("EXACT_APPLY_DOLLAR_TAG_EXHAUSTED")


def build_fallback_sql(
    *,
    version: str,
    name: str,
    source_sql: str,
    source_blob: str,
) -> str:
    if SHA40_RE.fullmatch(source_blob) is None:
        raise ValueError("EXACT_APPLY_SOURCE_BLOB_INVALID")
    tag = _dollar_tag(source_sql)
    return f"""begin;
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $lfguard$
declare v_max text;
begin
  select max(version) into v_max from supabase_migrations.schema_migrations;
  if exists(select 1 from supabase_migrations.schema_migrations where version='{version}') then
    raise exception 'EXACT_APPLY_VERSION_EXISTS:{version}';
  end if;
  if v_max is not null and v_max >= '{version}' then
    raise exception 'EXACT_APPLY_VERSION_RACE:max=% target={version}',v_max;
  end if;
end;
$lfguard$;

{source_sql}

insert into supabase_migrations.schema_migrations
(version,statements,name,created_by,idempotency_key)
values
('{version}',array[{tag}{source_sql}{tag}]::text[],'{name}',
 'SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML','gitblob:{source_blob}');
commit;
"""


def _fallback_apply(
    *,
    project_root: Path,
    db_url: str,
    version: str,
    name: str,
    source_sql: str,
    source_blob: str,
) -> None:
    payload = build_fallback_sql(
        version=version,
        name=name,
        source_sql=source_sql,
        source_blob=source_blob,
    )
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", delete=False) as handle:
        handle.write(payload)
        tmp = Path(handle.name)
    try:
        proc = _run(["psql", db_url, "-X", "-v", "ON_ERROR_STOP=1", "-f", str(tmp)], cwd=project_root)
        if proc.returncode != 0:
            detail = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else f"rc={proc.returncode}"
            raise RuntimeError(f"EXACT_APPLY_FALLBACK_FAILED:{detail}")
    finally:
        tmp.unlink(missing_ok=True)


def apply_exact(
    *,
    project_root: Path,
    migration_path: Path,
    db_url: str,
    source_blob: str,
    allow_fallback: bool,
) -> ApplyReceipt:
    decision = TRANSPORT.select_transport("MIGRATION", migration_path.as_posix())
    if decision.executor != "SUPABASE_CLI_DB_PUSH_LINKED":
        raise RuntimeError("EXACT_APPLY_PRIMARY_EXECUTOR_UNEXPECTED")
    if decision.fallback_executor != "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML":
        raise RuntimeError("EXACT_APPLY_FALLBACK_EXECUTOR_UNEXPECTED")

    version = str(decision.migration_version)
    name = str(decision.migration_name)
    source_sql = migration_path.read_text(encoding="utf-8")

    existing_version, existing_name, existing_created_by = read_ledger(db_url, version, cwd=project_root)
    if existing_version is not None:
        if existing_name != name:
            raise RuntimeError(
                f"EXACT_APPLY_EXISTING_IDENTITY_MISMATCH:{existing_version}/{existing_name}"
            )
        return ApplyReceipt(
            "lf-migration-exact-apply/v1", "PASS", "ALREADY_APPLIED_EXACT",
            existing_created_by or "UNKNOWN", False, version, name,
            existing_version, existing_name,
        )

    floor_before = read_ledger_max(db_url, cwd=project_root)
    if version <= floor_before:
        raise RuntimeError(f"EXACT_APPLY_VERSION_NOT_MONOTONIC:version={version} floor={floor_before}")

    primary_ok, primary_detail = _primary_cli(
        project_root=project_root,
        db_url=db_url,
        version=version,
    )

    ledger_version, ledger_name, created_by = read_ledger(db_url, version, cwd=project_root)
    if primary_ok:
        if ledger_version != version or ledger_name != name:
            raise RuntimeError(
                f"EXACT_APPLY_PRIMARY_READBACK_MISMATCH:{ledger_version}/{ledger_name}"
            )
        return ApplyReceipt(
            "lf-migration-exact-apply/v1", "PASS", "PRIMARY_APPLIED_EXACT",
            "SUPABASE_CLI_DB_PUSH_LINKED", False, version, name,
            ledger_version, ledger_name,
        )

    # A failed CLI may have committed before returning non-zero. Never replay blindly.
    if ledger_version is not None:
        if ledger_version == version and ledger_name == name:
            return ApplyReceipt(
                "lf-migration-exact-apply/v1", "PASS", "PRIMARY_NONZERO_BUT_LEDGER_EXACT",
                "SUPABASE_CLI_DB_PUSH_LINKED", False, version, name,
                ledger_version, ledger_name,
            )
        raise RuntimeError(f"EXACT_APPLY_PRIMARY_PARTIAL_IDENTITY:{ledger_version}/{ledger_name}")

    floor_after = read_ledger_max(db_url, cwd=project_root)
    if floor_after != floor_before:
        raise RuntimeError(
            f"EXACT_APPLY_LEDGER_MOVED_AFTER_PRIMARY_FAILURE:before={floor_before} after={floor_after}"
        )
    if not allow_fallback:
        raise RuntimeError(f"EXACT_APPLY_PRIMARY_FAILED_NO_FALLBACK:{primary_detail}")

    _fallback_apply(
        project_root=project_root,
        db_url=db_url,
        version=version,
        name=name,
        source_sql=source_sql,
        source_blob=source_blob,
    )
    ledger_version, ledger_name, created_by = read_ledger(db_url, version, cwd=project_root)
    if ledger_version != version or ledger_name != name:
        raise RuntimeError(f"EXACT_APPLY_FALLBACK_READBACK_MISMATCH:{ledger_version}/{ledger_name}")
    return ApplyReceipt(
        "lf-migration-exact-apply/v1", "PASS", "FALLBACK_APPLIED_EXACT",
        "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML", True, version, name,
        ledger_version, ledger_name,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--migration-path", required=True)
    parser.add_argument("--db-url")
    parser.add_argument("--source-blob", required=True)
    parser.add_argument("--allow-fallback", action="store_true")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    migration_path = Path(args.migration_path).resolve()
    try:
        migration_path.relative_to(project_root)
    except ValueError as exc:
        raise RuntimeError("EXACT_APPLY_MIGRATION_OUTSIDE_PROJECT_ROOT") from exc
    db_url = args.db_url or build_db_url()

    receipt = apply_exact(
        project_root=project_root,
        migration_path=migration_path,
        db_url=db_url,
        source_blob=args.source_blob.lower(),
        allow_fallback=args.allow_fallback,
    )
    print(json.dumps(asdict(receipt), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
