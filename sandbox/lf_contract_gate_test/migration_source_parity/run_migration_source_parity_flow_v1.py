#!/usr/bin/env python3
"""Pass-carrier runner for the existing MIGRATION_SOURCE_PARITY capability.

This module prepares bounded Git/Supabase snapshots for the already-canonical
lf_migration_source_parity.py adapter, verifies exact base/head currentness,
and delegates the parity verdict to that adapter. It does not decide pass
applicability, mutate Git/Supabase, apply DDL, or duplicate the parity core.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
PARITY_ADAPTER = ROOT / "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
POSTGRES_IMAGE = "postgres:17.6"
CUTOVER = "20260808031006"
CLASSIFICATION_BASELINE_END = "20261005203801"
GRANDFATHERED_COUNT = "796"
GRANDFATHERED_SHA256 = "94b5e2bb0b33e6e08b1b72b9af48423c2f3e8333945797313f8816a7ee18de38"
LEGACY_START = "20260801063708"
LEGACY_END = "20260801170332"
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SAFE_BASE_REF_RE = re.compile(r"^[A-Za-z0-9._/-]+$")

GRANDFATHERED_EXCLUSIONS_SQL = r"""(
  coalesce(name,'') like 'pr93\_%' escape '\'
  or coalesce(name,'') like 'lf\_%' escape '\'
  or coalesce(name,'') like 'programacion\_story\_agent\_task\_%' escape '\'
  or coalesce(name,'') like 'programacion\_task\_sizing\_%' escape '\'
  or coalesce(name,'') like 'programacion\_task\_dependency\_%' escape '\'
  or coalesce(name,'') like 'programacion\_agent\_task\_%' escape '\'
  or coalesce(name,'') like 'programacion\_dependency\_context\_%' escape '\'
  or coalesce(name,'') like 'programacion\_propagate\_execution\_%' escape '\'
  or coalesce(name,'') like 'programacion\_deprecate\_declared\_independence\_%' escape '\'
  or coalesce(name,'') like 'programacion\_revoke\_security\_definer\_%' escape '\'
  or coalesce(name,'') like 'programacion\_worker\_spec\_%' escape '\'
  or coalesce(name,'') like 'programacion\_prog017\_%' escape '\'
)"""


def _load_parity_adapter():
    spec = importlib.util.spec_from_file_location("lf_migration_source_parity_clean_carrier", PARITY_ADAPTER)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_CARRIER_ADAPTER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _require_sha(value: str, label: str) -> str:
    value = value.strip().lower()
    if SHA40_RE.fullmatch(value) is None:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_{label}_SHA:{value!r}")
    return value


def _require_base_ref(value: str) -> str:
    value = value.strip()
    if not value or SAFE_BASE_REF_RE.fullmatch(value) is None or ".." in value.split("/"):
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_BASE_REF:{value!r}")
    return value


def _git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
        timeout=90,
    )


def _verify_exact_context(base_sha: str, head_sha: str, base_ref: str) -> None:
    _git("fetch", "--no-tags", "origin", base_sha, head_sha)
    actual_head = _git("rev-parse", "HEAD").stdout.strip().lower()
    if actual_head != head_sha:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_EXACT_HEAD expected={head_sha} actual={actual_head}"
        )
    _git(
        "fetch",
        "--no-tags",
        "origin",
        f"+refs/heads/{base_ref}:refs/remotes/origin/{base_ref}",
    )
    live_base = _git("rev-parse", f"refs/remotes/origin/{base_ref}").stdout.strip().lower()
    if live_base != base_sha:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_BASE_CURRENTNESS expected={base_sha} live={live_base}"
        )
    merge_base = _git("merge-base", base_sha, head_sha).stdout.strip().lower()
    if merge_base != base_sha:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_BASE_NOT_ANCESTOR base={base_sha} merge_base={merge_base}"
        )


def _pg_env() -> dict[str, str]:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip() or os.environ.get("PGPASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if not password:
        raise RuntimeError("FAIL_LF_MIGRATION_PARITY_DB_PASSWORD_MISSING")
    if not project or not host:
        raise RuntimeError("FAIL_LF_MIGRATION_PARITY_DB_CONTEXT_MISSING")
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": host,
            "PGPORT": "5432",
            "PGUSER": f"postgres.{project}",
            "PGPASSWORD": password,
            "PGDATABASE": "postgres",
            "PGSSLMODE": "require",
        }
    )
    return env


def _psql(sql: str, *, env: dict[str, str]) -> str:
    proc = subprocess.run(
        [
            "docker", "run", "--rm",
            "-e", "PGHOST", "-e", "PGPORT", "-e", "PGUSER",
            "-e", "PGPASSWORD", "-e", "PGDATABASE", "-e", "PGSSLMODE",
            POSTGRES_IMAGE,
            "psql", "-X", "-v", "ON_ERROR_STOP=1", "--csv", "-t", "-c", sql,
        ],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=180,
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else f"rc={proc.returncode}"
        raise RuntimeError(f"FAIL_LF_MIGRATION_PARITY_DB_QUERY:{detail}")
    return proc.stdout


def _managed_versions_literal(migrations: Path) -> str:
    module = _load_parity_adapter()
    versions: list[str] = []
    for path in sorted(migrations.glob("*.sql")):
        match = module.FILENAME_RE.fullmatch(path.name)
        if not match:
            continue
        version, name = match.groups()
        if version > CLASSIFICATION_BASELINE_END and module.managed_source(path, version, name):
            versions.append(version)
    if len(versions) != len(set(versions)):
        raise RuntimeError("FAIL_S28_MIGRATION_MANAGED_VERSION_SET")
    if any(not re.fullmatch(r"\d{14}", item) for item in versions):
        raise RuntimeError("FAIL_S28_MIGRATION_MANAGED_VERSION_LITERAL")
    return "{" + ",".join(versions) + "}"


def _write_text(path: Path, content: str, *, max_bytes: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = content.encode("utf-8")
    if max_bytes is not None and len(encoded) > max_bytes:
        raise RuntimeError(
            f"FAIL_S28_MIGRATION_LEDGER_PAYLOAD_BUDGET bytes={len(encoded)} max={max_bytes}"
        )
    path.write_bytes(encoded)


def _github_json(path: str) -> object:
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not repo or not token:
        raise RuntimeError("FAIL_LF_MIGRATION_EXTERNAL_OWNER_GITHUB_CONTEXT_MISSING")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "lf-migration-owner-currentness-v1",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(
            f"FAIL_LF_MIGRATION_EXTERNAL_OWNER_GITHUB_READ:{path}:{type(exc).__name__}"
        ) from exc


def _canonical_remote_sql_sha(remote_sql_hex: str) -> str | None:
    try:
        remote_sql = bytes.fromhex(remote_sql_hex).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None
    remote_sql = remote_sql.replace("\r\n", "\n").replace("\r", "\n")
    remote_lines = [
        line for line in remote_sql.split("\n")
        if not line.lstrip().startswith("--")
    ]
    return hashlib.sha256(
        "\n".join(remote_lines).rstrip("\n").encode("utf-8")
    ).hexdigest()


def _build_external_owner_evidence(owner_csv: Path) -> dict[str, object]:
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if not repo:
        raise RuntimeError("FAIL_LF_MIGRATION_EXTERNAL_OWNER_REPOSITORY_MISSING")
    owner_rows: list[dict[str, object]] = []
    seen: set[tuple[object, ...]] = set()

    with owner_csv.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if not row:
                continue
            if len(row) != 15:
                raise RuntimeError("FAIL_LF_MIGRATION_EXTERNAL_OWNER_DB_ROW")
            (
                execution_id, execution_status, operation_code, target_repo, target_path,
                version, migration_name, raw_pr_number, receipt_head, receipt_blob,
                write_readback, currentness_result, ddl_replayed, remote_sql_hex,
                raw_remote_statement_count,
            ) = row
            if target_repo != repo or not raw_pr_number.isdigit():
                continue
            if (
                write_readback != "PASS"
                or currentness_result != "OWNER_PR_EXACT_OPEN"
                or ddl_replayed != "false"
            ):
                continue
            if not raw_remote_statement_count.isdigit() or int(raw_remote_statement_count) < 1:
                continue
            remote_sha256 = _canonical_remote_sql_sha(remote_sql_hex)
            if remote_sha256 is None:
                continue

            pr_number = int(raw_pr_number)
            pr = _github_json(f"pulls/{pr_number}")
            if not isinstance(pr, dict) or pr.get("state") != "open":
                continue
            live_head = str((pr.get("head") or {}).get("sha") or "")
            if live_head != receipt_head:
                continue

            files: list[object] = []
            page = 1
            while True:
                chunk = _github_json(f"pulls/{pr_number}/files?per_page=100&page={page}")
                if not isinstance(chunk, list):
                    raise RuntimeError("FAIL_LF_MIGRATION_EXTERNAL_OWNER_GITHUB_FILES_SHAPE")
                files.extend(chunk)
                if len(chunk) < 100:
                    break
                page += 1
                if page > 20:
                    raise RuntimeError("FAIL_LF_MIGRATION_EXTERNAL_OWNER_GITHUB_FILES_PAGINATION")

            exact = [
                item for item in files
                if isinstance(item, dict)
                and item.get("filename") == target_path
                and item.get("sha") == receipt_blob
            ]
            if len(exact) != 1:
                continue

            key = (version, migration_name, target_path, pr_number, receipt_head, receipt_blob)
            if key in seen:
                continue
            seen.add(key)
            owner_rows.append(
                {
                    "version": version,
                    "name": migration_name,
                    "path": target_path,
                    "currentness_execution_id": execution_id,
                    "currentness_execution_status": execution_status,
                    "operation_code": operation_code,
                    "target_repo": target_repo,
                    "pr_number": pr_number,
                    "pr_state": "OPEN",
                    "pr_head_sha": receipt_head,
                    "source_blob": receipt_blob,
                    "write_readback": write_readback,
                    "currentness_result": currentness_result,
                    "ddl_replayed": False,
                    "remote_sha256": remote_sha256,
                    "remote_statement_count": int(raw_remote_statement_count),
                }
            )
    return {
        "schema_version": "lf-migration-external-owner-currentness/v1",
        "repository": repo,
        "complete": True,
        "owners": owner_rows,
    }


def _prepare_inputs(migrations: Path, output_dir: Path) -> dict[str, Path]:
    env = _pg_env()
    managed_versions = _managed_versions_literal(migrations)
    output_dir.mkdir(parents=True, exist_ok=True)

    post_cutover = output_dir / "lf-post-cutover-migrations-compact.csv"
    grandfathered = output_dir / "lf-grandfathered-migrations.csv"
    legacy = output_dir / "lf-legacy-checkpoint.csv"
    statement_counts = output_dir / "lf-migration-statement-counts.csv"
    owner_csv = output_dir / "lf-migration-owner-currentness.csv"
    owner_json = output_dir / "lf-migration-external-owner-currentness.json"

    post_sql = f"""select version,coalesce(name,''),case when version = any('{managed_versions}'::text[]) then 'sha256:' || (select encode(extensions.digest(convert_to(regexp_replace(coalesce(string_agg(line,E'\\n' order by ord),''),E'\\n+$',''),'UTF8'),'sha256'),'hex') from regexp_split_to_table(replace(replace(coalesce(array_to_string(sm.statements,E'\\n'),''),E'\\r\\n',E'\\n'),E'\\r',E'\\n'),E'\\n') with ordinality as x(line,ord) where line !~ '^[[:space:]]*--') else '' end from supabase_migrations.schema_migrations sm where version > '{CLASSIFICATION_BASELINE_END}' order by version"""
    _write_text(post_cutover, _psql(post_sql, env=env), max_bytes=524288)

    grandfather_sql = f"""with x as (select version,coalesce(name,'') as name,array_to_string(statements,E'\\n') as sql_text from supabase_migrations.schema_migrations where version > '{CUTOVER}' and version <= '{CLASSIFICATION_BASELINE_END}') select count(*)::text,encode(extensions.digest(convert_to(coalesce(string_agg(version||E'\\n'||name||E'\\n'||sql_text,E'\\n--MIGRATION--\\n' order by version),''),'UTF8'),'sha256'),'hex') from x"""
    _write_text(grandfathered, _psql(grandfather_sql, env=env))

    legacy_sql = f"""select count(*)::text,encode(extensions.digest(convert_to(string_agg(version||E'\\n'||coalesce(name,'')||E'\\n'||array_to_string(statements,E'\\n--STATEMENT--\\n'),E'\\n--MIGRATION--\\n' order by version),'UTF8'),'sha256'),'hex') from supabase_migrations.schema_migrations where version between '{LEGACY_START}' and '{LEGACY_END}'"""
    _write_text(legacy, _psql(legacy_sql, env=env))

    statement_sql = f"""select version,coalesce(cardinality(statements),0)::text from supabase_migrations.schema_migrations where version=any('{managed_versions}'::text[]) order by version"""
    _write_text(statement_counts, _psql(statement_sql, env=env))

    owner_sql = """select g.execution_id,e.status,e.operation_code,coalesce(g.receipt->>'repository',''),coalesce(g.receipt->>'target_path',''),coalesce(g.receipt->>'migration_version',''),coalesce(g.receipt->>'migration_name',''),coalesce(g.receipt->>'pr_number',''),coalesce(g.receipt->>'pr_head_sha',''),coalesce(g.receipt->>'source_blob',''),coalesce(g.receipt->>'write_readback',''),coalesce(g.receipt->>'currentness_result',''),coalesce(g.receipt->>'ddl_replayed',''),encode(convert_to(coalesce(array_to_string(m.statements,chr(10)),''),'UTF8'),'hex'),coalesce(cardinality(m.statements),0)::text from public.lf_operation_effect_guard g join public.lf_operation_execution e using(execution_id) join supabase_migrations.schema_migrations m on m.version=g.receipt->>'migration_version' and m.name=g.receipt->>'migration_name' where g.effect_scope like 'MIGRATION_OWNER_CURRENTNESS:%' and g.state='SUCCEEDED' and g.receipt->>'schema_version'='lf-migration-owner-currentness/v1' order by g.resolved_at desc nulls last,g.execution_id"""
    _write_text(owner_csv, _psql(owner_sql, env=env))
    owner_payload = _build_external_owner_evidence(owner_csv)
    owner_json.write_text(json.dumps(owner_payload, sort_keys=True) + "\n", encoding="utf-8")

    return {
        "post_cutover": post_cutover,
        "grandfathered": grandfathered,
        "legacy": legacy,
        "statement_counts": statement_counts,
        "owner_json": owner_json,
    }


def _run_parity(
    *,
    migrations: Path,
    inputs: dict[str, Path],
    output_dir: Path,
    event_name: str,
    base_ref: str,
) -> int:
    env = os.environ.copy()
    env["LF_MIGRATION_CUTOVER"] = CUTOVER
    env["LF_MIGRATION_CLASSIFICATION_BASELINE_END"] = CLASSIFICATION_BASELINE_END
    env["LF_MIGRATION_GRANDFATHERED_COUNT"] = GRANDFATHERED_COUNT
    env["LF_MIGRATION_GRANDFATHERED_SHA256"] = GRANDFATHERED_SHA256
    env["LF_MIGRATION_STATEMENT_COUNTS_CSV"] = str(inputs["statement_counts"])
    env["LF_MIGRATION_EXTERNAL_OWNER_EVIDENCE_JSON"] = str(inputs["owner_json"])
    env["GITHUB_EVENT_NAME"] = event_name
    env["GITHUB_BASE_REF"] = base_ref

    proc = subprocess.run(
        [
            sys.executable,
            str(PARITY_ADAPTER),
            str(migrations),
            str(inputs["post_cutover"]),
            str(inputs["grandfathered"]),
            str(inputs["legacy"]),
        ],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=240,
    )
    (output_dir / "parity-output.txt").write_text(proc.stdout, encoding="utf-8")
    if proc.stderr:
        (output_dir / "parity-stderr.txt").write_text(proc.stderr, encoding="utf-8")
    status = "PASS" if proc.returncode == 0 else "FAIL"
    (output_dir / "run-summary.json").write_text(
        json.dumps(
            {
                "schema_version": "lf-migration-source-parity-run/v1",
                "status": status,
                "returncode": proc.returncode,
                "delegated_adapter": str(PARITY_ADAPTER.relative_to(ROOT)),
                "functional_core_duplicated": False,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr, file=sys.stderr, end="")
        return proc.returncode
    print("PASS_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER")
    return 0


def self_test() -> int:
    checks = 0
    if _require_sha("a" * 40, "TEST") != "a" * 40:
        raise RuntimeError("SELFTEST_SHA")
    checks += 1
    if _require_base_ref("main") != "main":
        raise RuntimeError("SELFTEST_BASE_REF")
    checks += 1
    probe = "-- comment\r\nselect 1;\r\n"
    expected = hashlib.sha256(b"select 1;").hexdigest()
    if _canonical_remote_sql_sha(probe.encode().hex()) != expected:
        raise RuntimeError("SELFTEST_CANONICAL_SHA")
    checks += 1
    if POSTGRES_IMAGE != "postgres:17.6" or GRANDFATHERED_COUNT != "796":
        raise RuntimeError("SELFTEST_BASELINE_CONSTANTS")
    checks += 1
    print(f"PASS_MIGRATION_SOURCE_PARITY_CLEAN_CARRIER_SELFTEST checks={checks}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--base-sha")
    parser.add_argument("--head-sha")
    parser.add_argument("--base-ref", default="main")
    parser.add_argument("--event-name", default="pull_request")
    parser.add_argument("--output-dir", default=".lf_migration_source_parity")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    repo_root = Path(args.repo_root).resolve()
    if repo_root != ROOT:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_REPO_ROOT expected={ROOT} observed={repo_root}"
        )
    base_sha = _require_sha(args.base_sha or "", "BASE")
    head_sha = _require_sha(args.head_sha or "", "HEAD")
    base_ref = _require_base_ref(args.base_ref)
    if args.event_name not in {"pull_request", "push", "workflow_dispatch"}:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_EVENT_NAME:{args.event_name!r}")

    _verify_exact_context(base_sha, head_sha, base_ref)
    output_dir = (ROOT / args.output_dir).resolve()
    try:
        output_dir.relative_to(ROOT)
    except ValueError as exc:
        raise RuntimeError("FAIL_MIGRATION_PARITY_OUTPUT_OUTSIDE_REPO") from exc
    migrations = ROOT / "supabase/migrations"
    inputs = _prepare_inputs(migrations, output_dir)
    return _run_parity(
        migrations=migrations,
        inputs=inputs,
        output_dir=output_dir,
        event_name=args.event_name,
        base_ref=base_ref,
    )


if __name__ == "__main__":
    raise SystemExit(main())
