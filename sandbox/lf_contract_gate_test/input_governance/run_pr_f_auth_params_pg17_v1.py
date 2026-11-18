#!/usr/bin/env python3
"""PR-F: real ephemeral PostgreSQL 17 BEGIN/ROLLBACK, exact-head, no remote writes."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci" / "pr_f_global_auth"
ORIGIN = ROOT / "supabase/migrations/20261118064500_lf_global_config_consolidation_v1.sql"
TARGET_GLOB = "*_lf_global_auth_params_pr_f_v1.sql"
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_f_auth_params_rollback.sql"
MARKERS = (
    "PR_F_PREIMAGE_PASS global_rows=1 auth_rows=0 fixture_auth_rules=3",
    "PR_F_UNIQUE_REJECTED_PASS",
    "PR_F_BAD_STATUS_REJECTED_PASS",
    "PR_F_BAD_TYPE_REJECTED_PASS",
    "PR_F_IN_TRANSACTION_PASS auth_rows=9 real_by_key=1 rls=ON forced=ON policies=0 roles_denied=14 fixture_rules_unchanged=3",
    "PR_F_REAL_POST_ROLLBACK_PASS global_rows=1 auth_rows=0 fixture_rules=3 rls_unchanged=true",
)


def guard(ok, error):
    if not ok:
        raise RuntimeError(error)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def psql(*args):
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
         "-p", "5432", "-U", "postgres", "-d", "postgres", *args],
        capture_output=True, text=True, env=os.environ.copy(),
        check=False, timeout=120,
    )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {
        "status": "FAIL", "engine": "REAL_POSTGRESQL_17",
        "test_service": "EPHEMERAL_GITHUB_ACTIONS",
        "persistent_or_remote_supabase_tested": False,
        "policy_or_rule_writes_performed": False,
    }
    try:
        guard(os.environ.get("GITHUB_EVENT_NAME") == "pull_request", "PR_ONLY")
        guard(os.environ.get("GITHUB_REPOSITORY") ==
              "cristhianlujan/claude-persona-lf-patch", "REPO_MISMATCH")
        expected = os.environ.get("PR_F_EXACT_HEAD")
        head = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            text=True).strip()
        guard(bool(expected) and head == expected, "PR_F_EXACT_HEAD_DRIFT")
        report["candidate_head"] = head
        for key, val in (
            ("PGHOST", "127.0.0.1"), ("PGPORT", "5432"),
            ("PGUSER", "postgres"), ("PGDATABASE", "postgres"),
            ("PGPASSWORD", "pr_f_ephemeral_pg17_only")
        ):
            guard(os.environ.get(key) == val, "PR_F_LOCAL_POSTGRES_GUARD_" + key)
        matches = list((ROOT / "supabase/migrations").glob(TARGET_GLOB))
        guard(len(matches) == 1, "PR_F_MIGRATION_NOT_UNIQUE")
        origin = ORIGIN.read_text()
        target = matches[0].read_text()
        template = HARNESS.read_text()
        start = origin.find("CREATE TABLE public.lf_global_config (")
        end = origin.find("FROM PUBLIC, anon, authenticated;", start)
        guard(start >= 0 and end >= 0, "PR_F_SOURCE_BASELINE_DDL_MISSING")
        ddl = origin[start:end + len("FROM PUBLIC, anon, authenticated;")]
        guard(ddl.count("CREATE TABLE ") == 1 and
              ddl.count("ENABLE ROW LEVEL SECURITY") == 1 and
              ddl.count("FORCE ROW LEVEL SECURITY") == 1 and
              "DROP TABLE" not in ddl, "PR_F_FIXTURE_NOT_MINIMAL")
        guard(target.count("INSERT INTO public.lf_global_config") == 1,
              "PR_F_ONE_INSERT_REQUIRED")
        guard("UPDATE " not in target.upper() and
              "DELETE " not in target.upper() and
              "CREATE TABLE " not in target.upper() and
              "DROP TABLE " not in target.upper() and
              "ALTER TABLE " not in target.upper() and
              "CASCADE" not in target.upper(), "PR_F_DDL_DML_SCOPE_DRIFT")
        guard("lf_ops.reglas" not in target.lower() and
              "politicas_seguridad" not in target.lower(), "PR_F_RULE_POLICY_DRIFT")
        guard(not any(re.match(r"(?i)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;",ln)
                      for ln in target.splitlines()), "PR_F_MIGRATION_TRANSACTION_FORBIDDEN")
        guard(template.count("@@SOURCE_TABLE_DDL@@") == 1 and
              template.count("@@PR_F_MIGRATION_SQL@@") == 1,
              "PR_F_HARNESS_PLACEHOLDER_DRIFT")
        assembled = template.replace("@@SOURCE_TABLE_DDL@@", ddl).replace(
            "@@PR_F_MIGRATION_SQL@@", target)
        guard(assembled.splitlines().count("BEGIN;") == 1 and
              assembled.splitlines().count("ROLLBACK;") == 1 and
              assembled.splitlines().count("COMMIT;") == 0, "PR_F_NOT_REAL_ROLLBACK")
        report["sources"] = {
            "baseline_ddl_source": ORIGIN.name,
            "baseline_sha256": sha(origin.encode()),
            "migration": matches[0].name,
            "migration_sha256": sha(target.encode()),
            "harness_sha256": sha(template.encode()),
            "assembled_sql_sha256": sha(assembled.encode()),
        }
        script = OUT / "transaction.sql"
        script.write_text(assembled)
        run = psql("-f", str(script))
        logs = run.stdout + run.stderr
        (OUT / "postgresql.log").write_text(logs)
        report["sql_exit_code"] = run.returncode
        report["sql_log_sha256"] = sha(logs.encode())
        report["assertions"] = {m: m in logs for m in MARKERS}
        # Real independent PostgreSQL readback, executed in another connection.
        check = psql("-At", "-c",
            "SELECT CASE WHEN "
            "(SELECT count(*) FROM public.lf_global_config)=1 "
            "AND (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')=0 "
            "AND (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')=3 "
            "AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class "
            "WHERE oid='public.lf_global_config'::regclass) "
            "THEN 'RESTORED_1_0_3_RLS' ELSE 'DRIFT' END")
        report["independent_exit_code"] = check.returncode
        report["independent_readback"] = check.stdout.strip()
        guard(run.returncode == 0, "PR_F_PG_REAL_SQL_FAILED")
        guard(all(report["assertions"].values()), "PR_F_PG_ASSERTION_MARKER_MISSING")
        guard(check.returncode == 0 and
              check.stdout.strip() == "RESTORED_1_0_3_RLS",
              "PR_F_INDEPENDENT_AFTER_ROLLBACK_FAILED")
        report["status"] = "PASS"
    except subprocess.TimeoutExpired:
        report["blocking_error"] = "PR_F_POSTGRES_TIMEOUT"
    except Exception as err:
        report["blocking_error"] = str(err)[:650]
    finally:
        report["recorded_at_utc"] = datetime.now(timezone.utc).isoformat()
        (OUT / "report.json").write_text(
            json.dumps(report, sort_keys=True, indent=2) + "\n")
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
