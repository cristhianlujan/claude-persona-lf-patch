#!/usr/bin/env python3
"""L36 policy19 semantical compatibility — scoped dynamic SQL, real PG17.6/18.7.
Read-only-captured function source fixture; synthetic Train row; no Supabase writes.
"""
import json, pathlib, re, subprocess, time, unittest, uuid

ROOT=pathlib.Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261113173000_lf_policy19_semantic_factor_selection_compat_v1.sql"
UNDO=ROOT/"audits/login-policy19-semantic/01_rollback_guarded_v1.sql"
FIX=pathlib.Path(__file__).with_name("policy19_semantic_live_three_functions_fixture.sql")
ORIGINAL={
"fn_input_governance_semantic_probe_v3":"8e2fd437a0ab693ce02fb3d6afe95406",
"fn_input_governance_semantic_probe_v3_cached_v1":"f057bbe4e4fdf0c35d2bd73c1ccc5ac5",
"fn_input_governance_semantic_probe_v3_ctx":"58d3ae035dba9c380cbf14fc65edc710"}
TARGET="20261113173000_lf_policy19_semantic_factor_selection_compat_v1"
DECIDED={
"admin_minimum_strength":"APPROVED_MFA",
"admin_phishing_resistant_requirement":"NOT_REQUIRED_FOR_PROFILES_1_2_OWNER_RISK_ACCEPTED_PENDING_SIGNATURE",
"phishing_resistant_option_required":False,
"admin_primary_method":"USERNAME_PASSWORD_SERVER_VALIDATED",
"admin_identity_provider":"PENDING_ADR_003_M1_SPIKE",
"admin_sso_protocol":"PENDING_ADR_003_M1_SPIKE",
"admin_provider_configuration_status":"PENDING_REAL_IDP_AND_BREVO_INTEGRATION_QA",
"factor_selection_status":"OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION",
"admin_profile_ids":[1,2],"coverage_status":"ALL_HUMAN_PROFILES"}
REGEX=re.compile(r"\$factor_new\$(.*?)\$factor_new\$",re.DOTALL)

