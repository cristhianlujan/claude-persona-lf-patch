#!/usr/bin/env python3
"""PR-C real PostgreSQL 17 rollback in ephemeral CI service, NEVER remote Supabase."""
from __future__ import annotations
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci" / "pr_c_payment_provider_config"
MIGRATION_GLOB = "*_lf_payment_provider_config_niubiz_generic_v1.sql"
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_c_payment_provider_config_rollback.sql"
MARKERS = (
    "PR_C_EMPTY_PREIMAGE_PASS",
    "PR_C_DUPLICATE_REJECTED_PASS",
    "PR_C_STATUS_ENUM_REJECTED_PASS",
    "PR_C_IN_TRANSACTION_PASS columns=6 rls=ON forced=ON policies=0 roles_denied=2 row=1 status=FICTICIO",
    "PR_C_REAL_POST_ROLLBACK_PASS table_absent=true",
)


def guard(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def psql(extra: list[str]) -> subprocess.CompletedProcess:
    args = ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
            "-p", "5432", "-U", "postgres", "-d", "postgres", *extra]
    return subprocess.run(args, env=os.environ.copy(), capture_output=True,
                          text=True, timeout=100, check=False)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    report: dict = {"status": "FAIL", "engine": "REAL_POSTGRESQL_17",
                    "target": "EPHEMERAL_CI_SERVICE_ONLY", "remote_supabase_tested": False,
                    "persistent_changes_authorized": False}
    try:
        guard(os.environ.get("GITHUB_EVENT_NAME") == "pull_request",
              "PR_ONLY_NO_TRUSTED_DB")
        guard(os.environ.get("GITHUB_REPOSITORY") ==
              "cristhianlujan/claude-persona-lf-patch", "REPO_MISMATCH")
        exact_head = os.environ.get("PR_C_EXACT_HEAD")
        observed = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                                           text=True).strip()
        guard(bool(exact_head) and observed == exact_head, "PR_C_EXACT_HEAD_DRIFT")
        report["candidate_head"] = exact_head
        guard(os.environ.get("PGHOST") == "127.0.0.1", "REMOTE_HOST_FORBIDDEN")
        guard(os.environ.get("PGUSER") == "postgres", "ROLE_MISMATCH")
        guard(os.environ.get("PGDATABASE") == "postgres", "DB_MISMATCH")
        guard(os.environ.get("PGPASSWORD") == "pr_c_ephemeral_pg17_only",
              "PG_EPHEMERAL_CREDENTIAL_MISMATCH")
        candidates = list((ROOT / "supabase/migrations").glob(MIGRATION_GLOB))
        guard(len(candidates) == 1, "MIGRATION_NOT_UNIQUE")
        source = candidates[0].read_bytes()
        harness = HARNESS.read_bytes()
        text = source.decode("utf-8")
        guard(text.count("CREATE TABLE public.payment_provider_config") == 1,
              "TABLE_SCOPE_DRIFT")
        guard(text.count("INSERT INTO public.payment_provider_config") == 1,
              "ROW_SCOPE_DRIFT")
        guard(not any(re.match(r"(?i)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;", line)
                      for line in text.splitlines()), "NESTED_TX_FORBIDDEN")
        guard(not any(line.lstrip().startswith("\\") for line in text.splitlines()),
              "MIGRATION_PSQL_META_FORBIDDEN")
        target = harness.decode("utf-8")
        guard(target.count("@@MIGRATION_SQL@@") == 1, "HARNESS_MARKER_DRIFT")
        sql = target.replace("@@MIGRATION_SQL@@", text)
        guard(sql.splitlines().count("BEGIN;") == 1 and
              sql.splitlines().count("ROLLBACK;") == 1 and
              sql.splitlines().count("COMMIT;") == 0,
              "BEGIN_ROLLBACK_CONTROL_DRIFT")
        path = OUT / "single_session_begin_rollback.sql"
        path.write_text(sql)
        report["source"] = {"migration": candidates[0].name,
                            "migration_sha256": sha256(source),
                            "harness_sha256": sha256(harness),
                            "assembled_sql_sha256": sha256(sql.encode())}
        # Only ephemeral local role definitions; no source database mutations.
        role_fixture = psql(["-c", "CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;"])
        guard(role_fixture.returncode == 0, "EPHEMERAL_ROLE_SETUP_FAILED:" +
              role_fixture.stderr[:500])
        execution = psql(["-f", str(path)])
        output = execution.stdout + execution.stderr
        (OUT / "postgresql.log").write_text(output)
        report["executed"] = True
        report["sql_exit_code"] = execution.returncode
        report["sql_log_sha256"] = sha256(output.encode())
        report["assertions"] = {key: key in output for key in MARKERS}
        readback = psql(["-At", "-c", (
            "SELECT CASE WHEN to_regclass('public.payment_provider_config') "
            "IS NULL THEN 'ABSENT' ELSE 'PRESENT' END"
        )])
        report["independent_readback"] = readback.stdout.strip()
        report["independent_exit_code"] = readback.returncode
        report["independent_readback_sha256"] = sha256(
            (readback.stdout + readback.stderr).encode())
        guard(execution.returncode == 0, "POSTGRESQL_ROLLBACK_HARNESS_FAIL")
        guard(all(report["assertions"].values()), "POSTGRESQL_ASSERTIONS_MISSING")
        guard(readback.returncode == 0 and readback.stdout.strip() == "ABSENT",
              "POSTGRESQL_INDEPENDENT_READBACK_FAIL")
        report["status"] = "PASS"
    except subprocess.TimeoutExpired:
        report["blocking_error"] = "POSTGRES_TIMEOUT"
    except Exception as exc:
        report["blocking_error"] = str(exc)[:600]
    finally:
        report["recorded_at_utc"] = datetime.now(timezone.utc).isoformat()
        (OUT / "report.json").write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
