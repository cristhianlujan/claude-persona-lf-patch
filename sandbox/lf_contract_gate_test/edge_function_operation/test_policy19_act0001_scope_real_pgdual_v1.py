#!/usr/bin/env python3
"""Scope #3820 tests: real preimage issuer/consumer and owner writer,
new ACT0001 policy19 scope, fixed rollback, Postgres 17.6 / 18.7.
Only disposable Docker. No Supabase calls, no real Train RUN mutations.
"""
import json, re, subprocess, time, unittest, uuid
from pathlib import Path
from test_ig_asset_owner_one_name_pg18 import ROOT, BASE, UPSTREAM, MIGRATION as OWNER_GUARD, quote

DELTA=ROOT/"supabase/migrations/20261113143800_lf_policy19_act0001_scoped_writer_v1.sql"
ROLLBACK=ROOT/"audits/login-policy19-act0001/03_scope_rollback_exact_v1.sql"
CURRENT=Path(__file__).with_name("policy19_act0001_live_issuer_consumer_fixture_v1.sql")
PROVENANCE=ROOT/"audits/login-policy19-act0001/04_live_provenance_pg17_pg18_fixture.sql"
POLICY=ROOT/"audits/login-policy19-act0001/05_policy19_exact_row_pg17_pg18_fixture.sql"
REPO="cristhianlujan/claude-persona-lf-patch"
OWNER="EXEC-DB-TRAIN-LAB-OWNER-SCOPE-001"
POLICY_RUN="EXEC-DB-TRAIN-LAB-POLICY19-001"

