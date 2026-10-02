#!/usr/bin/env python3
"""Focal PASE carrier for MIGRATION_SOURCE_PARITY.

The existing run_migration_source_parity_flow_v1.py remains the full-history audit
runner. This carrier intentionally limits the *blocking* parity set to migration
sources changed by the exact base...head changeset, while delegating comparison,
source-first semantics and negative checks to the existing canonical adapter.

Authority: EKB CI-MIGRATION-LEDGER-BROAD-SCAN-001.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[3]
FULL_RUNNER = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py"
MIGRATIONS = ROOT / "supabase/migrations"
FOCAL_SCOPE = "FOCAL_CHANGESET"


def _load_full_runner():
    spec = importlib.util.spec_from_file_location("lf_migration_source_parity_full_audit_runner", FULL_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_FULL_RUNNER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


FULL = _load_full_runner()


def _parse_name_status(text: str) -> list[str]:
    """Return focal migration paths; fail closed on destructive/ambiguous changes."""
    paths: list[str] = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        fields = raw.split("\t")
        status = fields[0]
        if status not in {"A", "M"} or len(fields) != 2:
            raise RuntimeError(
                "FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS:"
                f"{raw}"
            )
        path = fields[1].replace("\\", "/")
        if not path.startswith("supabase/migrations/"):
            continue
        filename = path.rsplit("/", 1)[-1]
        match = re.fullmatch(r"(\d{14})_(.+)\.sql", filename)
        if match is None:
            raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_FILENAME:{path}")
        if match.group(1) <= FULL.CUTOVER:
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


def _checkpoint_source() -> Path:
    adapter = FULL._load_parity_adapter()
    matches: list[Path] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        if not path.stat().st_size:
            continue
        first = path.read_text(encoding="utf-8").splitlines()[0]
        if adapter.MARKER_RE.fullmatch(first):
            matches.append(path)
    if len(matches) != 1:
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_FOCAL_CHECKPOINT_COUNT:{len(matches)}")
    return matches[0]


def _checkpoint_identity() -> tuple[Path, str, str, tuple[str, ...]]:
    adapter = FULL._load_parity_adapter()
    checkpoint = _checkpoint_source()
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

    checkpoint, _checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
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
    return scoped, sorted(focal_versions), sorted(managed_versions)


def _pg_array(versions: list[str]) -> str:
    if any(re.fullmatch(r"\d{14}", version) is None for version in versions):
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_VERSION_LITERAL")
    return "{" + ",".join(versions) + "}"


def _prepare_focal_inputs(
    *, output_dir: Path, focal_versions: list[str], managed_versions: list[str]
) -> dict[str, Path]:
    """Prepare only focal rows plus the structural checkpoint anchor.

    The checkpoint is not part of the focal blocking set, but the canonical
    adapter legitimately sees its source because it carries the legacy integrity
    marker. Therefore its exact ledger row must accompany the scoped snapshot;
    otherwise source-first would falsely classify the anchor itself as pending.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    env = FULL._pg_env()
    checkpoint, checkpoint_version, _checkpoint_name, marker_groups = _checkpoint_identity()

    context_versions = sorted(set(focal_versions) | {checkpoint_version})
    context_managed_versions = sorted(set(managed_versions) | {checkpoint_version})
    context_literal = _pg_array(context_versions)
    managed_literal = _pg_array(context_managed_versions)

    post_cutover = output_dir / "lf-post-cutover-migrations-compact.csv"
    grandfathered = output_dir / "lf-grandfathered-migrations.csv"
    legacy = output_dir / "lf-legacy-checkpoint.csv"
    statement_counts = output_dir / "lf-migration-statement-counts.csv"
    owner_json = output_dir / "lf-migration-external-owner-currentness.json"

    post_sql = f"""select version,coalesce(name,''),'sha256:' || (select encode(extensions.digest(convert_to(regexp_replace(coalesce(string_agg(line,E'\\n' order by ord),''),E'\\n+$',''),'UTF8'),'sha256'),'hex') from regexp_split_to_table(replace(replace(coalesce(array_to_string(sm.statements,E'\\n'),''),E'\\r\\n',E'\\n'),E'\\r',E'\\n'),E'\\n') with ordinality as x(line,ord) where line !~ '^[[:space:]]*--') from supabase_migrations.schema_migrations sm where version=any('{context_literal}'::text[]) order by version"""
    FULL._write_text(post_cutover, FULL._psql(post_sql, env=env), max_bytes=131072)

    statement_sql = f"""select version,coalesce(cardinality(statements),0)::text from supabase_migrations.schema_migrations where version=any('{managed_literal}'::text[]) order by version"""
    FULL._write_text(statement_counts, FULL._psql(statement_sql, env=env), max_bytes=65536)

    # Historical integrity is intentionally not a focal blocking set. The full
    # runner remains available for that audit lane. These compatibility inputs
    # bind the legacy adapter interface to its already-declared checkpoint.
    FULL._write_text(
        grandfathered,
        f"{FULL.GRANDFATHERED_COUNT},{FULL.GRANDFATHERED_SHA256}\n",
    )
    _marker_cutover, _legacy_start, _legacy_end, legacy_count, legacy_sha = marker_groups
    FULL._write_text(legacy, f"{legacy_count},{legacy_sha}\n")

    owner_json.write_text(
        json.dumps(
            {
                "schema_version": "lf-migration-external-owner-currentness/v1",
                "repository": __import__("os").environ.get("GITHUB_REPOSITORY", ""),
                "complete": True,
                "owners": [],
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return {
        "post_cutover": post_cutover,
        "grandfathered": grandfathered,
        "legacy": legacy,
        "statement_counts": statement_counts,
        "owner_json": owner_json,
    }


def _write_scope_manifest(
    *, output_dir: Path, base_sha: str, head_sha: str, changed_paths: list[str], focal_versions: list[str]
) -> None:
    _checkpoint, checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
    payload = {
        "schema_version": "lf-migration-source-parity-scope/v1",
        "scope": FOCAL_SCOPE,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "changed_migration_paths": changed_paths,
        "focal_versions": focal_versions,
        "structural_checkpoint_version": checkpoint_version,
        "historical_full_audit": "OUT_OF_BAND_NOT_BLOCKING",
        "authority": "EKB:CI-MIGRATION-LEDGER-BROAD-SCAN-001",
    }
    (output_dir / "scope-manifest.json").write_text(
        json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8"
    )


def self_test() -> int:
    if _parse_name_status("A\tsupabase/migrations/20261002010101_lf_probe.sql\n") != [
        "supabase/migrations/20261002010101_lf_probe.sql"
    ]:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_POSITIVE")
    if _parse_name_status("") != []:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_EMPTY")
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
    _checkpoint, checkpoint_version, _checkpoint_name, _marker = _checkpoint_identity()
    if checkpoint_version <= FULL.CUTOVER:
        raise RuntimeError("FAIL_MIGRATION_PARITY_FOCAL_SELFTEST_CHECKPOINT_CONTEXT")
    print("PASS_MIGRATION_SOURCE_PARITY_FOCAL_SELFTEST=5/5")
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
        raise RuntimeError(f"FAIL_MIGRATION_PARITY_REPO_ROOT expected={ROOT} observed={repo_root}")
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
    print(
        "PASS_MIGRATION_SOURCE_PARITY_SCOPE "
        f"scope={FOCAL_SCOPE} migrations={len(focal_versions)} "
        "historical_full_audit=OUT_OF_BAND_NOT_BLOCKING"
        if rc == 0
        else f"FAIL_MIGRATION_SOURCE_PARITY_SCOPE scope={FOCAL_SCOPE} rc={rc}"
    )
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