class Base:
    @classmethod
    def sql(cls,source,error=None):
        r=None
        for i in range(20):
            r=subprocess.run(["docker","exec","-i",cls.container,"psql",
                "-X","-q","-v","ON_ERROR_STOP=1","-A","-t",
                "-U","postgres","-d","postgres"],input=source,
                text=True,capture_output=True,timeout=240)
            if (r.returncode and "connection to server on socket" in r.stderr
                and "No such file or directory" in r.stderr and i<19):
                time.sleep(1)
                continue
            break
        if error:
            found=re.search(r"ERROR:\s*([A-Z][A-Z0-9_]+)",r.stderr)
            if r.returncode==0 or not found or found.group(1)!=error:
                raise AssertionError("SEMANTIC_NEGATIVE_ERROR_WRONG expected="+error
                  +" actual="+str(found.group(1) if found else None)+" "+r.stderr[-1200:])
            return r.stderr
        if r.returncode: raise AssertionError("SEMANTIC_SQL_FAILED "+r.stderr[-1900:])
        return r.stdout.strip()
    @classmethod
    def signature(cls,name):
        return "programacion."+name+("(integer,text,bigint)" if name=="fn_input_governance_semantic_probe_v3" else "(integer,text,bigint,jsonb)")
    @classmethod
    def md5(cls,name):
        return cls.sql("SELECT md5(pg_get_functiondef('"+cls.signature(name)+"'::regprocedure));")
    @classmethod
    def setUpClass(cls):
        cls.container="lf-semantic-policy19-"+uuid.uuid4().hex[:10]
        p=subprocess.run(["docker","run","-d","--rm","--name",cls.container,
         "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",cls.IMAGE],
         capture_output=True,text=True,timeout=220)
        if p.returncode:raise AssertionError("DOCKER_UNAVAILABLE "+p.stderr)
        try:
            for _ in range(70):
                ready=subprocess.run(["docker","exec",cls.container,"pg_isready",
                  "-U","postgres"],capture_output=True,timeout=10)
                if ready.returncode==0:break
                time.sleep(1)
            else:raise AssertionError("PG_READY_TIMEOUT")
            if cls.sql("SHOW server_version_num;")!=cls.VERSION:raise AssertionError("PG_VERSION_DRIFT")
            cls.sql("CREATE SCHEMA programacion; CREATE SCHEMA lf_ops;"
              "CREATE TABLE public.lf_operation_execution("
              "execution_id text,operation_code text,target_type text,status text,"
              "target_code text,target_repo text,target_path text,manifest jsonb);"
              "CREATE TABLE lf_ops.politicas_seguridad(security_policy_id bigint PRIMARY KEY,policy_config jsonb NOT NULL);"
              "INSERT INTO lf_ops.politicas_seguridad VALUES(19,'{}'::jsonb);"
              "INSERT INTO public.lf_operation_execution VALUES("
              "'EXEC-DB-TRAIN-SEMANTIC-LAB','ACTUALIZACION_DB_LF','MIGRATION',"
              "'IN_PROGRESS','"+TARGET+"','cristhianlujan/claude-persona-lf-patch',"
              "'supabase/migrations/"+TARGET+".sql',"
              "'{\"producer\":\"lf-migration-merge-train\","
              "\"router_authority_receipt\":{\"schema_version\":\"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1\"}}'::jsonb);")
            cls.sql(FIX.read_text(encoding="utf-8"))
            for name,sha in ORIGINAL.items():
                if cls.md5(name)!=sha:raise AssertionError("LIVE_SNAPSHOT_HASH_MISMATCH "+cls.IMAGE+" "+name+" "+cls.md5(name)+" vs "+sha)
            print("PASS_POLICY19_SEMANTIC_EXACT_LIVE_FUNCTION_PREIMAGE_"+cls.IMAGE,flush=True)
        except BaseException:
            subprocess.run(["docker","rm","-f",cls.container],capture_output=True,timeout=60)
            raise
    @classmethod
    def tearDownClass(cls):
        subprocess.run(["docker","rm","-f",cls.container],capture_output=True,timeout=60)
    @classmethod
    def migration_without_commit(cls):
        s=MIG.read_text(encoding="utf-8").rstrip()
        if not s.endswith("COMMIT;"):raise AssertionError("MIGRATION_TRANSACTION_END_DRIFT")
        return s[:-len("COMMIT;")]
    def test_01_ddl_pg_rollback_exact(self):
        names=list(ORIGINAL)
        reads="\n".join("SELECT md5(pg_get_functiondef('"+self.signature(n)+"'::regprocedure));" for n in names)
        lines=self.sql(self.migration_without_commit()+reads+"\nROLLBACK;\n"+reads).splitlines()
        self.assertEqual(len(lines),6,repr(lines))
        self.assertNotEqual(lines[:3],lines[3:],"DID_NOT_MODIFY_FUNCTIONS")
        self.assertEqual(lines[3:],[ORIGINAL[n] for n in names])
        print("PASS_POLICY19_SEMANTIC_THREE_PROBES_GUARDED_UP_READBACK_EXACT_TRANSACTION_ROLLBACK_"+self.IMAGE,flush=True)
    def test_02_negative_preimage_and_train(self):
        altered=("BEGIN; ALTER FUNCTION "+self.signature("fn_input_governance_semantic_probe_v3")
          +" SET search_path TO pg_catalog,programacion,lf_ops,public;")
        self.sql(altered+"\n"+MIG.read_text(encoding="utf-8"),error="LF_POLICY19_SEMANTIC_SOURCE_PREIMAGE_DRIFT")
        for n,sha in ORIGINAL.items():self.assertEqual(self.md5(n),sha)
        self.sql("BEGIN; UPDATE public.lf_operation_execution SET status='BLOCKED';"
             +MIG.read_text(encoding="utf-8"),error="LF_POLICY19_SEMANTIC_TRAIN_CONTEXT_REQUIRED")
        for n,sha in ORIGINAL.items():self.assertEqual(self.md5(n),sha)
        print("PASS_POLICY19_SEMANTIC_PREIMAGE_AND_TRAIN_NEGATIVES_ZERO_PERSISTENT_CHANGES_"+self.IMAGE,flush=True)
    def test_03_positive_and_negative_predicate(self):
        m=REGEX.search(MIG.read_text(encoding="utf-8"))
        self.assertIsNotNone(m)
        pred=m.group(1)
        def result(policy_id,config):
            contents=json.dumps(config,sort_keys=True,separators=(",",":")).replace("'","''")
            sql=("SELECT COALESCE(("+pred+"),false)::text FROM (SELECT "+str(policy_id)
                 +"::bigint security_policy_id,'"+contents+"'::jsonb policy_config) AS factor;")
            return self.sql(sql)
        self.assertEqual(result(77,{"factor_selection_status":"CLOSED_POLICY_DEFINED"}),"true")
        self.assertEqual(result(19,DECIDED),"true")
        cases=[
          (21,DECIDED),
          (19,{**DECIDED,"admin_profile_ids":[1]}),
          (19,{**DECIDED,"phishing_resistant_option_required":True}),
          (19,{**DECIDED,"admin_identity_provider":"GOOGLE_WORKSPACE"}),
          (19,{**DECIDED,"admin_provider_configuration_status":"READY"}),
          (19,{**DECIDED,"factor_selection_status":"OWNER_PENDING"}),
          (19,{k:v for k,v in DECIDED.items() if k!="admin_minimum_strength"})]
        for policy_id,data in cases:self.assertEqual(result(policy_id,data),"false",repr((policy_id,data)))
        self.assertIn("PENDING",DECIDED["admin_provider_configuration_status"])
        print("PASS_POLICY19_SEMANTIC_2_POSITIVES_7_FAIL_CLOSED_AND_PENDING_PROVIDER_"+self.IMAGE,flush=True)
    def test_04_committed_up_and_manual_inverse(self):
        self.sql(MIG.read_text(encoding="utf-8"))
        for n,sha in ORIGINAL.items():self.assertNotEqual(self.md5(n),sha)
        self.sql(UNDO.read_text(encoding="utf-8"))
        for n,sha in ORIGINAL.items():self.assertEqual(self.md5(n),sha)
        print("PASS_POLICY19_SEMANTIC_COMMITTED_UP_GUARDED_INVERSE_RESTORES_THREE_MD5_"+self.IMAGE,flush=True)

class PG176(Base,unittest.TestCase):
    IMAGE="postgres:17.6";VERSION="170006"
class PG187(Base,unittest.TestCase):
    IMAGE="postgres:18.7";VERSION="180007"
