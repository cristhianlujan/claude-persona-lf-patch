#!/usr/bin/env python3
"""Run the exact Train-versioned inactive skill-update bootstrap against isolated PG17.

The catalog, authority and Router action entries in this fixture are SYNTHETIC.
No Supabase credential, model call, Router invocation or product write is used.
"""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = sorted((ROOT / "supabase/migrations").glob("*_lf_skill_update_apply_inactive_bootstrap_v1.sql"))
PG_CONTAINER = os.environ.get("PG_CONTAINER", "")
EXPECTED_SKILL = "SKILL_UPDATE_APPLY"
EXPECTED_METHOD = "GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1"

FIXTURE = """
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
CREATE TABLE public.lf_operation_registry (
  operation_code text, applies_to_asset_type text, lifecycle_state_code text
);
CREATE TABLE public.lf_router_action_registry (
  asset_type text,action_code text,operation_code text,status text,write_allowed boolean
);
CREATE TABLE public.lf_profile_write_authority_v1 (
  profile_code text,operation_code text,status text
);
CREATE TABLE public.lf_skill_catalog_v1 (
 skill_code text PRIMARY KEY,description text NOT NULL,required_operation text NOT NULL,
 handler_fn text NOT NULL,effect text NOT NULL,input_required text[] NOT NULL,
 status text NOT NULL,opener_fn text,child_caller jsonb,
 CONSTRAINT status_valid CHECK(status IN ('DRAFT','READY','DISABLED'))
);
CREATE TABLE public.lf_router_governed_callers (
 caller_code text PRIMARY KEY,caller_method text UNIQUE,repository text NOT NULL,
 workflow_ref text NOT NULL,asset_type text NOT NULL,action_code text NOT NULL,
 operation_code text NOT NULL,literal_template text NOT NULL,status text NOT NULL,
 notes text,CONSTRAINT caller_status_valid CHECK(status IN ('ACTIVE','DISABLED'))
);
INSERT INTO public.lf_operation_registry VALUES
 ('ACTUALIZACION_SKILL_LF','SKILL','OP_OPERATIONAL');
INSERT INTO public.lf_router_action_registry VALUES
 ('SKILL','SKILL_UPDATE','ACTUALIZACION_SKILL_LF','ACTIVE',true);
INSERT INTO public.lf_profile_write_authority_v1 VALUES
 ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','ACTUALIZACION_SKILL_LF','ACTIVE');
"""

def run(sql, expected_failure=False):
    assert PG_CONTAINER, "PG_CONTAINER_REQUIRED"
    p = subprocess.run(
      ["docker", "exec", "-i", PG_CONTAINER, "psql", "-X", "-A", "-t", "-q",
       "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
      input=sql, text=True, capture_output=True, timeout=40
    )
    if expected_failure:
        assert p.returncode != 0, "NEGATIVE_EXPECTED_FAILURE"
        return p.stderr
    assert p.returncode == 0, p.stderr[-2500:]
    return p.stdout.strip()

def assert_pass(value, name):
    assert value, "FAIL_" + name
    print("PASS_" + name, flush=True)

def main():
    assert_pass(len(MIGRATIONS) == 1, "EXACTLY_ONE_TRAIN_VERSION")
    sql = MIGRATIONS[0].read_text(encoding="utf-8")
    assert_pass("CREATE OR REPLACE FUNCTION public.lf_router" not in sql,
                "ROUTER_IS_UNCHANGED")

    run(FIXTURE)
    run(sql)
    got = run(
      "SELECT skill_code || '|' || status || '|' || required_operation"
      " FROM public.lf_skill_catalog_v1;"
      " SELECT caller_method || '|' || status || '|' || operation_code"
      " FROM public.lf_router_governed_callers;"
    ).splitlines()
    assert_pass(len(got) == 2 and
                got[0] == EXPECTED_SKILL + "|DRAFT|ACTUALIZACION_SKILL_LF" and
                got[1] == EXPECTED_METHOD + "|DISABLED|ACTUALIZACION_SKILL_LF",
                "INACTIVE_BY_DEFAULT_READBACK")
    err=run(sql,expected_failure=True)
    assert_pass("LF_SKILL_UPDATE_BOOTSTRAP_IDENTITY_CONFLICT" in err,
                "REPLAY_IDENTITY_BLOCKS")
    assert_pass(run("SELECT count(*) FROM public.lf_skill_catalog_v1;") == "1",
                "REPLAY_NO_DUPLICATE")

    for mutation,expect,name in [
      ("DELETE FROM public.lf_profile_write_authority_v1;",
       "LF_SKILL_UPDATE_REPARADOR_OPERATION_NOT_AUTHORIZED","MISSING_AUTHORITY"),
      ("UPDATE public.lf_router_action_registry SET write_allowed=false;",
       "LF_SKILL_UPDATE_ROUTER_ACTION_NOT_EXACT","MISSING_ROUTE"),
      ("DELETE FROM public.lf_operation_registry;",
       "LF_SKILL_UPDATE_OPERATION_NOT_OPERATIONAL","MISSING_OPERATION"),
    ]:
        run(FIXTURE)
        run(mutation)
        err=run(sql,expected_failure=True)
        assert_pass(expect in err,name+"_BLOCKS")
        assert_pass(run("SELECT count(*) FROM public.lf_skill_catalog_v1;") == "0",
                    name+"_NO_EFFECT")
    print("PASS_ISOLATED_PG17_BOOTSTRAP: disabled only, production unchanged", flush=True)

if __name__ == "__main__":
    main()
