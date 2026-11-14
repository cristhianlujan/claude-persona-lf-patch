#!/usr/bin/env python3
"""Exact Step40 contract migration tested in disposable PG17.6 and PG18.7.

The SQL is run under BEGIN ... ROLLBACK on a fixture constructed from the
actual live PG function preimage. Does NOT run against sandbox or production.
Transport timeout tests do not call the network or issue credentials.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261114153500_lf_step40_generic_skill_hook_failopen_readonly_v1.sql"
FIXTURE = Path(__file__).with_name("fixture_step40_live_bridge_preimage_pgdual.sql")
NATIVE = ROOT / "scripts/lf_profile_native_resume.py"
CALLER = ROOT / "supabase/functions/lf-profiles-governance-caller-v1/caller.ts"
OLD_REF = "public.lf_profile_execution_input_validate_v1 + programacion.fn_lf_profile_input_governance_resolve_v1"
NEW_REF = "public.lf_profile_execution_input_validate_v1"
PREIMAGE_MD5 = "1a6c6c81538f3c83286c581528e4c80d"
INVOKER_MD5 = "f6087f356ccd5ece078170c2ff414cd9"
TICKET_MD5 = "cafccb4e256f8bbb9530f2e1b2e611ca"

class RealPgRollback(unittest.TestCase):
    def run_postgres(self, image, expected_version_prefix):
        self.assertTrue(shutil.which("docker"), "NOT_TESTED_NO_DOCKER")
        name = "lf-step40-generic-" + uuid.uuid4().hex[:10]
        start = subprocess.run([
            "docker","run","-d","--rm","--name",name,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image
        ], capture_output=True, text=True, timeout=180)
        self.assertEqual(start.returncode,0, "PG_IMAGE_NOT_AVAILABLE:"+start.stderr[-400:])
        try:
            def psql(sql, expect_fail=None):
                r = subprocess.run([
                    "docker","exec","-i",name,"psql","-X","-v","ON_ERROR_STOP=1",
                    "-U","postgres","-d","postgres","-Atq"
                ],input=sql,text=True,capture_output=True,timeout=180)
                if expect_fail:
                    self.assertNotEqual(r.returncode,0,"WRONG_SUCCESS")
                    self.assertIn(expect_fail,r.stderr)
                else:
                    self.assertEqual(r.returncode,0,"SQL_FAILED:"+r.stderr[-3600:])
                return r.stdout.strip()
            for _ in range(80):
                check=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                    capture_output=True,timeout=8)
                if check.returncode==0:break
                time.sleep(1)
            else:self.fail("PG_READY_TIMEOUT")
            server=psql("SHOW server_version_num;")
            self.assertTrue(server.startswith(expected_version_prefix),"PG_VERSION_"+server)
            psql(FIXTURE.read_text("utf-8"))
            baseline_ref=psql("SELECT resolver_ref FROM public.lf_operation_step_contracts;")
            self.assertEqual(baseline_ref,OLD_REF)
            before=psql("SELECT md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure));")
            self.assertRegex(before,r"^[0-9a-f]{32}$")
            inv_before=psql("SELECT md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure));")
            self.assertRegex(inv_before,r"^[0-9a-f]{32}$")
            ticket_before=psql("SELECT md5(pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure));")
            self.assertRegex(ticket_before,r"^[0-9a-f]{32}$")
            forward=MIGRATION.read_text("utf-8")
            self.assertTrue(forward.startswith("-- LF Step40 generic skill hook"))
            self.assertTrue(forward.rstrip().endswith("COMMIT;"))
            self.assertEqual(forward.count("BEGIN;"),1)
            self.assertIn("\nCOMMIT;",forward)  # final top-level COMMIT; function bodies may contain it too
            inner=forward.replace("BEGIN;\n","",1).rsplit("\nCOMMIT;",1)[0]
            # Cross-major pg_get_functiondef deparsing may differ. Replace only
            # the test fixture source digest while retaining the exact live
            # preimage guard in the original deployed migration.
            self.assertIn(PREIMAGE_MD5,inner)
            if before!=PREIMAGE_MD5:
                inner=inner.replace(PREIMAGE_MD5,before)
            self.assertIn(INVOKER_MD5,inner)
            if inv_before!=INVOKER_MD5:
                inner=inner.replace(INVOKER_MD5,inv_before)
            self.assertIn(TICKET_MD5,inner)
            if ticket_before!=TICKET_MD5:
                inner=inner.replace(TICKET_MD5,ticket_before)
            tested=psql("BEGIN; SET LOCAL check_function_bodies=off;\n"+
                inner+"""
