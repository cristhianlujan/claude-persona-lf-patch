#!/usr/bin/env python3
"""Emit a reversible PostgreSQL trial for the PE10 helper migration.

This script never connects to a database, requests credentials, starts Train,
applies migrations, or treats static checks as an executed SQL proof.
Run emitted SQL only through an authorized sandbox/Train rollback test lane.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261014152000_lf_pe10_profile_update_readonly_helpers_v1.sql"
FUNCTIONS = (
    "lf_profile_update_verified_receipt_v1(text,text,text,text,text)",
    "lf_profile_update_effective_route_v1(text)",
    "lf_profile_update_evolution_step_guard_v1(text,text,jsonb)",
)
# The migration contains these exact candidate sources (not a second copy).
SOURCES = (
    "skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql",
    "skills/profile_creator/contracts/profile_update_effective_route_reader_candidate_v1.sql",
    "skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql",
)
BEGIN_RE = re.compile(r"(?m)^BEGIN;\s*$")
COMMIT_RE = re.compile(r"(?m)^COMMIT;\s*$")


def verify_source_parity(sql: str) -> None:
    """Prevent Train from admitting a migration with stale helper source bytes.

    Compare the embedded exact source to each canonical candidate file and
    independently verify the Git blob SHA-1 pinned by the source header.
    """
    for path in SOURCES:
        source_bytes = (ROOT / path).read_bytes()
        source_text = source_bytes.decode("utf-8").rstrip("\n")
        git_blob = hashlib.sha1(
            f"blob {len(source_bytes)}\\0".encode("ascii") + source_bytes
        ).hexdigest()
        marker = f"-- SOURCE {path} BLOB {git_blob}"
        if sql.count(marker) != 1:
            raise ValueError("PE10_MIGRATION_SOURCE_BLOB_DRIFT:" + path)
        if not source_text or sql.count(source_text) != 1:
            raise ValueError("PE10_MIGRATION_SOURCE_BYTES_DRIFT:" + path)


def validate_source(sql: str) -> dict[str, object]:
    verify_source_parity(sql)
    starts, ends = list(BEGIN_RE.finditer(sql)), list(COMMIT_RE.finditer(sql))
    if len(starts) != 1 or len(ends) != 1 or sql[ends[0].end():].strip():
        raise ValueError("PE10_ROLLBACK_SOURCE_TRANSACTION_BOUNDARY_INVALID")
    if starts[0].start() >= ends[0].start():
        raise ValueError("PE10_ROLLBACK_SOURCE_ORDER_INVALID")
    for fn in FUNCTIONS:
        if sql.count("public." + fn.split("(")[0] + "(") < 2:
            raise ValueError("PE10_ROLLBACK_HELPER_MISSING:" + fn)
    if "PE10_READONLY_HELPERS_POLICY_DRIFT" not in sql:
        raise ValueError("PE10_ROLLBACK_BASELINE_GUARD_MISSING")
    if "REVOKE ALL ON FUNCTION" not in sql or "GRANT EXECUTE ON FUNCTION" not in sql:
        raise ValueError("PE10_ROLLBACK_ACL_GUARD_MISSING")
    return {
        "source_sha256": hashlib.sha256(sql.encode()).hexdigest(),
        "source_bytes": len(sql.encode()),
        "begin_at": starts[0].start(),
        "commit_at": ends[0].start(),
    }


def emit(sql: str) -> str:
    checked = validate_source(sql)
    start, end = int(checked["begin_at"]), int(checked["commit_at"])
    inner = sql[start + len("BEGIN;"):end]
    return """-- PE10 authorized-only rollback probe. NEVER merge or apply this as a migration.
\\set ON_ERROR_STOP on
BEGIN;
""" + inner + """
-- The new route resolver must consume the frozen requirements of historic
-- executions and must not reinterpret them against today's step catalog.
DO $pe10_legacy$
DECLARE
  v_expected bigint;
  v_correct bigint;