class _ScopeLab:
    @classmethod
    def sql(cls, sql, error=None, timeout=300):
        result=None
        for i in range(20):
            result=subprocess.run(["docker","exec","-i",cls.container,"psql",
               "-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
               input=sql,text=True,capture_output=True,timeout=timeout)
            if (result.returncode and "connection to server on socket" in result.stderr
                and "No such file or directory" in result.stderr and i<19):
                time.sleep(1)
                continue
            break
        if error:
            found=re.search(r"ERROR:\s*([A-Z][A-Z0-9_]+)",result.stderr)
            if result.returncode==0 or not found or found.group(1)!=error:
                raise AssertionError("NEGATIVE_ERROR_MISMATCH "+error+" vs "
                   +str(found.group(1) if found else None)+" "+result.stderr[-1100:])
            return result.stderr
        if result.returncode:
            raise AssertionError("SCOPE_PG_SQL_FAILURE "+result.stderr[-1700:]+" SQL "+sql[:400])
        return result.stdout.strip()

    @classmethod
    def add_train(cls,exec_id,code,pr,actor="LF_GOVERNANCE"):
        path="supabase/migrations/"+code+".sql"
        manifest={
            "producer":"lf-migration-merge-train","head_sha":"a"*40,
            "train_run_id":"43379990001","pr":str(pr),
            "router_authority_receipt":{
              "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
              "router":"ACT-0001","operation_code":"ACTUALIZACION_DB_LF",
              "action_code":"UPDATE","target_repo":REPO,"target_code":code,
              "target_path":path,"scope_attested":False,"route_eligibility_only":True},
            "proposer_actor":actor}
        cls.sql("INSERT INTO public.lf_operation_execution("
            "execution_id,operation_code,target_type,target_code,target_repo,target_path,"
            "status,request_sha256,manifest,idempotency_key,created_by_execution_id) VALUES("
            +quote(exec_id)+",'ACTUALIZACION_DB_LF','MIGRATION',"
            +quote(code)+","+quote(REPO)+","+quote(path)+",'IN_PROGRESS',"
            +quote("f"*64)+","+quote(json.dumps(manifest,ensure_ascii=False))+"::jsonb,"
            +quote("train:"+code[:14]+":"+manifest["head_sha"])+","
            +quote("LF-MIGRATION-TRAIN-RUN-"+manifest["train_run_id"])+");")

    @classmethod
    def setUpClass(cls):
        cls.container="lf-policy19-scope-"+uuid.uuid4().hex[:10]
        image=cls.IMAGE
        p=subprocess.run(["docker","run","-d","--rm","--name",cls.container,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            capture_output=True,text=True,timeout=220)
        if p.returncode: raise AssertionError("DOCKER_UNAVAILABLE "+p.stderr[-800:])
        try:
            for _ in range(70):
                r=subprocess.run(["docker","exec",cls.container,"pg_isready","-U","postgres"],
                     capture_output=True,timeout=10)
                if r.returncode==0:break
                time.sleep(1)
            else:raise AssertionError("POSTGRES_STARTUP_FAILED")
            if cls.sql("SHOW server_version_num;")!=cls.VERSION:raise AssertionError("WRONG_PG_ENGINE")
            cls.sql(BASE.read_text(encoding="utf-8"),timeout=420)
            # exact upstream #3803 synthetic Train fixture needed to seed canonical catalog
            code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            cls.add_train("EXEC-DB-TRAIN-PR3803-20261113030000-R43379990001",code,3803)
            cls.sql(UPSTREAM.read_text(encoding="utf-8"),timeout=420)
            cls.sql(OWNER_GUARD.read_text(encoding="utf-8"),timeout=420)
            cls.sql(CURRENT.read_text(encoding="utf-8"),timeout=420)
            if cls.sql("SELECT md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure));")!="c9fba71dba3f2d5f7f16a40f22d15d6d":
                raise AssertionError("LIVE_ROUTER_BIND_MD5_MISMATCH")
            if cls.sql("SELECT md5(pg_get_functiondef('public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure));")!="29cd88f920e2b9f6dbd7b5e11af3fdb5":
                raise AssertionError("LIVE_ROUTER_CONSUMER_MD5_MISMATCH")
            cls.sql(POLICY.read_text(encoding="utf-8"))
            cls.sql(PROVENANCE.read_text(encoding="utf-8"))
            cls.add_train("EXEC-DB-TRAIN-LAB-SCOPE-001",
                "20261113143800_lf_policy19_act0001_scoped_writer_v1",3820)
            cls.sql(DELTA.read_text(encoding="utf-8"),timeout=300)
            cls.add_train(OWNER,
                "20261113071927_lf_asset_owner_one_name_backfill_v1",3806)
            cls.add_train(POLICY_RUN,
                "20261113130100_lf_b2b_policy19_otp_brevo_profiles12_v1",3819)
            assert cls.sql("SELECT count(*) FROM public.lf_router_scope_policy_v1;")=="2"
            print("PASS_POLICY19_SCOPE_REAL_MIGRATION_APPLIED_"+image+"_version="+cls.VERSION,flush=True)
        except BaseException:
            subprocess.run(["docker","rm","-f",cls.container],capture_output=True,timeout=60)
            raise

    @classmethod
    def tearDownClass(cls):
        if getattr(cls,"container",None):
            subprocess.run(["docker","rm","-f",cls.container],
                capture_output=True,timeout=60)

    def test_01_policy19_positive_receipt_rollback(self):
        sql=("BEGIN; SET LOCAL ROLE service_role;"
             +"SELECT public.lf_router_scope_bind_v1("+quote(POLICY_RUN)+")::text;"
             +"SELECT public.lf_router_scope_receipt_consume_v2("+quote(POLICY_RUN)
             +",'description')::text; ROLLBACK;")
        lines=[x for x in self.sql(sql).splitlines() if x.startswith("{")]
        self.assertEqual(len(lines),2,lines)
        issued,verified=map(json.loads,lines)
        self.assertEqual(issued["status"],"SCOPE_ATTESTED_ROUTE_ONLY")
        self.assertEqual(verified["status"],"SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY")
        self.assertEqual(issued["receipt_sha256"],verified["receipt_sha256"])
        self.assertEqual(issued["positive_scope"][0]["row_id"],19)
        self.assertEqual(len(issued["positive_scope"][0]["policy_config_keys"]),8)
        self.assertFalse(issued["effect_authority"])
        self.assertFalse(verified["downstream_execution_allowed"])
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
           "WHERE execution_id="+quote(POLICY_RUN)+";"),"0")
        print("PASS_POLICY19_SCOPE_REAL_ISSUER_CONSUMER_SHA_POSITIVE_NEGATIVE_ROLLBACK_"+self.IMAGE,flush=True)

    def test_02_policy19_wrong_column_denied(self):
        self.sql("BEGIN; SET LOCAL ROLE service_role; SELECT public.lf_router_scope_bind_v1("
            +quote(POLICY_RUN)+"); SELECT public.lf_router_scope_receipt_consume_v2("
            +quote(POLICY_RUN)+",'status'); ROLLBACK;",
            error="LF_POLICY19_SCOPE_BUSINESS_COLUMN_FORBIDDEN")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
            "WHERE execution_id="+quote(POLICY_RUN)+";"),"0")
        print("PASS_POLICY19_SCOPE_WRONG_COLUMN_DENIED_ZERO_RECEIPTS_"+self.IMAGE,flush=True)

    def test_03_policy19_forged_origin_denied(self):
        self.sql("BEGIN; UPDATE public.lf_operation_execution SET manifest=jsonb_set("
            "manifest,'{router_authority_receipt,router}','\"FAKE\"'::jsonb) WHERE execution_id="
            +quote(POLICY_RUN)+"; SET LOCAL ROLE service_role;"
            "SELECT public.lf_router_scope_bind_v1("+quote(POLICY_RUN)+"); ROLLBACK;",
            error="LF_POLICY19_SCOPE_ROUTER_ORIGIN_NOT_GOVERNED")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
            "WHERE execution_id="+quote(POLICY_RUN)+";"),"0")
        print("PASS_POLICY19_SCOPE_FORGED_ORIGIN_DENIED_ZERO_RECEIPTS_"+self.IMAGE,flush=True)

    def test_04_policy19_no_receipt_writer_fails(self):
        self.sql("BEGIN; SET LOCAL ROLE service_role;"
            "SELECT public.lf_ig_policy19_apply_v1("+quote(POLICY_RUN)
            +",'ANY','{}'::jsonb); ROLLBACK;",error="LF_POLICY19_SCOPE_RECEIPT_MISSING")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
           "WHERE execution_id="+quote(POLICY_RUN)+";"),"0")
        print("PASS_POLICY19_SCOPE_WRITER_MISSING_RECEIPT_DENIED_"+self.IMAGE,flush=True)

    def test_05_owners_issuer_consumer_regression(self):
        query=("BEGIN; SET LOCAL ROLE service_role;"
            "SELECT public.lf_router_scope_bind_v1("+quote(OWNER)+")::text;"
            "SELECT public.lf_router_scope_receipt_consume_v2("+quote(OWNER)
            +",'owner_name')::text; ROLLBACK;")
        lines=[x for x in self.sql(query).splitlines() if x.startswith("{")]
        self.assertEqual(len(lines),2,lines)
        issued,verified=map(json.loads,lines)
        self.assertEqual(issued["scope_code"],"LF_ACTIVOS_OWNER_NAME_WRITE_V1")
        self.assertEqual(verified["status"],"SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY")
        self.assertEqual(issued["receipt_sha256"],verified["receipt_sha256"])
        self.assertFalse(issued["effect_authority"])
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
           "WHERE execution_id="+quote(OWNER)+";"),"0")
        print("PASS_POLICY19_SCOPE_OWNER_NAME_ISSUER_CONSUMER_REGRESSION_"+self.IMAGE,flush=True)

    def test_06_live_rollback_restores_function_md5(self):
        # Undo only after all tests; unittest method names sort lexicographically.
        self.sql(ROLLBACK.read_text(encoding="utf-8"))
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_router_scope_policy_v1;"),"1")
        self.assertEqual(self.sql("SELECT md5(pg_get_functiondef("
            "'public.lf_router_scope_bind_v1(text)'::regprocedure));"),
            "c9fba71dba3f2d5f7f16a40f22d15d6d")
        self.assertEqual(self.sql("SELECT md5(pg_get_functiondef("
            "'public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure));"),
            "29cd88f920e2b9f6dbd7b5e11af3fdb5")
        print("PASS_POLICY19_SCOPE_EXACT_ROUTER_FUNCTION_ROLLBACK_"+self.IMAGE,flush=True)

class TestScopePG176(_ScopeLab,unittest.TestCase):
    IMAGE="postgres:17.6"; VERSION="170006"
class TestScopePG187(_ScopeLab,unittest.TestCase):
    IMAGE="postgres:18.7"; VERSION="180007"
