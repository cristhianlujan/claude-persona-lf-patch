"""LF rule promotion B08 documentary projection + 148 diagnostic PG17/18 rollback.
Pure fixtures, no connection to live Supabase or owner identity claim.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261114192000_lf_rule_promotion_documentary_and_screen_readback_v1.sql"
FIXTURE = r"""
CREATE ROLE service_role;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(id int PRIMARY KEY,codigo text NOT NULL,
 categoria text,estado text NOT NULL,valor_config jsonb);
CREATE TABLE lf_ops.pantallas(id int PRIMARY KEY,codigo text,estado text);
CREATE TABLE lf_ops.reglas_pantallas(regla_id int,pantalla_id int);
CREATE TABLE public.lf_ig_project_owner_v2(
 project_code text,owner_name text,identity_mode text,status text);
CREATE TABLE public.lf_rule_promotion_v1(
 promotion_id text, status text,rule_code text,request_snapshot_sha256 text);
CREATE FUNCTION public.lf_rule_promotion_decide_batch_v1(
 text[],text,text,text) RETURNS jsonb
 LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION public.lf_rule_promotion_apply_batch_v1(text[])
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(text,text)
 RETURNS text LANGUAGE sql STABLE AS $$SELECT repeat('a',64)$$;
INSERT INTO public.lf_ig_project_owner_v2 VALUES(
 'LF','Cristhian Luján','UNVERIFIED_CHAT_DECLARATION','TEMP_DOCUMENTARY_ACTIVE');
INSERT INTO lf_ops.pantallas VALUES
 (1,'S1','CANDIDATO'),(2,'S2','CANDIDATO'),
 (3,'S3','CANDIDATO'),(4,'S4','CANDIDATO'),(5,'S5','CANDIDATO'),
 (6,'SCREEN_VIS','CANDIDATO_VISUAL'),(7,'B2B-AUTH-001','CANDIDATO');
INSERT INTO lf_ops.reglas
 SELECT i, 'R-'||i, 'BUSINESS','CANDIDATO','{}'::jsonb
 FROM generate_series(1001,1162) g(i);
INSERT INTO lf_ops.reglas VALUES
 (438,'B2B-RULE-AUTH-019','UX','CANDIDATO',
   '{"owner_decision_identity_verified":false}'::jsonb),
 (439,'B2B-RULE-AUTH-020','SECURITY','CANDIDATO',
   '{"owner_decision_identity_verified":false}'::jsonb),
 (440,'B2B-RULE-AUTH-021','SECURITY','CANDIDATO',
   '{"owner_decision_identity_verified":false}'::jsonb),
 (577,'B2B-RULE-AUTH-047','UX','CANDIDATO',
   '{"owner_decision_identity_verified":false,"screen_code":"B2B-AUTH-001"}'::jsonb),
 (235,'REG_B2B_005','BUSINESS','VIGENTE',
   '{"owner_decision_identity_verified":false}'::jsonb),
 (532,'REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001','BUSINESS','VIGENTE',
   '{"owner_decision_identity_verified":false}'::jsonb);
INSERT INTO lf_ops.reglas_pantallas
 SELECT i,s FROM generate_series(1001,1018) g(i)
 CROSS JOIN generate_series(1,5) t(s);
INSERT INTO lf_ops.reglas_pantallas VALUES (438,6),(439,7);
"""
class PromotionDocumentaryPgDual(unittest.TestCase):
    def test_pg17_18_readback_rollback(self):
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED")
        mig = MIG.read_text("utf-8")
        self.assertIn("false AS identity_verified_effective", mig)
        self.assertNotIn("UPDATE lf_ops.reglas", mig)
        self.assertNotIn("INSERT INTO lf_ops.reglas_pantallas", mig)
        body = mig.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-promotion-evidence-"+uuid.uuid4().hex[:9]
                startup=subprocess.run(["docker","run","-d","--rm","--name",name,
                   "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                   capture_output=True,text=True,timeout=180)
                self.assertEqual(startup.returncode,0,startup.stderr)
                try:
                    for _ in range(80):
                        ready=subprocess.run(["docker","exec",name,"pg_isready",
                            "-U","postgres"],capture_output=True,timeout=8)
                        logs=subprocess.run(["docker","logs",name],
                            capture_output=True,text=True,timeout=8)
                        if ready.returncode==0 and (
                            "PostgreSQL init process complete; ready for start up."
                            in (logs.stdout+logs.stderr)): break
                        time.sleep(.7)
                    self.assertEqual(ready.returncode,0)
                    def psql(q):
                        return subprocess.run(["docker","exec","-i",name,"psql",
                          "-X","-A","-t","-v","ON_ERROR_STOP=1",
                          "-U","postgres","-d","postgres"],
                          input=q,capture_output=True,text=True,timeout=120)
                    seeded=psql(FIXTURE)
                    self.assertEqual(seeded.returncode,0,seeded.stderr[-2500:])
                    query=r"""
SELECT 'OWNER_6='||count(*) FROM public.lf_rule_promotion_documentary_owner_v1
 WHERE rule_id IN (235,438,439,440,532,577)
 AND identity_verified_effective=false AND source_identity_assertion='false';
SELECT 'SCREEN_148='||count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
 WHERE linked_screens<5;
SELECT 'A='||count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
 WHERE diagnostic_bucket='A_EVIDENCED_LINK_MISSING';
SELECT 'B='||count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
 WHERE diagnostic_bucket='B_UI_E2E_REVIEW';
SELECT 'C='||count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
 WHERE diagnostic_bucket='C_LOW_SCOPE_PROVISIONAL';
SELECT 'D='||count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
 WHERE diagnostic_bucket='D_NO_LINK_UNKNOWN';
SELECT 'BATCH_DRY='||(public.lf_rule_promotion_batch_dryrun_v1(
 ARRAY['PROMO-NONEXISTENT']) ->>'no_write_performed');
SELECT 'NO_REQ='||count(*) FROM public.lf_rule_promotion_v1;
SELECT 'SERVICE_GRANTED='||(
 has_table_privilege('service_role',
  'public.lf_rule_promotion_documentary_owner_v1','SELECT') AND
 has_function_privilege('service_role',
  'public.lf_rule_promotion_batch_dryrun_v1(text[])','EXECUTE'))::text;
SELECT 'ANON_DENIED='||(NOT has_table_privilege('anon',
 'public.lf_rule_promotion_documentary_owner_v1','SELECT'))::text;
"""
                    output=psql("BEGIN;\n"+body+"\n"+query+"\nROLLBACK;\n"
                       "SELECT 'POST_ROLLBACK_VIEW='||(to_regclass("
                       "'public.lf_rule_promotion_documentary_owner_v1') IS NULL)::text;\n"
                       "SELECT 'POST_ROLLBACK_RULES='||count(*) FROM lf_ops.reglas;")
                    self.assertEqual(output.returncode,0,output.stderr[-3500:])
                    for want in ("OWNER_6=6","SCREEN_148=148",
                         "A=1","B=1","C=1","D=145",
                         "BATCH_DRY=true","NO_REQ=0",
                         "SERVICE_GRANTED=true","ANON_DENIED=true",
                         "POST_ROLLBACK_VIEW=true","POST_ROLLBACK_RULES=168"):
                        self.assertIn(want,output.stdout,want+" not in "+output.stdout)
                    print("PASS_LF_PROMOTION_EVIDENCE_PG_"+pg+
                          "_6_DOCUMENTARY_148_SCREEN_DRYRUN_ROLLBACK")
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,timeout=30)