BEGIN
  SELECT count(*) INTO v_expected FROM public.lf_operation_execution
   WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS'
     AND manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}' IS NOT NULL;
  IF v_expected=0 THEN RAISE EXCEPTION 'PE10_ROLLBACK_LEGACY_FIXTURE_MISSING'; END IF;
  SELECT count(*) INTO v_correct FROM public.lf_operation_execution e
   WHERE e.operation_code='ACTUALIZACION_PERFIL_LF' AND e.status='IN_PROGRESS'
     AND e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}' IS NOT NULL
     AND (public.lf_profile_update_effective_route_v1(e.execution_id)->>'outcome')='LEGACY_FROZEN'
     AND (public.lf_profile_update_effective_route_v1(e.execution_id)->'effective_steps')
           = e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
  IF v_correct<>v_expected THEN
    RAISE EXCEPTION 'PE10_ROLLBACK_LEGACY_ROUTE_DRIFT %/%',v_correct,v_expected;
  END IF;
  -- Historical 14-step snapshots (without post_merge_reconcile) must be
  -- preserved exactly; the current 15-step catalogue must not be imposed.
  IF EXISTS(
      SELECT 1 FROM public.lf_operation_execution e
      WHERE e.operation_code='ACTUALIZACION_PERFIL_LF'
        AND e.status='IN_PROGRESS'
        AND jsonb_array_length(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}')=14
        AND (
          public.lf_profile_update_effective_route_v1(e.execution_id)->'effective_steps'
          IS DISTINCT FROM e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}'
        )
    ) THEN
    RAISE EXCEPTION 'PE10_ROLLBACK_14_STEP_HISTORICAL_DRIFT';
  END IF;
  IF NOT has_function_privilege('service_role',
        'public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role',
        'public.lf_profile_update_effective_route_v1(text)','EXECUTE')
    OR NOT has_function_privilege('service_role',
        'public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'PE10_ROLLBACK_HELPER_SERVICE_ACL_MISSING'; END IF;
  IF has_function_privilege('anon',
        'public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
    OR has_function_privilege('authenticated',
        'public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'PE10_ROLLBACK_HELPER_ACL_LEAK'; END IF;
END $pe10_legacy$;
SELECT 'PE10_ROLLBACK_BEFORE_REVERT_PASS' AS assertion;
ROLLBACK;
-- Poststate MUST be verified outside the reverted transaction, same connection.
DO $pe10_post$
BEGIN
  IF to_regprocedure('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)') IS NOT NULL
    OR to_regprocedure('public.lf_profile_update_effective_route_v1(text)') IS NOT NULL
    OR to_regprocedure('public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_ROLLBACK_FUNCTION_RESIDUE'; END IF;
  IF (SELECT count(*) FROM public.lf_operation_steps
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active)<>15
  THEN RAISE EXCEPTION 'PE10_ROLLBACK_STEP_RESIDUE'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_policy_versions
    WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1'
      AND status='ACTIVE'
  ) THEN RAISE EXCEPTION 'PE10_ROLLBACK_POLICY_RESIDUE'; END IF;
END $pe10_post$;
SELECT 'PE10_ROLLBACK_POSTSTATE_PASS' AS assertion;
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-sql", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.emit_sql == args.self_test:
        parser.error("choose exactly one of --emit-sql and --self-test")
    sql = MIGRATION.read_text(encoding="utf-8")
    record = validate_source(sql)
    trial = emit(sql)
    if args.emit_sql:
        sys.stdout.write(trial)
    else:
        if not trial.rstrip().endswith("SELECT 'PE10_ROLLBACK_POSTSTATE_PASS' AS assertion;"):
            raise SystemExit("PE10_ROLLBACK_TAIL_INVALID")
        if len(COMMIT_RE.findall(trial)) != 0:
            raise SystemExit("PE10_ROLLBACK_COMMIT_LEAK")
        if trial.count("\nROLLBACK;\n") != 1:
            raise SystemExit("PE10_ROLLBACK_NOT_EXACTLY_ONCE")
        bad = sql.replace("\nCOMMIT;\n", "\nCOMMIT;\nCOMMIT;\n")
        try:
            validate_source(bad)
        except ValueError:
            pass
        else:
            raise SystemExit("PE10_ROLLBACK_DANGEROUS_SOURCE_ACCEPTED")
        # A changed source file or changed migration body must invalidate
        # the frozen bytes before either enters a privileged Train run.
        broken = sql.replace(
            "-- Candidate-only: NOT a deployed migration or a grant of Profile Updater write authority.",
            "-- Candidate-only: source tampered before Train admission.",
            1,
        )
        if broken == sql:
            raise SystemExit("PE10_SOURCE_DRIFT_NEGATIVE_FIXTURE_MISSING")
        try:
            validate_source(broken)
        except ValueError as e:
            if "PE10_MIGRATION_SOURCE_BYTES_DRIFT" not in str(e):
                raise
        else:
            raise SystemExit("PE10_SOURCE_DRIFT_NEGATIVE_ACCEPTED")
        print(json.dumps({
            "source_parity": "PASS_3_OF_3_EXACT_BLOBS",
            "negative_drift_rejected": True,
            "status": "PASS_STATIC_ONLY",
            "schema": "PE10_HELPERS_ROLLBACK_PROBE_V1",
            "source_sha256": record["source_sha256"],
            "trial_sha256": hashlib.sha256(trial.encode()).hexdigest(),
            "sql_executed": False,
            "eligible_for_production_claim": False
        }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
