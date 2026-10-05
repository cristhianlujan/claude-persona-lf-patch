#!/usr/bin/env python3
"""Context-aware PASE carrier for MIGRATION_SOURCE_PARITY.

The existing run_migration_source_parity_flow_v1.py remains the deliberate
FULL_CURRENT_STATE / HISTORICAL_RECONCILIATION audit runner. This carrier binds
the blocking verdict to the exact current changeset while preserving exact-head,
source-first, authority/currentness, checkpoint readback, selftests and negatives.

Authority:
- plan event #19868: PASE_EVALUATION_SCOPE_POLICY_V1
- EKB event #19869: PASE-CONTEXT-AWARE-EVALUATION-NO-HISTORICAL-DRAG-001
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[3]
FULL_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py"
MIGRATIONS = ROOT / "supabase/migrations"
POLICY_ID = "PASE_EVALUATION_SCOPE_POLICY_V1"
EXPECTED_MATURITY = "CUTOVER"
EXPECTED_SCOPE = "CHANGESET_SCOPED"
EXPECTED_HISTORICAL_DISPOSITION = "RECONCILIATION_WORK_ITEM"


def _load_full_runner():
    spec = importlib.util.spec_from_file_location("lf_migration_source_parity_full_audit_runner", FULL_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_FULL_RUNNER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


FULL = _load_full_runner()


def _require_exact(value: str, expected: str, label: str) -> str:
    normalized = value.strip().upper()
    if normalized != expected:
        raise RuntimeError(
            f"FAIL_MIGRATION_PARITY_{label}:expected={expected}:observed={normalized or '<empty>'}"
        )
    return normalized


def _parse_name_status(text: str) -> list[str]:
    """Return current migration paths; fail closed on destructive/ambiguous changes."""
    paths: list[str] = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        fields = raw.split("\t")
        status = fields[0]
        material_paths = [
            path.replace("\\", "/")
            for path in fields[1:]
            if path.replace("\\", "/").startswith("supabase/migrations/")
        ]
        if not material_paths:
            continue
        if status not in {"A", "M"} or len(fields) != 2:
            raise RuntimeError(
                "FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS:"
                f"{raw}"
            )
        path = material_paths[0]
        filename = path.rsplit("/", 1)[-1]
        match = re.fullmatch(r"(\d{14})_(.+)\.sql", filename)
        if match is None:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_FILENAME:{path}")
        if match.group(1) <= FULL.CLASSIFICATION_BASELINE_END:
            raise RuntimeError(
                "FAIL_MIGRATION_PARITY_FOCAL_HISTORICAL_MUTATION:"
                f"{path}"
            )
        paths.append(path)
    if len(paths) != len(set(paths)):
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_DUPLICATE_PATH")
    return sorted(paths)


def _changed_migration_paths(base_sha: str, head_sha: str) -> list[str]:
    proc = FULL._git(
        "diff",
        "--name-status",
        f"{base_sha}...{head_sha}",
        "--",
        "supabase/migrations",
    )
    return _parse_name_status(proc.stdout)


def _checkpoint_identity() -> tuple[Path, str, str, tuple[str, ...]]:
    adapter = FULL._load_parity_adapter()
    matches: list[Path] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        if not path.stat().st_size:
            continue
        first = path.read_text(encoding="utf-8").splitlines()[0]
        marker = adapter.MARKER_RE.fullmatch(first)
        if marker:
            matches.append(path)
    if len(matches) != 1:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_CHECKPOINT_COUNT:{len(matches)}")
    checkpoint = matches[0]
    filename = adapter.FILENAME_RE.fullmatch(checkpoint.name)
    if filename is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_CHECKPOINT_FILENAME")
    version, name = filename.groups()
    first = checkpoint.read_text(encoding="utf-8").splitlines()[0]
    marker = adapter.MARKER_RE.fullmatch(first)
    if marker is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_CHECKPOINT_MARKER")
    if not adapter.managed_source(checkpoint, version, name):
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_CHECKPOINT_NOT_MANAGED")
    return checkpoint, version, name, marker.groups()


def _build_scoped_snapshot(
    *, output_dir: Path, changed_paths: list[str]
) -> tuple[Path, list[str], list[str]]:
    adapter = FULL._load_parity_adapter()
    scoped = output_dir / "focal_migrations"
    if scoped.exists():
        shutil.rmtree(scoped)
    scoped.mkdir(parents=True, exist_ok=True)

    checkpoint, checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
    shutil.copy2(checkpoint, scoped / checkpoint.name)

    focal_versions: list[str] = []
    managed_versions: list[str] = []
    for repo_path in changed_paths:
        source = ROOT / repo_path
        if not source.is_file():
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_SOURCE_MISSING:{repo_path}")
        match = adapter.FILENAME_RE.fullmatch(source.name)
        if match is None:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_FILENAME:{repo_path}")
        version, name = match.groups()
        focal_versions.append(version)
        destination = scoped / source.name
        shutil.copy2(source, destination)
        if adapter.managed_source(destination, version, name):
            managed_versions.append(version)

    if len(focal_versions) != len(set(focal_versions)):
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_DUPLICATE_VERSION")
    return scoped, sorted(focal_versions), sorted(set(managed_versions))


def _pg_array(versions: list[str]) -> str:
    if any(re.fullmatch(r"\d{14}", version) is None for version in versions):
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_VERSION_LITERAL")
    return "{" + ",".join(versions) + "}"


def _prepare_focal_inputs(
    *, output_dir: Path, focal_versions: list[str], managed_versions: list[str]
) -> dict[str, Path]:
    """Build current-change evidence plus bounded live checkpoint readback."""
    output_dir.mkdir(parents=True, exist_ok=True)
    env = FULL._pg_env()
    checkpoint, checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
    context_versions = sorted(set(focal_versions))
    context_literal = _pg_array(context_versions)
    managed_literal = _pg_array(managed_versions)

    post_cutover = output_dir / "lf-post-cutover-migrations-compact.csv"
    grandfathered = output_dir / "lf-grandfathered-migrations.csv"
    legacy = output_dir / "lf-legacy-checkpoint.csv"
    statement_counts = output_dir / "lf-migration-statement-counts.csv"
    owner_csv = output_dir / "lf-migration-owner-currentness.csv"
    owner_json = output_dir / "lf-migration-external-owner-currentness.json"

    post_sql = f"""select version,coalesce(name,''),'sha256:' || (select encode(extensions.digest(convert_to(regexp_replace(coalesce(string_agg(line,E'\\n' order by ord),''),E'\\n+$',''),'UTF8'),'sha256'),'hex') from regexp_split_to_table(replace(replace(coalesce(array_to_string(sm.statements,E'\\n'),''),E'\\r\\n',E'\\n'),E'\\r',E'\\n'),E'\\n') with ordinality as x(line,ord) where line !~ '^[[:space:]]*--') from supabase_migrations.schema_migrations sm where version=any('{context_literal}'::text[]) order by version"""
    FULL._write_text(post_cutover, FULL._psql(post_sql, env=env), max_bytes=131072)

    statement_sql = f"""select version,coalesce(cardinality(statements),0)::text from supabase_migrations.schema_migrations where version=any('{managed_literal}'::text[]) order by version"""
    FULL._write_text(statement_counts, FULL._psql(statement_sql, env=env), max_bytes=65536)

    # Aggregate attestation for the immutable historical ledger segment.
    grandfather_sql = f"""with x as (select version,coalesce(name,'') as name,array_to_string(statements,E'\\n') as sql_text from supabase_migrations.schema_migrations where version > '{FULL.CUTOVER}' and version <= '{FULL.CLASSIFICATION_BASELINE_END}') select count(*)::text,encode(extensions.digest(convert_to(coalesce(string_agg(version||E'\\n'||name||E'\\n'||sql_text,E'\\n--MIGRATION--\\n' order by version),''),'UTF8'),'sha256'),'hex') from x"""
    FULL._write_text(grandfathered, FULL._psql(grandfather_sql, env=env))

    legacy_sql = f"""select count(*)::text,encode(extensions.digest(convert_to(string_agg(version||E'\\n'||coalesce(name,'')||E'\\n'||array_to_string(statements,E'\\n--STATEMENT--\\n'),E'\\n--MIGRATION--\\n' order by version),'UTF8'),'sha256'),'hex') from supabase_migrations.schema_migrations where version between '{FULL.LEGACY_START}' and '{FULL.LEGACY_END}'"""
    FULL._write_text(legacy, FULL._psql(legacy_sql, env=env))

    owner_sql = f"""select g.execution_id,e.status,e.operation_code,coalesce(g.receipt->>'repository',''),coalesce(g.receipt->>'target_path',''),coalesce(g.receipt->>'migration_version',''),coalesce(g.receipt->>'migration_name',''),coalesce(g.receipt->>'pr_number',''),coalesce(g.receipt->>'pr_head_sha',''),coalesce(g.receipt->>'source_blob',''),coalesce(g.receipt->>'write_readback',''),coalesce(g.receipt->>'currentness_result',''),coalesce(g.receipt->>'ddl_replayed',''),encode(convert_to(coalesce(array_to_string(m.statements,chr(10)),''),'UTF8'),'hex'),coalesce(cardinality(m.statements),0)::text from public.lf_operation_effect_guard g join public.lf_operation_execution e using(execution_id) join supabase_migrations.schema_migrations m on m.version=g.receipt->>'migration_version' and m.name=g.receipt->>'migration_name' where g.effect_scope like 'MIGRATION_OWNER_CURRENTNESS:%' and g.state='SUCCEEDED' and g.receipt->>'schema_version'='lf-migration-owner-currentness/v1' and g.receipt->>'migration_version'=any('{context_literal}'::text[]) order by g.resolved_at desc nulls last,g.execution_id"""
    FULL._write_text(owner_csv, FULL._psql(owner_sql, env=env))
    owner_payload = FULL._build_external_owner_evidence(owner_csv)
    owner_json.write_text(json.dumps(owner_payload, sort_keys=True) + "\n", encoding="utf-8")

    return {
        "post_cutover": post_cutover,
        "grandfathered": grandfathered,
        "legacy": legacy,
        "statement_counts": statement_counts,
        "owner_json": owner_json,
    }


def _write_scope_manifest(
    *,
    output_dir: Path,
    base_sha: str,
    head_sha: str,
    changed_paths: list[str],
    focal_versions: list[str],
    maturity: str,
    evaluation_scope: str,
    historical_disposition: str,
) -> None:
    _checkpoint, checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
    payload = {
        "schema_version": "lf-migration-source-parity-scope/v2",
        "policy_id": POLICY_ID,
        "control_maturity": maturity,
        "evaluation_scope": evaluation_scope,
        "historical_debt_disposition": historical_disposition,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "changed_migration_paths": changed_paths,
        "focal_versions": focal_versions,
        "structural_checkpoint_version": checkpoint_version,
        "checkpoint_readback": "REQUIRED_BOUNDED_AGGREGATE",
        "unbounded_historical_scan": False,
        "historical_reconciliation": "OUT_OF_BAND_NOT_BLOCKING_WITHOUT_CAUSAL_BINDING",
        "plan_event_id": 19868,
        "ekb_event_id": 19869,
    }
    (output_dir / "scope-manifest.json").write_text(
        json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8"
    )


def _enrich_run_summary(
    *,
    output_dir: Path,
    maturity: str,
    evaluation_scope: str,
    historical_disposition: str,
    changed_paths: list[str],
) -> None:
    path = output_dir / "run-summary.json"
    payload: dict[str, object] = {}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                payload.update(loaded)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            pass
    payload.update(
        {
            "policy_id": POLICY_ID,
            "control_maturity": maturity,
            "evaluation_scope": evaluation_scope,
            "historical_debt_disposition": historical_disposition,
            "changeset_migration_count": len(changed_paths),
            "changeset_migrations": changed_paths,
            "unbounded_historical_scan": False,
        }
    )
    path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")


def self_test() -> int:
    checks = 0
    if _require_exact("cutover", EXPECTED_MATURITY, "CONTROL_MATURITY") != EXPECTED_MATURITY:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_MATURITY")
    checks += 1
    if _require_exact("changeset_scoped", EXPECTED_SCOPE, "EVALUATION_SCOPE") != EXPECTED_SCOPE:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_SCOPE")
    checks += 1
    if _require_exact(
        "reconciliation_work_item",
        EXPECTED_HISTORICAL_DISPOSITION,
        "HISTORICAL_DEBT_DISPOSITION",
    ) != EXPECTED_HISTORICAL_DISPOSITION:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_DISPOSITION")
    checks += 1
    if _parse_name_status("A\tsupabase/migrations/20261002010101_lf_probe.sql\n") != [
        "supabase/migrations/20261002010101_lf_probe.sql"
    ]:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_POSITIVE")
    checks += 1
    if _parse_name_status("") != []:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_EMPTY")
    checks += 1
    for row in (
        "D\tsupabase/migrations/20261002010101_lf_probe.sql\n",
        "R100\tsupabase/migrations/20261002010101_lf_old.sql\tsupabase/migrations/20261002010102_lf_new.sql\n",
    ):
        try:
            _parse_name_status(row)
        except RuntimeError as exc:
            if not str(exc).startswith("FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS"):
                raise
        else:
            raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_DESTRUCTIVE_ACCEPTED")
        checks += 1
    print(f"PASS_MIGRATION_SOURCE_PARITY_FOCAL_SELFTEST={checks}/7")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--base-sha")
    parser.add_argument("--head-sha")
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
    maturity = _require_exact(args.control_maturity, EXPECTED_MATURITY, "CONTROL_MATURITY")
    evaluation_scope = _require_exact(args.evaluation_scope, EXPECTED_SCOPE, "EVALUATION_SCOPE")
    historical_disposition = _require_exact(
        args.historical_debt_disposition,
        EXPECTED_HISTORICAL_DISPOSITION,
        "HISTORICAL_DEBT_DISPOSITION",
    )
    base_sha = FULL._require_sha(args.base_sha or "", "BASE")
    head_sha = FULL._require_sha(args.head_sha or "", "HEAD")
    base_ref = FULL._require_base_ref(args.base_ref)
    if args.event_name not in {"pull_request", "push", "workflow_dispatch"}:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_EVENT_NAME:{args.event_name!r}")

    FULL._verify_exact_context(base_sha, head_sha, base_ref)
    output_dir = (ROOT / args.output_dir).resolve()
    try:
        output_dir.relative_to(ROOT)
    except ValueError as exc:
        raise RuntimeError("FAIL_MIGRATION_PARITY_OUTPUT_OUTSIDE_REPO") from exc
    output_dir.mkdir(parents=True, exist_ok=True)

    changed_paths = _changed_migration_paths(base_sha, head_sha)
    scoped_migrations, focal_versions, managed_versions = _build_scoped_snapshot(
        output_dir=output_dir,
        changed_paths=changed_paths,
    )
    _write_scope_manifest(
        output_dir=output_dir,
        base_sha=base_sha,
        head_sha=head_sha,
        changed_paths=changed_paths,
        focal_versions=focal_versions,
        maturity=maturity,
        evaluation_scope=evaluation_scope,
        historical_disposition=historical_disposition,
    )
    inputs = _prepare_focal_inputs(
        output_dir=output_dir,
        focal_versions=focal_versions,
        managed_versions=managed_versions,
    )
    rc = FULL._run_parity(
        migrations=scoped_migrations,
        inputs=inputs,
        output_dir=output_dir,
        event_name=args.event_name,
        base_ref=base_ref,
    )
    _enrich_run_summary(
        output_dir=output_dir,
        maturity=maturity,
        evaluation_scope=evaluation_scope,
        historical_disposition=historical_disposition,
        changed_paths=changed_paths,
    )
    if rc == 0:
        print(
            "PASS_PASE_EVALUATION_SCOPE_POLICY_V1 "
            f"maturity={maturity} scope={evaluation_scope} migrations={len(focal_versions)} "
            f"historical_debt_disposition={historical_disposition} "
            "NO_UNBOUNDED_HISTORICAL_SCAN_IN_CRITICAL_PATH=true"
        )
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
