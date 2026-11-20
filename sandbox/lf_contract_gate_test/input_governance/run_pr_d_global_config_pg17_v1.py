#!/usr/bin/env python3
"""PR-D: exact-head real PostgreSQL 17 BEGIN/ROLLBACK against ephemeral CI only."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / ".lf_ci" / "pr_d_global_config"
ORIGIN = ROOT / "supabase/migrations/20261118061500_lf_payment_provider_config_niubiz_generic_v1.sql"
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_d_global_config_rollback.sql"
DEST_GLOB = "*_lf_global_config_consolidation_v1.sql"
PIN_PR_C_SOURCE_SHA256 = "26654ebfbbfdc222fe2045cd019f56ac67848d84ae9c23aa1a61369d35ec7c62"
MARKERS = (
    "PR_D_PREIMAGE_PASS old_rows=1 new_absent=true",
    "PR_D_DUPLICATE_DENIED_PASS",
    "PR_D_BAD_STATUS_DENIED_PASS",
    "PR_D_BAD_TYPE_DENIED_PASS",
    "PR_D_IN_TRANSACTION_PASS columns=8 rls=ON forced=ON policies=0 client_roles_denied=2 migrated_rows=1 real=0 source_absent=true",
    "PR_D_REAL_POST_ROLLBACK_PASS dest_absent=true source_restored=true source_rows=1",
)


def guard(condition: bool, code: str):
    if not condition:
        raise RuntimeError(code)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def psql(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", "5432",
         "-U", "postgres", "-d", "postgres", *args],
        env=os.environ.copy(), text=True, capture_output=True, timeout=110, check=False)


def source_signature() -> str:
    return (
        "SELECT row_to_json(t)::text "
        "FROM (SELECT provider,config_key,config_value,value_status,valid_from,created_at "
        "FROM public.payment_provider_config ORDER BY provider,config_key,valid_from) t"
    )


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {"status": "FAIL", "engine": "REAL_POSTGRESQL_17",
              "target": "EPHEMERAL_CI_SERVICE_ONLY", "remote_supabase_tested": False,
              "persistent_changes_authorized": False}
    try:
        guard(os.environ.get("GITHUB_EVENT_NAME") == "pull_request", "PR_ONLY")
        guard(os.environ.get("GITHUB_REPOSITORY") ==
              "cristhianlujan/claude-persona-lf-patch", "REPO_MISMATCH")
        head = os.environ.get("PR_D_EXACT_HEAD")
        observed = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        guard(bool(head) and observed == head, "PR_D_EXACT_HEAD_DRIFT")
        report["candidate_head"] = head
        for key, expected in (
            ("PGHOST", "127.0.0.1"), ("PGUSER", "postgres"),
            ("PGDATABASE", "postgres"), ("PGPASSWORD", "pr_d_ephemeral_pg17_only"),
        ):
            guard(os.environ.get(key) == expected, "LOCAL_PG_GUARD_" + key)
        matches = list((ROOT / "supabase/migrations").glob(DEST_GLOB))
        guard(len(matches) == 1, "PR_D_MIGRATION_NOT_UNIQUE")
        origin = ORIGIN.read_bytes()
        dest = matches[0].read_bytes()
        harness = HARNESS.read_bytes()
        guard(digest(origin) == PIN_PR_C_SOURCE_SHA256, "PR_C_FIXTURE_SHA256_DRIFT")
        txt = dest.decode()
        guard(txt.count("CREATE TABLE public.lf_global_config") == 1,
              "PR_D_TARGET_CREATE_DRIFT")
        guard(txt.count("DROP TABLE public.payment_provider_config;") == 1,
              "PR_D_SOURCE_DROP_DRIFT")
        guard("CASCADE" not in txt, "PR_D_CASCADE_FORBIDDEN")
        guard(not any(re.match(r"(?i)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;", ln)
                      for ln in txt.splitlines()), "PR_D_NESTED_TRANSACTION")
        guard(not any(ln.lstrip().startswith("\\") for ln in txt.splitlines()),
              "PR_D_PSQL_META_FORBIDDEN")
        template = harness.decode()
        guard(template.count("@@PRC_SOURCE_SQL@@") == 1 and
              template.count("@@PRD_MIGRATION_SQL@@") == 1, "HARNESS_MARKER_DRIFT")
        sql = template.replace("@@PRC_SOURCE_SQL@@", origin.decode()).replace(
            "@@PRD_MIGRATION_SQL@@", txt)
        guard(sql.splitlines().count("BEGIN;") == 1 and
              sql.splitlines().count("ROLLBACK;") == 1 and
              sql.splitlines().count("COMMIT;") == 0, "ROLLBACK_SESSION_DRIFT")
        report["source"] = {
            "pr_c_fixture_sha256": digest(origin),
            "pr_d_migration": matches[0].name,
            "pr_d_migration_sha256": digest(dest),
            "harness_sha256": digest(harness),
            "assembled_sql_sha256": digest(sql.encode()),
        }
        role_setup = psql("-c", "CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;")
        guard(role_setup.returncode == 0, "ROLE_FIXTURE_SETUP_FAILED:" +
              role_setup.stderr[:300])
        # The initial fixture is only installed by the upcoming harness; check after
        # complete rollback that the same original row persists with unchanged timestamps.
        path = OUTPUT / "transaction.sql"
        path.write_text(sql)
        execution = psql("-f", str(path))
        log = execution.stdout + execution.stderr
        (OUTPUT / "postgresql.log").write_text(log)
        report["executed"] = True
        report["sql_exit_code"] = execution.returncode
        report["sql_log_sha256"] = digest(log.encode())
        report["assertions"] = {marker: marker in log for marker in MARKERS}
        rb = psql("-At", "-c",
                  "SELECT CASE WHEN to_regclass('public.lf_global_config') "
                  "IS NULL AND to_regclass('public.payment_provider_config') IS NOT NULL "
                  "THEN 'RESTORED' ELSE 'DRIFT' END")
        rows = psql("-At", "-c", source_signature())
        report["independent_readback"] = rb.stdout.strip()
        report["source_snapshot_rows"] = len(rows.stdout.splitlines())
        report["source_snapshot_sha256"] = digest(rows.stdout.encode())
        report["independent_exit_codes"] = [rb.returncode, rows.returncode]
        guard(execution.returncode == 0, "PR_D_REAL_PG_ROLLBACK_HARNESS_FAIL")
        guard(all(report["assertions"].values()), "PR_D_SQL_ASSERTIONS_MISSING")
        guard(rb.returncode == 0 and rb.stdout.strip() == "RESTORED",
              "PR_D_INDEPENDENT_TABLE_READBACK_FAIL")
        guard(rows.returncode == 0 and len(rows.stdout.splitlines()) == 1 and
              '"niubiz-generico@lf-ficticio.invalid"' in rows.stdout and
              '"FICTICIO"' in rows.stdout, "PR_D_INDEPENDENT_SOURCE_ROW_FAIL")
        report["status"] = "PASS"
    except subprocess.TimeoutExpired:
        report["blocking_error"] = "PR_D_PG_TIMEOUT"
    except Exception as exc:
        report["blocking_error"] = str(exc)[:600]
    finally:
        report["recorded_at_utc"] = datetime.now(timezone.utc).isoformat()
        (OUTPUT / "report.json").write_text(
            json.dumps(report, sort_keys=True, indent=2) + "\n")
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
