"""PG17.6/PG18.7 isolated forward-only retirement tests, transaction rolled back.
Synthetic PG fixtures ONLY. No Supabase writes, approvals, profile runs, or production.
"""
import re
import shutil
import subprocess
import sys
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/edge_function_operation"))
from test_lf_ig0815_auto_score_promotion_pgdual_v1 import (
    SCHEMA, SOURCE, MIGRATION as IG0815_MIGRATION
)

CHAT_SOURCE = ROOT / "supabase/migrations/20261117000100_lf_owner_chat_verified_receipt_guard_v1.sql"
RETIRE = ROOT / "supabase/migrations/20261118034000_lf_owner_chat_full_retirement_v1.sql"
TRANSITION = ROOT / "supabase/migrations/20261105060000_lf_profile_runtime_transition_route_v1.sql"

# Fictitious UUID, not an assertion of human identity or an actual order.
OWNER_SUB = "00000000-0000-4000-8000-000000000001"
SETUP = r"""
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA private;
CREATE SCHEMA programacion;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE FUNCTION programacion.fn_v09_canonical_jsonb_text(j jsonb)
 RETURNS text LANGUAGE SQL IMMUTABLE STRICT AS $$ SELECT j::text $$;
CREATE FUNCTION programacion.fn_v09_sha256_jsonb(j jsonb)
 RETURNS text LANGUAGE SQL IMMUTABLE STRICT AS $$
 SELECT encode(extensions.digest(convert_to(programacion.fn_v09_canonical_jsonb_text(j),'UTF8'),'sha256'),'hex') $$;
CREATE TABLE public.lf_ig_project_owner_v2(
 project_code text PRIMARY KEY, owner_sub uuid NOT NULL, owner_name text NOT NULL,
 identity_mode text NOT NULL DEFAULT 'UNVERIFIED_CHAT_DECLARATION'
 CHECK (identity_mode='UNVERIFIED_CHAT_DECLARATION'));
INSERT INTO public.lf_ig_project_owner_v2(project_code,owner_sub,owner_name)
 VALUES('LF','00000000-0000-4000-8000-000000000001'::uuid,'Fixture Owner');
CREATE TABLE public.lf_activos(
  tipo_activo text, codigo_activo text, archived_at timestamptz,
  estado_original text, estado_documental text, estado_operativo text,
  nivel_control text, runtime_estado text, impacto_automatico text);
CREATE TABLE public.cat_estado_normalizacion_lf(
  estado_original text, estado_documental text, estado_operativo text,
  nivel_control text, runtime_estado text, impacto_automatico text);
CREATE TABLE public.lf_profile_runtime_transition_receipt_v1 (
  receipt_id bigint generated always as identity primary key,
  profile_code text not null, from_state jsonb not null, to_state jsonb not null,
  from_state_sha256 text not null, owner_authorization jsonb not null,
  requested_by text not null, request_ref text not null,
  created_at timestamptz not null default now(),
  constraint lf_profile_runtime_transition_receipt_one_shot
    unique(profile_code, from_state_sha256));
"""


def strip_transaction(sql):
    sql, n = re.subn(r"(?m)^BEGIN;\s*$", "", sql, count=1)
    assert n == 1, "EXPECTED_BEGIN"
    sql, n = re.subn(r"(?m)^COMMIT;\s*$", "", sql, count=1)
    assert n == 1, "EXPECTED_COMMIT"
    return sql


def transition_function():
    sql = TRANSITION.read_text(encoding="utf-8")
    start = sql.index("create or replace function public.lf_profile_runtime_transition_v1(")
    end = sql.index("revoke all on function public.lf_profile_runtime_transition_v1(", start)
    return sql[start:end]


