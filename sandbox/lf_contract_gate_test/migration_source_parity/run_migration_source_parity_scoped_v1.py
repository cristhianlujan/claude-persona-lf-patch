#!/usr/bin/env python3
"""Context-aware carrier for MIGRATION_SOURCE_PARITY.

Phase-04 CUTOVER policy: validate the current changeset and materially bound
migration authority without promoting unrelated historical taxonomy debt into
the current PASE verdict. Full/historical reconciliation remains available via
the existing canonical runner and is never inferred implicitly.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
BASE_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py"
FILENAME_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
CHECKPOINT_PREFIX = "-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 "

CONTROL_MATURITIES = {
    "BUILD",
    "QUALIFICATION",
    "CUTOVER",
    "ACTIVE",
    "HISTORICAL_RECONCILIATION",
}
EVALUATION_SCOPES = {
    "CHANGESET_SCOPED",
    "AFFECTED_DEPENDENCIES",
    "FULL_CURRENT_STATE",
    "HISTORICAL_RECONCILIATION",
}
HISTORICAL_DEBT_DISPOSITIONS = {
    "BLOCK_CURRENT_CHANGE",
    "NON_BLOCKING_FINDING",
    "RECONCILIATION_WORK_ITEM",
    "NOT_APPLICABLE",
}


def _load_base_runner():
    spec = importlib.util.spec_from_file_location("lf_migration_source_parity_base_runner", BASE_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_SCOPED_BASE_RUNNER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


_base = _load_base_runner()


def _require_choice(value: str, allowed: set[str], label: str) -> str:
    normalized = value.strip().upper()
    if normalized not in allowed:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_{label}:{value!r}")
    return normalized


def _migration_path(path: str) -> tuple[str, str, str] | None:
    normalized = path.replace("\\", "/")
    prefix = "supabase/migrations/"
    if not normalized.startswith(prefix):
        return None
    filename = normalized[len(prefix):]
    if not filename.endswith(".sql"):
        return None
    match = FILENAME_RE.fullmatch(filename)
    if match is None:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHANGESET_FILENAME:{normalized}")
    version, name = match.groups()
    return version, name, normalized


def _changeset_migrations(base_sha: str, head_sha: str) -> list[tuple[str, str, str]]:
    proc = _base._git(
        "diff",
        "--name-status",
        "--find-renames",
        base_sha,
        head_sha,
        "--",
        "supabase/migrations",
    )
    changed: list[tuple[str, str, str]] = []
    seen_versions: set[str] = set()
    for raw in proc.stdout.splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        status = parts[0]
        paths = parts[1:]
        material = [item for item in (_migration_path(path) for path in paths) if item is not None]
        if not material:
            continue
        if status.startswith(("D", "R", "C")):
            raise RuntimeError(
                "FAIL_MIGRATION_PARITY_CHANGESET_SOURCE_REMOVAL_OR_RENAME:"
                + raw
            )
        if len(material) != 1:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHANGESET_PATH_SHAPE:{raw}")
        version, name, path = material[0]
        if version <= _base.CUTOVER:
            raise RuntimeError(
                f"FAIL_MIGRATION_PARITY_CHANGESET_PRE_CUTOVER_MUTATION:{path}"
            )
        if version in seen_versions:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHANGESET_DUPLICATE_VERSION:{version}")
        seen_versions.add(version)
        changed.append((version, name, path))
    return sorted(changed)


def _checkpoint_path(migrations: Path) -> Path:
    matches: list[Path] = []
    for path in sorted(migrations.glob("*.sql")):
        try:
            first = path.read_text(encoding="utf-8").splitlines()[0] if path.stat().st_size else ""
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHECKPOINT_READ:{path.name}") from exc
        if first.startswith(CHECKPOINT_PREFIX):
            matches.append(path)
    if len(matches) != 1:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHECKPOINT_COUNT:{len(matches)}")
    return matches[0]


def _build_scoped_tree(
    *,
    full_migrations: Path,
    output_dir: Path,
    changed: list[tuple[str, str, str]],
) -> Path:
    scoped = output_dir / "changeset_migrations"
    if scoped.exists():
        shutil.rmtree(scoped)
    scoped.mkdir(parents=True, exist_ok=True)
    checkpoint = _checkpoint_path(full_migrations)
    shutil.copyfile(checkpoint, scoped / checkpoint.name)
    for _version, _name, repo_path in changed:
        source = ROOT / repo_path
        if not source.is_file():
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_CHANGESET_SOURCE_MISSING:{repo_path}")
        shutil.copyfile(source, scoped / source.name)
    return scoped


def _pg_array(versions: list[str]) -> str:
    if any(re.fullmatch(r"\d{14}", value) is None for value in versions):
        raise RuntimeError("FAIL_MIGRATION_PARITY_SCOPE_VERSION_LITERAL")
    return "{" + ",".join(versions) + "}"


def _managed_versions(scoped: Path, changed: list[tuple[str, str, str]]) -> list[str]:
    adapter = _base._load_parity_adapter()
    result: list[str] = []
    for version, name, _repo_path in changed:
        path = scoped / f"{version}_{name}.sql"
        if adapter.managed_source(path, version, name):
            result.append(version)
    return result


def _prepare_scoped_inputs(
    *,
    scoped: Path,
    output_dir: Path,
    changed: list[tuple[str, str, str]],
) -> dict[str, Path]:
    env = _base._pg_env()
    output_dir.mkdir(parents=True, exist_ok=True)
    post_cutover = output_dir / "lf-post-cutover-migrations-compact.csv"
    grandfathered = output_dir / "lf-grandfathered-migrations.csv"
    legacy = output_dir / "lf-legacy-checkpoint.csv"
    statement_counts = output_dir / "lf-migration-statement-counts.csv"
    owner_csv = output_dir / "lf-migration-owner-currentness.csv"
    owner_json = output_dir / "lf-migration-external-owner-currentness.json"

    versions = [row[0] for row in changed]
    managed = _managed_versions(scoped, changed)

    if versions:
        version_literal = _pg_array(versions)
        managed_literal = _pg_array(managed) if managed else "{}"
        post_sql = f"""select version,coalesce(name,''),case when version = any('{managed_literal}'::text[]) then 'sha256:' || (select encode(extensions.digest(convert_to(regexp_replace(coalesce(string_agg(line,E'\\n' order by ord),''),E'\\n+$',''),'UTF8'),'sha256'),'hex') from regexp_split_to_table(replace(replace(coalesce(array_to_string(sm.statements,E'\\n'),''),E'\\r\\n',E'\\n'),E'\\r',E'\\n'),E'\\n') with ordinality as x(line,ord) where line !~ '^[[:space:]]*--') else '' end from supabase_migrations.schema_migrations sm where version=any('{version_literal}'::text[]) order by version"""
        _base._write_text(post_cutover, _base._psql(post_sql, env=env), max_bytes=131072)
    else:
        _base._write_text(post_cutover, "")

    grandfather_sql = f"""with x as (select version,coalesce(name,'') as name,array_to_string(statements,E'\\n') as sql_text from supabase_migrations.schema_migrations where version > '{_base.CUTOVER}' and version <= '{_base.CLASSIFICATION_BASELINE_END}' and not {_base.GRANDFATHERED_EXCLUSIONS_SQL}) select count(*)::text,encode(extensions.digest(convert_to(coalesce(string_agg(version||E'\\n'||name||E'\\n'||sql_text,E'\\n--MIGRATION--\\n' order by version),''),'UTF8'),'sha256'),'hex') from x"""
    _base._write_text(grandfathered, _base._psql(grandfather_sql, env=env))

    legacy_sql = f"""select count(*)::text,encode(extensions.digest(convert_to(string_agg(version||E'\\n'||coalesce(name,'')||E'\\n'||array_to_string(statements,E'\\n--STATEMENT--\\n'),E'\\n--MIGRATION--\\n' order by version),'UTF8'),'sha256'),'hex') from supabase_migrations.schema_migrations where version between '{_base.LEGACY_START}' and '{_base.LEGACY_END}'"""
    _base._write_text(legacy, _base._psql(legacy_sql, env=env))

    if managed:
        managed_literal = _pg_array(managed)
        statement_sql = f"""select version,coalesce(cardinality(statements),0)::text from supabase_migrations.schema_migrations where version=any('{managed_literal}'::text[]) order by version"""
        _base._write_text(statement_counts, _base._psql(statement_sql, env=env))
    else:
        _base._write_text(statement_counts, "")

    if versions:
        version_literal = _pg_array(versions)
        owner_sql = f"""select g.execution_id,e.status,e.operation_code,coalesce(g.receipt->>'repository',''),coalesce(g.receipt->>'target_path',''),coalesce(g.receipt->>'migration_version',''),coalesce(g.receipt->>'migration_name',''),coalesce(g.receipt->>'pr_number',''),coalesce(g.receipt->>'pr_head_sha',''),coalesce(g.receipt->>'source_blob',''),coalesce(g.receipt->>'write_readback',''),coalesce(g.receipt->>'currentness_result',''),coalesce(g.receipt->>'ddl_replayed',''),encode(convert_to(coalesce(array_to_string(m.statements,chr(10)),''),'UTF8'),'hex'),coalesce(cardinality(m.statements),0)::text from public.lf_operation_effect_guard g join public.lf_operation_execution e using(execution_id) join supabase_migrations.schema_migrations m on m.version=g.receipt->>'migration_version' and m.name=g.receipt->>'migration_name' where g.effect_scope like 'MIGRATION_OWNER_CURRENTNESS:%' and g.state='SUCCEEDED' and g.receipt->>'schema_version'='lf-migration-owner-currentness/v1' and g.receipt->>'migration_version'=any('{version_literal}'::text[]) order by g.resolved_at desc nulls last,g.execution_id"""
        _base._write_text(owner_csv, _base._psql(owner_sql, env=env))
        owner_payload = _base._build_external_owner_evidence(owner_csv)
    else:
        _base._write_text(owner_csv, "")
        owner_payload = {
            "schema_version": "lf-migration-external-owner-currentness/v1",
            "repository": os.environ.get("GITHUB_REPOSITORY", "").strip(),
            "complete": True,
            "owners": [],
        }
    owner_json.write_text(json.dumps(owner_payload, sort_keys=True) + "\n", encoding="utf-8")

    return {
        "post_cutover": post_cutover,
        "grandfathered": grandfathered,
        "legacy": legacy,
        "statement_counts": statement_counts,
        "owner_json": owner_json,
    }


def _enrich_summary(
    *,
    output_dir: Path,
    maturity: str,
    scope: str,
    disposition: str,
    base_sha: str,
    head_sha: str,
    changed: list[tuple[str, str, str]],
) -> None:
    summary_path = output_dir / "run-summary.json"
    payload: dict[str, object] = {}
    if summary_path.is_file():
        try:
            loaded = json.loads(summary_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                payload.update(loaded)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            pass
    payload.update(
        {
            "policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
            "control_maturity": maturity,
            "evaluation_scope": scope,
            "historical_debt_disposition": disposition,
            "base_sha": base_sha,
            "head_sha": head_sha,
            "changeset_migration_count": len(changed),
            "changeset_migrations": [row[2] for row in changed],
            "unbounded_historical_scan": False,
        }
    )
    summary_path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")


def self_test() -> int:
    checks = 0
    if _require_choice("cutover", CONTROL_MATURITIES, "CONTROL_MATURITY") != "CUTOVER":
        raise RuntimeError("SELFTEST_MATURITY")
    checks += 1
    if _require_choice("changeset_scoped", EVALUATION_SCOPES, "EVALUATION_SCOPE") != "CHANGESET_SCOPED":
        raise RuntimeError("SELFTEST_SCOPE")
    checks += 1
    if _require_choice("reconciliation_work_item", HISTORICAL_DEBT_DISPOSITIONS, "HISTORICAL_DEBT_DISPOSITION") != "RECONCILIATION_WORK_ITEM":
        raise RuntimeError("SELFTEST_DISPOSITION")
    checks += 1
    if _migration_path("supabase/migrations/20261001010101_probe.sql") != (
        "20261001010101",
        "probe",
        "supabase/migrations/20261001010101_probe.sql",
    ):
        raise RuntimeError("SELFTEST_PATH")
    checks += 1
    try:
        _migration_path("supabase/migrations/not_a_version.sql")
    except RuntimeError as exc:
        if not str(exc).startswith("FAIL_MIGRATION_PARITY_CHANGESET_FILENAME"):
            raise
    else:
        raise RuntimeError("SELFTEST_INVALID_FILENAME")
    checks += 1
    print(f"PASS_MIGRATION_SOURCE_PARITY_SCOPED_SELFTEST checks={checks}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--base-ref", default="main")
    parser.add_argument("--event-name", default="pull_request")
    parser.add_argument("--output-dir", default=".lf_migration_source_parity")
    parser.add_argument("--control-maturity", required=True)
    parser.add_argument("--evaluation-scope", required=True)
    parser.add_argument("--historical-debt-disposition", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    repo_root = Path(args.repo_root).resolve()
    if repo_root != ROOT:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_REPO_ROOT expected={ROOT} observed={repo_root}")
    maturity = _require_choice(args.control_maturity, CONTROL_MATURITIES, "CONTROL_MATURITY")
    scope = _require_choice(args.evaluation_scope, EVALUATION_SCOPES, "EVALUATION_SCOPE")
    disposition = _require_choice(
        args.historical_debt_disposition,
        HISTORICAL_DEBT_DISPOSITIONS,
        "HISTORICAL_DEBT_DISPOSITION",
    )
    base_sha = _base._require_sha(args.base_sha, "BASE")
    head_sha = _base._require_sha(args.head_sha, "HEAD")
    base_ref = _base._require_base_ref(args.base_ref)
    if args.event_name not in {"pull_request", "push", "workflow_dispatch"}:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_EVENT_NAME:{args.event_name!r}")

    output_dir = (ROOT / args.output_dir).resolve()
    output_dir.relative_to(ROOT)
    output_dir.mkdir(parents=True, exist_ok=True)

    if scope in {"FULL_CURRENT_STATE", "HISTORICAL_RECONCILIATION"}:
        command = [
            sys.executable,
            str(BASE_RUNNER),
            "--repo-root", str(ROOT),
            "--base-sha", base_sha,
            "--head-sha", head_sha,
            "--base-ref", base_ref,
            "--event-name", args.event_name,
            "--output-dir", args.output_dir,
        ]
        proc = subprocess.run(command, cwd=ROOT, check=False)
        _enrich_summary(
            output_dir=output_dir,
            maturity=maturity,
            scope=scope,
            disposition=disposition,
            base_sha=base_sha,
            head_sha=head_sha,
            changed=[],
        )
        return proc.returncode
    if scope == "AFFECTED_DEPENDENCIES":
        raise RuntimeError("FAIL_MIGRATION_PARITY_SCOPE_NOT_IMPLEMENTED:AFFECTED_DEPENDENCIES")
    if scope != "CHANGESET_SCOPED":
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_SCOPE_UNSUPPORTED:{scope}")
    if maturity not in {"BUILD", "QUALIFICATION", "CUTOVER", "ACTIVE"}:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_SCOPE_MATURITY_MISMATCH:{maturity}:{scope}")

    _base._verify_exact_context(base_sha, head_sha, base_ref)
    changed = _changeset_migrations(base_sha, head_sha)
    full_migrations = ROOT / "supabase/migrations"
    scoped = _build_scoped_tree(
        full_migrations=full_migrations,
        output_dir=output_dir,
        changed=changed,
    )
    inputs = _prepare_scoped_inputs(scoped=scoped, output_dir=output_dir, changed=changed)
    result = _base._run_parity(
        migrations=scoped,
        inputs=inputs,
        output_dir=output_dir,
        event_name=args.event_name,
        base_ref=base_ref,
    )
    _enrich_summary(
        output_dir=output_dir,
        maturity=maturity,
        scope=scope,
        disposition=disposition,
        base_sha=base_sha,
        head_sha=head_sha,
        changed=changed,
    )
    if result == 0:
        print(
            "PASS_PASE_EVALUATION_SCOPE_POLICY_V1 "
            f"maturity={maturity} scope={scope} migrations={len(changed)} "
            f"historical_debt_disposition={disposition}"
        )
    return result


if __name__ == "__main__":
    raise SystemExit(main())
