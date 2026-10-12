#!/usr/bin/env python3
"""Fail-closed helpers for the S30 source-first migration transport.

This module intentionally does not connect to GitHub or Postgres.  The GitHub
workflow supplies independently read evidence; these helpers validate it and
render the single atomic SQL transaction used by the transport.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

PATH_RE = re.compile(r"^supabase/migrations/(?P<version>[0-9]{14})_(?P<name>[a-z0-9_]+)\.sql$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
EXEC_RE = re.compile(r"^[A-Z0-9][A-Z0-9_.:-]{5,191}$")
TX_CONTROL_RE = re.compile(r"(?im)^\s*(?:begin|commit|rollback|start\s+transaction)\s*;\s*(?:--.*)?$")
PSQL_META_RE = re.compile(r"(?m)^\s*\\")
TRANSPORT_CODE = "SOURCE_FIRST_EXACT_VERSION_GITHUB_MAIN_ATOMIC_LEDGER_DML_V1"


class GuardError(ValueError):
    pass


def parse_target(path: str) -> tuple[str, str]:
    match = PATH_RE.fullmatch(path)
    if not match:
        raise GuardError("BLOCK_MIGRATION_TARGET_PATH")
    return match.group("version"), match.group("name")


def normalize_source(raw: str) -> str:
    return raw.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n")


def source_sha256(raw: str) -> str:
    return hashlib.sha256(normalize_source(raw).encode("utf-8")).hexdigest()


def validate_source_sql(raw: str) -> None:
    if not raw.strip():
        raise GuardError("BLOCK_MIGRATION_SOURCE_EMPTY")
    if TX_CONTROL_RE.search(raw):
        raise GuardError("BLOCK_MIGRATION_SOURCE_TRANSACTION_CONTROL")
    if PSQL_META_RE.search(raw):
        raise GuardError("BLOCK_MIGRATION_SOURCE_PSQL_META_COMMAND")


def validate_main_binding(main_sha: str, checkout_sha: str, remote_main_sha: str) -> None:
    if not SHA_RE.fullmatch(main_sha):
        raise GuardError("BLOCK_MIGRATION_MAIN_SHA_FORMAT")
    if checkout_sha != main_sha:
        raise GuardError("BLOCK_MIGRATION_CHECKOUT_NOT_EXACT_MAIN")
    if remote_main_sha != main_sha:
        raise GuardError("BLOCK_MIGRATION_REMOTE_MAIN_MOVED")


def validate_execution(row: dict[str, Any], *, execution_id: str, path: str, main_sha: str,
                       version: str, name: str, sha256: str) -> None:
    if not EXEC_RE.fullmatch(execution_id):
        raise GuardError("BLOCK_MIGRATION_EXECUTION_ID_FORMAT")
    if row.get("execution_id") != execution_id:
        raise GuardError("BLOCK_MIGRATION_EXECUTION_ID_MISMATCH")
    if row.get("operation_code") != "ACTUALIZACION_DB_LF":
        raise GuardError("BLOCK_MIGRATION_OPERATION_ROUTE")
    if row.get("target_type") != "MIGRATION":
        raise GuardError("BLOCK_MIGRATION_TARGET_TYPE")
    if row.get("target_path") != path:
        raise GuardError("BLOCK_MIGRATION_EXECUTION_TARGET_PATH")
    if row.get("status") != "IN_PROGRESS":
        raise GuardError("BLOCK_MIGRATION_EXECUTION_NOT_IN_PROGRESS")
    manifest = row.get("manifest")
    if not isinstance(manifest, dict):
        raise GuardError("BLOCK_MIGRATION_EXECUTION_MANIFEST")
    expected = {
        "source_first": True,
        "main_merge_sha": main_sha,
        "migration_version": version,
        "migration_name": name,
        "source_sha256": sha256,
        "exact_version_transport": TRANSPORT_CODE,
        "apply_migration_forbidden_for_this_lane": True,
    }
    bad = [key for key, value in expected.items() if manifest.get(key) != value]
    if bad:
        raise GuardError("BLOCK_MIGRATION_EXECUTION_BINDING:" + ",".join(sorted(bad)))
    if manifest.get("source_parity_state") not in {"PREAPPLY_READY", "BOOTSTRAP_PREAPPLY_READY"}:
        raise GuardError("BLOCK_MIGRATION_SOURCE_PARITY_STATE")


def validate_preapply_shape(*, local_managed: set[str], remote_managed: set[str], target_version: str) -> None:
    if target_version not in local_managed:
        raise GuardError("BLOCK_MIGRATION_TARGET_NOT_MANAGED_LOCAL")
    expected_remote = local_managed - {target_version}
    remote_only = sorted(remote_managed - expected_remote)
    local_only = sorted(expected_remote - remote_managed)
    if remote_only:
        raise GuardError("BLOCK_MIGRATION_REMOTE_ONLY:" + ",".join(remote_only))
    if local_only:
        raise GuardError("BLOCK_MIGRATION_PREEXISTING_LOCAL_ONLY:" + ",".join(local_only))
    if target_version in remote_managed:
        raise GuardError("BLOCK_MIGRATION_TARGET_ALREADY_APPLIED")


def _sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _dollar_tag(source: str, sha256: str) -> str:
    for width in (12, 20, 32, 64):
        tag = f"$lf_migration_{sha256[:width]}$"
        if tag not in source:
            return tag
    raise GuardError("BLOCK_MIGRATION_DOLLAR_QUOTE_COLLISION")


def render_atomic_sql(*, source: str, path: str, execution_id: str, main_sha: str) -> str:
    version, name = parse_target(path)
    validate_source_sql(source)
    sha = source_sha256(source)
    if not SHA_RE.fullmatch(main_sha):
        raise GuardError("BLOCK_MIGRATION_MAIN_SHA_FORMAT")
    if not EXEC_RE.fullmatch(execution_id):
        raise GuardError("BLOCK_MIGRATION_EXECUTION_ID_FORMAT")
    tag = _dollar_tag(source, sha)
    source_norm = normalize_source(source)
    version_lit = _sql_literal(version)
    name_lit = _sql_literal(name)
    execution_lit = _sql_literal(execution_id)
    main_lit = _sql_literal(main_sha)
    sha_lit = _sql_literal(sha)
    transport_lit = _sql_literal(TRANSPORT_CODE)
    return f"""\\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('LF_MIGRATION:{version}', 0));