ASSERTIONS = r"""
DO $verify_retirement$
BEGIN
  IF to_regclass('private.lf_owner_chat_orders_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_identity_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_action_catalog_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_promotion_leases_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_authorized_accounts_v1') IS NOT NULL
     OR to_regprocedure('private.fn_lf_owner_chat_owner_sub_v1()') IS NOT NULL
     OR to_regprocedure('private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text)') IS NOT NULL
  THEN RAISE EXCEPTION 'PG_RETIRE_OWNER_CHAT_OBJECT_REMAINS'; END IF;
  IF to_regclass('private.lf_ig_parameters_v1') IS NULL
     OR (SELECT count(*) FROM private.lf_ig_parameters_v1
          WHERE parameter_namespace='OWNER_CHAT')<>0
  THEN RAISE EXCEPTION 'PG_RETIRE_PARAMETER_TABLE_OR_ROWS_MISMATCH'; END IF;
  IF md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
     <>'98f1be74469c91d577e5eca66b81cba5'
  THEN RAISE EXCEPTION 'PG_RETIRE_DECIDE_NOT_PRE_4063'; END IF;
  IF md5(pg_get_functiondef('public.lf_profile_runtime_transition_v1(jsonb)'::regprocedure))
     <>'121fe8be9a5464695547dd889b8b7c9d'
  THEN RAISE EXCEPTION 'PG_RETIRE_TRANSITION_NOT_PRE_4063'; END IF;
END;
$verify_retirement$;
INSERT INTO private.lf_ig_parameters_v1
  (parameter_namespace,parameter_code,channel_code,value_kind,value_jsonb,activo)
VALUES ('INPUT_GOVERNANCE','FIXTURE_SETTING','', 'JSONB','{"fixture":true}'::jsonb,false);
DO $negative$
BEGIN
  BEGIN
    INSERT INTO private.lf_ig_parameters_v1
      (parameter_namespace,parameter_code,channel_code,value_kind,value_sha256,activo)
    VALUES ('OWNER_CHAT','SESSION_EMAIL_SHA256','CHAT_GPT_SESSION','SHA256',repeat('f',64),true);
    RAISE EXCEPTION 'PG_RETIRE_OWNER_CHAT_INSERT_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$negative$;
SELECT 'PASS_LF_OWNER_CHAT_RETIRED_BEFORE_ROLLBACK';
"""


class PgDualRetirement(unittest.TestCase):
    def test_pg17_pg18_retirement_begin_rollback(self):
        self.assertTrue(shutil.which("docker"), "DOCKER_REQUIRED_FOR_REAL_PG17_PG18")
        setup = (SCHEMA + "\n" + SOURCE.read_text(encoding="utf-8")
                 + "\n" + IG0815_MIGRATION.read_text(encoding="utf-8")
                 + "\n" + SETUP + "\n" + transition_function())
        chat = strip_transaction(CHAT_SOURCE.read_text(encoding="utf-8"))
        retire = strip_transaction(RETIRE.read_text(encoding="utf-8"))
        for version in ("17.6", "18.7"):
            with self.subTest(pg=version):
                name = "lf-owner-retire-" + uuid.uuid4().hex[:10]
                created = subprocess.run(
                    ["docker","run","-d","--rm","--name",name,
                     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(created.returncode,0,created.stderr)
                try:
                    for _ in range(90):
                        ready = subprocess.run(
                            ["docker","exec",name,"pg_isready","-U","postgres"],
                            capture_output=True,text=True,timeout=15)
                        if ready.returncode == 0:
                            logs = subprocess.run(
                                ["docker","logs",name],capture_output=True,text=True,timeout=15)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(0.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")

                    def psql(sql):
                        out = subprocess.run(
                            ["docker","exec","-i",name,"psql","-X","-v","ON_ERROR_STOP=1",
                             "-U","postgres","-d","postgres"],
                            input=sql,capture_output=True,text=True,timeout=240)
                        self.assertEqual(out.returncode,0,
                            "POSTGRES_"+version+"\n"+out.stderr[-10000:]+"\n"+out.stdout[-4000:])
                        return out.stdout+"\n"+out.stderr

                    psql(setup)
                    result = psql("BEGIN;\n"+chat+"\n"+retire+"\n"+ASSERTIONS+
                       "\nROLLBACK;\n"
                       "SELECT CASE WHEN to_regclass('private.lf_owner_chat_identity_v1') IS NULL "
                       "AND md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure)) "
                       "='98f1be74469c91d577e5eca66b81cba5' "
                       "THEN 'PASS_LF_TEARDOWN_ROLLBACK_CLEAN' ELSE 'FAIL_ROLLBACK' END;\n")
                    self.assertIn("PASS_LF_OWNER_CHAT_RETIRED_BEFORE_ROLLBACK",result)
                    self.assertIn("PASS_LF_TEARDOWN_ROLLBACK_CLEAN",result)
                    print("PASS_LF_OWNER_CHAT_RETIRE_PG"+version+"_BEGIN_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)


if __name__ == "__main__":
    unittest.main()
