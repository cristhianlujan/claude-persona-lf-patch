#!/usr/bin/env python3
"""Compile EXACT candidate PL/pgSQL bodies in ephemeral PG17, no LF apply."""
import os
from pathlib import Path
import re
import subprocess

root=Path(__file__).resolve().parents[3]
sources=list((root/"supabase/migrations").glob("*_lf_operational_executor_lane_v1.sql"))
assert len(sources)==1, "BLOCK_MIGRATION_CARDINALITY"
source=sources[0].read_text(encoding="utf-8")
names=(
  ("close_operational_execution","close"),
  ("operational_executor_begin","begin"),
  ("operational_executor_finish","finish"),
  ("operational_executor_assert_principal","principal"),
  ("operational_executor_admit","admit"),
  ("operational_executor_assert_decision_current","decision_current"),
)
definitions=[]
for suffix,tag in names:
    name="lf_"+suffix+"_v1"
    expr=(r"(?ms)^CREATE OR REPLACE FUNCTION public\."+re.escape(name)+
          r"\(.*?^END \$"+tag+r"\$;")
    matches=re.findall(expr,source)
    assert len(matches)==1, "BLOCK_FUNCTION_BODY_CARDINALITY:"+name
    body=matches[0]
    assert body.count("$"+tag+"$")==2, "BLOCK_UNBALANCED_BODY:"+name
    assert "COMMIT;" not in body and "DO $role$" not in body, "BLOCK_SQL_IN_BODY:"+name
    definitions.append(body)

env=dict(os.environ)
for key,value in (("PGHOST","localhost"),("PGPORT","5432"),
                  ("PGUSER","postgres"),("PGDATABASE","postgres")):
    env.setdefault(key,value)
assert env.get("PGPASSWORD"), "BLOCK_EPHEMERAL_PG_PASSWORD_MISSING"

def psql(statements: str, expected_ok: bool) -> None:
    run=subprocess.run(
        ["psql","-X","-v","ON_ERROR_STOP=1","--no-psqlrc","-tA"],
        input=statements,text=True,capture_output=True,env=env,timeout=45,
        check=False
    )
    if (run.returncode==0) != expected_ok:
        raise AssertionError(
            "POSTGRES_PLPGSQL_COMPILE_UNEXPECTED:"+str(run.returncode)+"\n"+
            "STDOUT:"+run.stdout[-800:]+"\nSTDERR:"+run.stderr[-1900:]
        )

setup="""
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE IF NOT EXISTS public.lf_operation_execution (
 execution_id text, operation_code text, target_type text, target_code text,
 status text, lease_owner text, lease_fence bigint, lease_expires_at timestamptz,
 manifest jsonb, request_sha256 text, created_by_execution_id text,
 updated_by_execution_id text, updated_at timestamptz, completed_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.lf_operation_effect_guard(
 execution_id text, effect_scope text, state text, receipt jsonb,
 dispatch_key text, effect_request_sha256 text
);
SET check_function_bodies=on;
"""
psql(setup+"\n\n"+"\n\n".join(definitions)+"\n",expected_ok=True)
clean=definitions[4]  # admission body; sixth definition is the currentness guard
broken=clean.replace(
    "PERFORM public.lf_operational_executor_assert_principal_v1",
    "IF THEN\n  PERFORM public.lf_operational_executor_assert_principal_v1",1
)
assert broken!=clean, "BLOCK_MUTATION_FIXTURE_NOT_INSERTED"
psql("SET check_function_bodies=on;\n"+broken+"\n",expected_ok=False)
print("PASS_REAL_POSTGRES17_PLPGSQL_COMPILATION function_bodies=6 "
      "corrupted_admission_rejected=true")