SELECT resolver_ref FROM public.lf_operation_step_contracts;
SELECT required_evidence_keys::text FROM public.lf_operation_step_contracts;
SELECT position('REVIEW_SKILL_SOURCE_POLICY_AND_RETRY_GOVERNED' IN
  pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure)) > 0;
ROLLBACK;
""")
            self.assertIn(NEW_REF,tested.splitlines())
            self.assertNotIn(OLD_REF,tested.splitlines())
            self.assertIn("t",tested.splitlines())
            self.assertIn("scope_authority_packet_sha256",tested)
            self.assertEqual(psql("SELECT resolver_ref FROM public.lf_operation_step_contracts;"),OLD_REF)
            self.assertEqual(psql("SELECT md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure));"),before)
            self.assertEqual(psql("SELECT md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure));"),inv_before)
            self.assertEqual(psql("SELECT md5(pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure));"),ticket_before)
            # The negative drift case must be rejected. Still rolled back.
            psql("BEGIN; UPDATE public.lf_operation_step_contracts SET resolver_ref='FORGED' WHERE step_order=40;\n"+inner+"\nROLLBACK;",expect_fail="LF_STEP40_CONTRACT_SOURCE_DRIFT")
            self.assertEqual(psql("SELECT resolver_ref FROM public.lf_operation_step_contracts;"),OLD_REF)
            print(f"PASS_STEP40_ROLLBACK_{image.replace(':','_')} server={server} exact_source={before==PREIMAGE_MD5}",flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=45)

    def test_pg176_rollback(self):
        self.run_postgres("postgres:17.6","170006")

    def test_pg187_rollback(self):
        self.run_postgres("postgres:18.7","180007")

class BoundedSkillTransport(unittest.TestCase):
    def test_native_timeout_is_a_finding_and_nonruntime_stays_fail_closed(self):
        with patch.dict(os.environ,{"LF_PROFILE_EDGE_URL":"https://mock.invalid/functions/v1/caller"}):
            spec=importlib.util.spec_from_file_location("native_resume_step40",NATIVE)
            mod=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
        with patch.object(mod.urllib.request,"urlopen",side_effect=TimeoutError("synthetic timeout")):
            code,response=mod.call_json("https://mock.invalid",{"action":"profile_skill_runtime_v1"},timeout_seconds=18)
            self.assertEqual(code,0)
            self.assertEqual(response["code"],"SKILL_RUNTIME_NETWORK_OR_DEADLINE")
            self.assertFalse(response["production_authorized"])
            with self.assertRaises(TimeoutError):
                mod.call_json("https://mock.invalid",{"action":"profile_native_continue_v1"})
        self.assertIn("timeout_seconds=18",NATIVE.read_text("utf-8"))
    def test_bounded_edge_and_sql_hook_keep_readonly(self):
        ts=CALLER.read_text("utf-8")
        self.assertIn("Math.min(config.recurationTimeoutMs, 12_000)",ts)
        self.assertIn("SKILL_RUNTIME_BOUNDED_FAILURE_AS_FINDING",ts)
        sql=MIGRATION.read_text("utf-8")
        self.assertIn("lf_profile_execution_plan_v1",sql)
        self.assertIn("lf_profile_skill_invoke_selected_v1",sql)
        self.assertIn("SKILL_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED",sql)
        self.assertIn("TICKET_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED",sql)
        self.assertIn("SKILL_OPTIONAL_SEMANTIC_DECISION_DEFERRED",sql)
        self.assertIn("DETERMINISTIC_POLICY",sql)
        self.assertIn("v_skill_plan:=jsonb_build_object('status','READY','skills','[]'::jsonb)",sql)
        self.assertIn("'continuation_allowed',true",sql)
        self.assertIn("'status','BLOCKED'",sql)
        self.assertNotIn("DELETE FROM public.lf_operation_execution",sql)
        self.assertNotIn("UPDATE lf_ops.reglas",sql)
        self.assertNotIn("DISABLE TRIGGER",sql.upper())
        self.assertIn("ACTIONS_ID_TOKEN_REQUEST_URL",NATIVE.read_text("utf-8"))

if __name__=="__main__":
    unittest.main()