DO $lf_guard$
BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version={version_lit}) THEN
    RAISE EXCEPTION 'BLOCK_MIGRATION_TARGET_ALREADY_APPLIED version={version}';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id={execution_lit}
      AND operation_code='ACTUALIZACION_DB_LF'
      AND target_type='MIGRATION'
      AND target_path={_sql_literal(path)}
      AND status='IN_PROGRESS'
      AND manifest->>'source_first'='true'
      AND manifest->>'main_merge_sha'={main_lit}
      AND manifest->>'migration_version'={version_lit}
      AND manifest->>'migration_name'={name_lit}
      AND manifest->>'source_sha256'={sha_lit}
      AND manifest->>'exact_version_transport'={transport_lit}
      AND manifest->>'apply_migration_forbidden_for_this_lane'='true'
      AND manifest->>'source_parity_state' IN ('PREAPPLY_READY','BOOTSTRAP_PREAPPLY_READY')
  ) THEN
    RAISE EXCEPTION 'BLOCK_MIGRATION_EXECUTION_BINDING';
  END IF;
END
$lf_guard$;

-- LF canonical source begins.  This executes inside the same transaction as ledger persistence.
{source_norm}
-- LF canonical source ends.

INSERT INTO supabase_migrations.schema_migrations(
  version, statements, name, created_by, idempotency_key
) VALUES (
  {version_lit}, ARRAY[{tag}{source_norm}{tag}], {name_lit}, {execution_lit},
  {_sql_literal('lf-source-first:' + main_sha + ':' + sha)}
);

UPDATE public.lf_operation_execution
SET manifest = coalesce(manifest,'{{}}'::jsonb) || jsonb_build_object(
      'source_parity_state','APPLIED_PENDING_POSTREADBACK',
      'applied_main_sha',{main_lit},
      'applied_source_sha256',{sha_lit},
      'exact_version_transport',{transport_lit}
    ),
    updated_by_execution_id={execution_lit},
    updated_at=now()
WHERE execution_id={execution_lit};
COMMIT;
"""


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--migration-path")
    parser.add_argument("--execution-id")
    parser.add_argument("--main-sha")
    parser.add_argument("--output")
    args = parser.parse_args()
    if not args.render:
        parser.error("--render is required")
    if not all((args.migration_path, args.execution_id, args.main_sha, args.output)):
        parser.error("--migration-path, --execution-id, --main-sha and --output are required")
    source = Path(args.migration_path).read_text(encoding="utf-8")
    sql = render_atomic_sql(source=source, path=args.migration_path, execution_id=args.execution_id, main_sha=args.main_sha)
    Path(args.output).write_text(sql, encoding="utf-8", newline="\n")
    print(json.dumps({"status":"PASS","path":args.migration_path,"source_sha256":source_sha256(source),"transport":TRANSPORT_CODE}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
