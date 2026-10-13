#!/usr/bin/env python3
"""Real PostgreSQL 16 security-definer principal test using disposable CI service.

This extracts the EXACT proposed function from the migration, with no rewritten
mock implementation. It does not apply the full LF migration or simulate Router.
The test is fail-closed and rolls back its role-membership negative scenario.
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCES = list((ROOT / "supabase" / "migrations").glob("*_lf_operational_executor_lane_v1.sql"))
assert len(SOURCES) == 1, "BLOCK_UNIQUE_MIGRATION_SOURCE_NOT_FOUND"
source = SOURCES[0].read_text(encoding="utf-8")
match = re.search(
    r"(?ms)^CREATE OR REPLACE FUNCTION public\.lf_operational_executor_assert_principal_v1\("
    r".*?^END \$principal\$;",
    source,
)
assert match is not None, "BLOCK_PRINCIPAL_FUNCTION_NOT_FOUND"
principal_sql = match.group(0)
assert principal_sql.count("SECURITY DEFINER") == 1, "BLOCK_SECURITY_DEFINER_NOT_EXACT"

env = dict(os.environ)
env.setdefault("PGHOST", "localhost")
env.setdefault("PGPORT", "5432")
env.setdefault("PGUSER", "postgres")
assert env.get("PGPASSWORD"), "BLOCK_EPHEMERAL_PG_PASSWORD_MISSING"


def psql(sql: str, *, expected_ok: bool = True) -> str:
    p = subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "--no-psqlrc", "-tA"],
        input=sql, text=True, capture_output=True, env=env, check=False, timeout=30
    )
    if (p.returncode == 0) != expected_ok:
        raise AssertionError(
            f"UNEXPECTED_POSTGRES_RESULT:{p.returncode}\n"
            f"STDOUT:{p.stdout[-1500:]}\nSTDERR:{p.stderr[-1600:]}"
        )
    return p.stdout


psql(String := """
CREATE ROLE lf_operational_admission_authority NOLOGIN NOINHERIT;
CREATE ROLE lf_operation_executor_runtime NOLOGIN NOINHERIT;
CREATE ROLE lf_op_sandbox_admit LOGIN NOINHERIT;
CREATE ROLE lf_op_sandbox_effect LOGIN NOINHERIT;
CREATE ROLE lf_op_sandbox_untrusted LOGIN NOINHERIT;
CREATE ROLE lf_op_sandbox_extra NOLOGIN;
GRANT lf_operational_admission_authority TO lf_op_sandbox_admit
  WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT lf_operation_executor_runtime TO lf_op_sandbox_effect
  WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
""" + principal_sql + """
REVOKE ALL ON FUNCTION public.lf_operational_executor_assert_principal_v1(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_operational_executor_assert_principal_v1(text)
  TO lf_operational_admission_authority, lf_operation_executor_runtime;
""")

# Real DB checks under separate database session principals.
def as_login(login: str, sql: str, *, activate_role: bool = True,
             expected_ok: bool = True) -> str:
    if login not in ("lf_op_sandbox_admit", "lf_op_sandbox_effect",
                     "lf_op_sandbox_untrusted"):
        raise ValueError("Unexpected test principal")
    return psql(
        "BEGIN;\n"
        + f"SET SESSION AUTHORIZATION {login};\n"
        + ((("SET LOCAL ROLE lf_operational_admission_authority;\n" if login == "lf_op_sandbox_admit"
             else "SET LOCAL ROLE lf_operation_executor_runtime;\n" if login == "lf_op_sandbox_effect"
             else "")) if activate_role else "")
        + sql
        + "\nRESET SESSION AUTHORIZATION;\n"
        + "ROLLBACK;\n",
        expected_ok=expected_ok
    )

def expected_block(role: str, code: str) -> str:
    return f"""
DO $negative$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    PERFORM public.lf_operational_executor_assert_principal_v1('{role}');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS DISTINCT FROM '{code}' THEN
      RAISE EXCEPTION 'WRONG_BLOCK_CODE_EXPECTED:{code}:GOT:%',SQLERRM;
    END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'UNAUTHORIZED_PRINCIPAL_ACCEPTED:{role}';
  END IF;
END $negative$;
"""

# Without an explicit role switch, the NOINHERIT login has no EXECUTE
# privilege. This negative assertion caught the original production-path bug.
as_login("lf_op_sandbox_effect",
         "SELECT public.lf_operational_executor_assert_principal_v1('lf_operation_executor_runtime');",
         activate_role=False, expected_ok=False)

# NOINHERIT must be paired with explicit SET ROLE on each operation
# session. The session_user remains the independent LOGIN principal.
as_login("lf_op_sandbox_effect",
         "SELECT public.lf_operational_executor_assert_principal_v1('lf_operation_executor_runtime');")
as_login("lf_op_sandbox_admit",
         "SELECT public.lf_operational_executor_assert_principal_v1('lf_operational_admission_authority');")
as_login("lf_op_sandbox_effect",
         expected_block("lf_operational_admission_authority",
                        "OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID"))
as_login("lf_op_sandbox_admit",
         expected_block("lf_operation_executor_runtime",
                        "OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID"))

# No EXECUTE grant should exist for any caller merely having PUBLIC access.
p = psql("""
SELECT count(*) FROM pg_proc f,
LATERAL aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) acl
WHERE f.oid='public.lf_operational_executor_assert_principal_v1(text)'::regprocedure
AND acl.grantee=0 AND acl.privilege_type='EXECUTE';
""")
assert p.strip().endswith("0"), "BLOCK_PUBLIC_EXECUTE_ON_GOVERNED_PRINCIPAL"

# A real rollback tests a negative privilege change without persisting it.
psql("""
BEGIN;
GRANT lf_op_sandbox_extra TO lf_op_sandbox_effect
  WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
COMMIT;
""")
as_login("lf_op_sandbox_effect",
         expected_block("lf_operation_executor_runtime",
                        "OPERATIONAL_PRINCIPAL_EXTRA_ROLE_MEMBERSHIP_FORBIDDEN"))
psql("""
BEGIN;
REVOKE lf_op_sandbox_extra FROM lf_op_sandbox_effect;
ROLLBACK;
""")
as_login("lf_op_sandbox_effect",
         expected_block("lf_operation_executor_runtime",
                        "OPERATIONAL_PRINCIPAL_EXTRA_ROLE_MEMBERSHIP_FORBIDDEN"))
psql("REVOKE lf_op_sandbox_extra FROM lf_op_sandbox_effect;")
as_login("lf_op_sandbox_effect",
         "SELECT public.lf_operational_executor_assert_principal_v1('lf_operation_executor_runtime');")

print("PASS_REAL_POSTGRES16_PRINCIPAL_RBAC_NEGATIVES_AND_ROLLBACK "
      "separate_logins=2 denies=3 no_public_execute=true")
