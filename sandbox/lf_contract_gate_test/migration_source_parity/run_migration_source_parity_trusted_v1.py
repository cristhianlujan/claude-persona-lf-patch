#!/usr/bin/env python3
"""Trusted, read-only runner for MIGRATION_SOURCE_PARITY (PASE shadow).

Separates CODE from DATA:
- code: this file and every module it loads come from the trusted checkout
  (the directory of this file); nothing is imported or executed from the
  candidate checkout;
- data: the candidate checkout given by --data-root is read only through Git
  (rev-parse, diff, show, ls-tree) and by copying changed migration files.

Database: one call to public.lf_ci_migration_parity_snapshot_v1 with a
read-only role: lf_ci_readonly (secret LF_SUPABASE_DB_READONLY_PASSWORD, CI
environment lf-ci-readonly) or lf_reconcile_readonly (secret
LF_SUPABASE_RO_DATABASE_URL, Merge Train environment lf-merge-train). The
write credential LF_SUPABASE_DB_PASSWORD is never read and is removed from the
environment of every child process. The snapshot is rendered into the same CSV
files the focal runner writes today (psql --csv rules), so the parity adapter
is unchanged.

Run with `python3 -I`.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, unquote, urlsplit

HERE = Path(__file__).resolve().parent
CODE_ROOT = HERE.parents[2]
ENTRY_PATH = HERE / "run_migration_source_parity_pase_entry_v1.py"
SNAPSHOT_FUNCTION = "public.lf_ci_migration_parity_snapshot_v1"
SNAPSHOT_SCHEMA = "lf-ci-migration-parity-snapshot/v1"
CI_READONLY_ROLE = "lf_ci_readonly"
CI_READONLY_PASSWORD_ENV = "LF_SUPABASE_DB_READONLY_PASSWORD"
WRITE_PASSWORD_ENV = "LF_SUPABASE_DB_PASSWORD"
RO_URL_ENV = "LF_SUPABASE_RO_DATABASE_URL"
ALLOWED_RO_ROLES = ("lf_ci_readonly", "lf_reconcile_readonly")
PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"
VERSION_RE = re.compile(r"\d{14}")


class TrustedRunnerError(RuntimeError):
    pass


def fail(code: str, detail: str = "") -> None:
    raise TrustedRunnerError(f"{code}:{detail}" if detail else code)


def scrub_environment() -> None:
    """Drop the write credential and interpreter injection variables for this process and children."""
    os.environ.pop(WRITE_PASSWORD_ENV, None)
    os.environ.pop("PGPASSWORD", None)
    for name in list(os.environ):
        if name.startswith("PYTHON"):
            os.environ.pop(name, None)


def _base_env() -> dict[str, str]:
    env = os.environ.copy()
    for name in (WRITE_PASSWORD_ENV, CI_READONLY_PASSWORD_ENV, RO_URL_ENV, "PGPASSWORD"):
        env.pop(name, None)
    return env


def _env_from_ro_url(url: str) -> dict[str, str]:
    parts = urlsplit(url)
    if parts.scheme not in ("postgres", "postgresql"):
        fail("BLOCK_MIGRATION_PARITY_RO_URL_INVALID")
    user = unquote(parts.username or "")
    role = user.split(".", 1)[0]
    if role not in ALLOWED_RO_ROLES:
        fail("BLOCK_MIGRATION_PARITY_RO_URL_ROLE_NOT_READ_ONLY", role or "<empty>")
    password = unquote(parts.password or "")
    host = parts.hostname or ""
    if not password or not host:
        fail("BLOCK_MIGRATION_PARITY_RO_URL_INVALID")
    query = parse_qs(parts.query)
    env = _base_env()
    env.update(
        {
            "PGHOST": host,
            "PGPORT": str(parts.port or 5432),
            "PGUSER": user,
            "PGPASSWORD": password,
            "PGDATABASE": (parts.path or "/postgres").lstrip("/") or "postgres",
            "PGSSLMODE": (query.get("sslmode") or ["require"])[0],
        }
    )
    return env


def readonly_pg_env() -> dict[str, str]:
    """Read-only connection only: lf_ci_readonly password, else an allowlisted read-only URL."""
    password = os.environ.get(CI_READONLY_PASSWORD_ENV, "").strip()
    if password:
        project = os.environ.get("SUPABASE_PROJECT_ID", "").strip() or PROJECT_ID
        host = os.environ.get("SUPABASE_POOLER_HOST", "").strip() or POOLER_HOST
        env = _base_env()
        env.update(
            {
                "PGHOST": host,
                "PGPORT": "5432",
                "PGUSER": f"{CI_READONLY_ROLE}.{project}",
                "PGPASSWORD": password,
                "PGDATABASE": "postgres",
                "PGSSLMODE": "require",
            }
        )
        return env
    url = os.environ.get(RO_URL_ENV, "").strip()
    if url:
        return _env_from_ro_url(url)
    fail("BLOCK_MIGRATION_PARITY_RO_PASSWORD_MISSING")


def psql_csv_field(value: object) -> str:
    """One field exactly as `psql --csv -t` prints it (NULL and '' print empty)."""
    if value is None:
        return ""
    text = str(value)
    if any(ch in text for ch in (",", '"', "\n", "\r")):
        return '"' + text.replace('"', '""') + '"'
    return text


def render_rows(rows: list[list[object]]) -> str:
    return "".join(",".join(psql_csv_field(field) for field in row) + "\n" for row in rows)


def _versions_literal(versions: list[str]) -> str:
    if any(VERSION_RE.fullmatch(v) is None for v in versions):
        fail("FAIL_MIGRATION_PARITY_TRUSTED_VERSION_LITERAL")
    return "{" + ",".join(versions) + "}"


def snapshot_sql(*, context_versions: list[str], managed_versions: list[str], full) -> str:
    for value in (full.CUTOVER, full.CLASSIFICATION_BASELINE_END, full.LEGACY_START, full.LEGACY_END):
        if VERSION_RE.fullmatch(value) is None:
            fail("FAIL_MIGRATION_PARITY_TRUSTED_RANGE_LITERAL")
    return (
        f"select {SNAPSHOT_FUNCTION}("
        f"'{_versions_literal(context_versions)}'::text[],"
        f"'{_versions_literal(managed_versions)}'::text[],"
        f"'{full.CUTOVER}','{full.CLASSIFICATION_BASELINE_END}',"
        f"'{full.LEGACY_START}','{full.LEGACY_END}')::text"
    )


def parse_snapshot(psql_stdout: str) -> dict[str, object]:
    rows = [row for row in csv.reader(io.StringIO(psql_stdout)) if row]
    if len(rows) != 1 or len(rows[0]) != 1:
        fail("FAIL_MIGRATION_PARITY_SNAPSHOT_SHAPE")
    try:
        snapshot = json.loads(rows[0][0])
    except json.JSONDecodeError:
        fail("FAIL_MIGRATION_PARITY_SNAPSHOT_JSON")
    if not isinstance(snapshot, dict) or snapshot.get("schema_version") != SNAPSHOT_SCHEMA:
        fail("FAIL_MIGRATION_PARITY_SNAPSHOT_SCHEMA")
    for key in ("post_cutover", "statement_counts", "owners"):
        if not isinstance(snapshot.get(key), list):
            fail("FAIL_MIGRATION_PARITY_SNAPSHOT_FIELD", key)
    for key in ("grandfathered", "legacy"):
        value = snapshot.get(key)
        if not isinstance(value, list) or len(value) != 2:
            fail("FAIL_MIGRATION_PARITY_SNAPSHOT_FIELD", key)
    return snapshot


def write_focal_inputs(*, output_dir: Path, snapshot: dict[str, object], full) -> dict[str, Path]:
    """Write the CSV/JSON files the focal runner produces, from one snapshot."""
    output_dir.mkdir(parents=True, exist_ok=True)
    post_cutover = output_dir / "lf-post-cutover-migrations-compact.csv"
    grandfathered = output_dir / "lf-grandfathered-migrations.csv"
    legacy = output_dir / "lf-legacy-checkpoint.csv"
    statement_counts = output_dir / "lf-migration-statement-counts.csv"
    owner_csv = output_dir / "lf-migration-owner-currentness.csv"
    owner_json = output_dir / "lf-migration-external-owner-currentness.json"
    full._write_text(post_cutover, render_rows(snapshot["post_cutover"]), max_bytes=131072)
    full._write_text(statement_counts, render_rows(snapshot["statement_counts"]), max_bytes=65536)
    full._write_text(grandfathered, render_rows([snapshot["grandfathered"]]))
    full._write_text(legacy, render_rows([snapshot["legacy"]]))
    full._write_text(owner_csv, render_rows(snapshot["owners"]))
    owner_payload = full._build_external_owner_evidence(owner_csv)
    owner_json.write_text(json.dumps(owner_payload, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "post_cutover": post_cutover,
        "grandfathered": grandfathered,
        "legacy": legacy,
        "statement_counts": statement_counts,
        "owner_json": owner_json,
    }


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail("FAIL_MIGRATION_PARITY_TRUSTED_LOAD", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def validate_roots(data_root: Path, output_dir: Path) -> None:
    if not (data_root / ".git").exists():
        fail("FAIL_MIGRATION_PARITY_DATA_ROOT_NOT_GIT", str(data_root))
    if data_root == CODE_ROOT or CODE_ROOT.is_relative_to(data_root) or data_root.is_relative_to(CODE_ROOT):
        fail("FAIL_MIGRATION_PARITY_DATA_ROOT_OVERLAPS_CODE")
    if output_dir.is_relative_to(data_root):
        fail("FAIL_MIGRATION_PARITY_OUTPUT_INSIDE_CANDIDATE")


def bind_data_root(*, entry, data_root: Path, event_name: str, psql, pg_env: dict[str, str]) -> None:
    """Rebind the focal/flow modules so Git and files read DATA while code stays trusted."""
    focal = entry.FOCAL
    full = focal.FULL
    focal.ROOT = data_root
    focal.MIGRATIONS = data_root / "supabase/migrations"
    full.ROOT = data_root  # git cwd and the adapter subprocess cwd
    if not str(full.PARITY_ADAPTER).startswith(str(CODE_ROOT)):
        fail("FAIL_MIGRATION_PARITY_ADAPTER_NOT_TRUSTED")
    full._verify_exact_context = (
        lambda base_sha, head_sha, base_ref: entry._verify_exact_context_event_aware(
            base_sha, head_sha, base_ref, event_name
        )
    )

    def prepare(*, output_dir: Path, focal_versions: list[str], managed_versions: list[str]) -> dict[str, Path]:
        sql = snapshot_sql(
            context_versions=sorted(set(focal_versions)),
            managed_versions=managed_versions,
            full=full,
        )
        snapshot = parse_snapshot(psql(sql, env=pg_env))
        return write_focal_inputs(output_dir=output_dir, snapshot=snapshot, full=full)

    focal._prepare_focal_inputs = prepare


def prepare_full_current_inputs(*, focal, full, output_dir: Path, data_root: Path, pg_env: dict[str,str], psql) -> tuple[dict[str,Path],dict[str,int]]:
    """Entire post-baseline Git + ledger, using only the existing read-only
    capability snapshot in bounded <=150-version batches. Never mutate either source.
    Unlike CHANGESET_SCOPED, include ledger-only versions in the comparison.
    """
    import io
    index_query = (
        "select version,coalesce(name,'') from supabase_migrations.schema_migrations "
        f"where version > '{full.CLASSIFICATION_BASELINE_END}' order by version"
    )
    ledger_index = [row for row in csv.reader(io.StringIO(psql(index_query,env=pg_env))) if row]
    if any(len(row)!=2 or VERSION_RE.fullmatch(row[0]) is None for row in ledger_index):
        fail("FAIL_IG_M1013_FULL_LEDGER_INDEX_INVALID")
    remote_versions = [row[0] for row in ledger_index]
    if len(remote_versions)!=len(set(remote_versions)):
        fail("FAIL_IG_M1013_FULL_LEDGER_INDEX_DUPLICATE")

    adapter = full._load_parity_adapter()
    local_versions: list[str] = []
    managed_versions: set[str] = set()
    for file in sorted((data_root/"supabase/migrations").glob("*.sql")):
        match = adapter.FILENAME_RE.fullmatch(file.name)
        if match is None or match.group(1) <= full.CLASSIFICATION_BASELINE_END:
            continue
        version, name = match.groups()
        local_versions.append(version)
        if adapter.managed_source(file,version,name):
            managed_versions.add(version)
    if len(local_versions)!=len(set(local_versions)) or not local_versions or not remote_versions:
        fail("FAIL_IG_M1013_FULL_SOURCE_INDEX_INVALID")

    full_versions = sorted(set(local_versions)|set(remote_versions))
    merged={"schema_version":SNAPSHOT_SCHEMA,"post_cutover":[],"statement_counts":[],
            "owners":[],"grandfathered":None,"legacy":None}
    batch_count=0
    for start in range(0,len(full_versions),150):
        batch = full_versions[start:start+150]
        current_managed = sorted(set(batch)&managed_versions)
        snap = parse_snapshot(psql(snapshot_sql(context_versions=batch,
                                managed_versions=current_managed,full=full),env=pg_env))
        for key in ("grandfathered","legacy"):
            if merged[key] is None:
                merged[key]=snap[key]
            elif merged[key]!=snap[key]:
                fail("FAIL_IG_M1013_FULL_HISTORICAL_SNAPSHOT_DRIFT",key)
        for key in ("post_cutover","statement_counts","owners"):
            merged[key].extend(snap[key])
        batch_count+=1

    if len(merged["post_cutover"])!=len(remote_versions):
        fail("FAIL_IG_M1013_FULL_REMOTE_COVERAGE",
             f"expected={len(remote_versions)} actual={len(merged['post_cutover'])}")
    if len(merged["statement_counts"])!=len(set(managed_versions)&set(remote_versions)):
        fail("FAIL_IG_M1013_FULL_MANAGED_COUNT_COVERAGE")

    inputs=write_focal_inputs(output_dir=output_dir,snapshot=merged,full=full)
    evidence={"local_versions":len(local_versions),"ledger_versions":len(remote_versions),
              "union_versions":len(full_versions),"managed_source_versions":len(managed_versions),
              "snapshot_batches":batch_count}
    (output_dir/"full-current-input-scope.json").write_text(
        json.dumps({"schema_version":"ig-m1013-full-current-scope/v1",
                    "scope":"FULL_CURRENT_STATE","coverage":evidence,
                    "source":"CURRENT_MAIN","ledger":"LIVE_READ_ONLY"},sort_keys=True)+"\n",encoding="utf-8")
    return inputs,evidence


def run(argv: list[str] | None = None, *, psql=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--base-ref", default="main")
    parser.add_argument("--event-name", default="pull_request")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--control-maturity", default="CUTOVER")
    parser.add_argument("--evaluation-scope", default="CHANGESET_SCOPED")
    parser.add_argument("--historical-debt-disposition", default="RECONCILIATION_WORK_ITEM")
    parser.add_argument("--full-current", action="store_true", help="M10.13 official Train-only entire live parity")
    args = parser.parse_args(argv)

    scrub_environment()
    data_root = Path(args.data_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    validate_roots(data_root, output_dir)
    pg_env = readonly_pg_env()  # fail closed before any work when no read-only credential exists
    for name in (CI_READONLY_PASSWORD_ENV, RO_URL_ENV):
        os.environ.pop(name, None)  # children (adapter, git) never see a database credential
    os.environ["LF_MIGRATION_PARITY_DATA_ROOT"] = str(data_root)
    os.chdir(data_root)

    entry = _load(ENTRY_PATH, "lf_migration_source_parity_trusted_entry")
    focal = entry.FOCAL
    full = focal.FULL
    bind_data_root(entry=entry, data_root=data_root, event_name=args.event_name, psql=psql or full._psql, pg_env=pg_env)

    maturity = focal._require_exact(args.control_maturity, focal.EXPECTED_MATURITY, "CONTROL_MATURITY")
    disposition = focal._require_exact(
        args.historical_debt_disposition, focal.EXPECTED_HISTORICAL_DISPOSITION, "HISTORICAL_DEBT_DISPOSITION"
    )
    base_sha = full._require_sha(args.base_sha, "BASE")
    head_sha = full._require_sha(args.head_sha, "HEAD")
    base_ref = full._require_base_ref(args.base_ref)
    if args.event_name not in {"pull_request", "push", "workflow_dispatch"}:
        fail("FAIL_MIGRATION_PARITY_EVENT_NAME", args.event_name)

    full._verify_exact_context(base_sha, head_sha, base_ref)
    output_dir.mkdir(parents=True, exist_ok=True)
    # Same path as the focal runner, including PRs without migration changes
    # (bounded checkpoint/grandfathered/legacy attestation still runs).
    if args.full_current:
        if (args.evaluation_scope!="FULL_CURRENT_STATE" or args.event_name!="push"
            or base_ref!="main" or base_sha!=head_sha
            or pg_env.get("PGUSER","").split(".",1)[0]!="lf_reconcile_readonly"):
            fail("BLOCK_IG_M1013_FULL_CURRENT_SCOPE_OR_ROLE")
        inputs,coverage=prepare_full_current_inputs(
            focal=focal,full=full,output_dir=output_dir,data_root=data_root,
            pg_env=pg_env,psql=psql or full._psql
        )
        rc=full._run_parity(
            migrations=data_root/"supabase/migrations",inputs=inputs,
            output_dir=output_dir,event_name=args.event_name,base_ref=base_ref
        )
        full._verify_exact_context(base_sha,head_sha,base_ref)
    else:
        scope = focal._require_exact(args.evaluation_scope, focal.EXPECTED_SCOPE, "EVALUATION_SCOPE")
        changed_paths = focal._changed_migration_paths(base_sha, head_sha)
        scoped, focal_versions, managed_versions = focal._build_scoped_snapshot(
            output_dir=output_dir, changed_paths=changed_paths
        )
        focal._write_scope_manifest(
            output_dir=output_dir, base_sha=base_sha, head_sha=head_sha, changed_paths=changed_paths,
            focal_versions=focal_versions, maturity=maturity, evaluation_scope=scope,
            historical_disposition=disposition,
        )
        inputs = focal._prepare_focal_inputs(
            output_dir=output_dir, focal_versions=focal_versions, managed_versions=managed_versions
        )
        rc = full._run_parity(
            migrations=scoped, inputs=inputs, output_dir=output_dir,
            event_name=args.event_name, base_ref=base_ref,
        )
        focal._enrich_run_summary(
            output_dir=output_dir, maturity=maturity, evaluation_scope=scope,
            historical_disposition=disposition, changed_paths=changed_paths,
        )
    summary_path = output_dir / "run-summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    summary["runner"] = "TRUSTED_READ_ONLY_V1"
    if args.full_current:
        summary.update({"evaluation_scope":"FULL_CURRENT_STATE","current_main_sha":head_sha,
                        "coverage":coverage,"checkpoint":"IG_CURATOR_VALIDATOR_REFACTOR_V2:M10.13:GIT_RUNTIME_PARITY"})
    summary_path.write_text(json.dumps(summary, sort_keys=True) + "\n", encoding="utf-8")
    if rc == 0:
        print(f"PASS_MIGRATION_SOURCE_PARITY_TRUSTED_READ_ONLY head={head_sha} migrations={coverage['local_versions'] if args.full_current else len(focal_versions)}")
    return rc


def main() -> int:
    try:
        return run()
    except (TrustedRunnerError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
