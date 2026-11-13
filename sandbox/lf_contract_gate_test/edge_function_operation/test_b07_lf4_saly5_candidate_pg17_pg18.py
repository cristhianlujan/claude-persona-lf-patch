#!/usr/bin/env python3
"""B07 candidate: UP/DOWN, SHA256 preimages, negative checks in real PG17.6/18.7.

All writes occur in disposable Docker containers. Supabase is NEVER contacted.
The LF source fixture is a partial live-object slice; SALY is reconstructed with
14 synthetic-content rows preserving observed codes, states, decision_id.
This is NOT a production rollout, not a B07 close, and not proof of source parity.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
DIR=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle"
SLICE=DIR/"pg18_live_object_slice_baseline.sql"
SEED=DIR/"b07_saly_14_rows_fixture.sql"
UP=DIR/"b07_lf4_saly5_candidate_up.sql"
DOWN=DIR/"b07_lf4_saly5_candidate_down.sql"
V2=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"

PREIMAGE="""SELECT encode(extensions.digest(convert_to(
 jsonb_build_object(
   'lf',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY id),'[]'::jsonb)
          FROM lf_ops.reglas r),
   'saly',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY id),'[]'::jsonb)
          FROM saly.reglas r),
   'cols',(SELECT coalesce(jsonb_agg(
      jsonb_build_array(n.nspname,c.relname,a.attnum,a.attname,
        format_type(a.atttypid,a.atttypmod),a.attnotnull,
        pg_get_expr(d.adbin,d.adrelid))
      ORDER BY n.nspname,c.relname,a.attnum),'[]'::jsonb)
     FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
     JOIN pg_namespace n ON n.oid=c.relnamespace
     LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
     WHERE (n.nspname,c.relname) IN (('lf_ops','reglas'),('saly','reglas'))
       AND a.attnum>0 AND NOT a.attisdropped),
   'rls',(SELECT coalesce(jsonb_agg(
      jsonb_build_array(n.nspname,c.relname,c.relrowsecurity)
      ORDER BY n.nspname,c.relname),'[]'::jsonb)
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE (n.nspname,c.relname) IN (('lf_ops','reglas'),('saly','reglas'))))::text,
 'UTF8'),'sha256'),'hex');"""

class B07Candidate(unittest.TestCase):
 def verify(self,image,expected):
  self.assertIsNotNone(shutil.which("docker"),"NOT_TESTED_DOCKER")
  for f in (SLICE,SEED,UP,DOWN,V2): self.assertTrue(f.is_file(),"MISSING:"+str(f))
  name="lf-b07-candidate-"+uuid.uuid4().hex[:12]
  p=subprocess.run(["docker","run","--rm","-d","--name",name,
    "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
    capture_output=True,text=True,timeout=240)
  self.assertEqual(p.returncode,0,p.stderr)
  try:
   def sql(statement,expect_fail=None):
    r=subprocess.run(["docker","exec","-i",name,"psql","-X","-q","-A","-t",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=statement,text=True,capture_output=True,timeout=450)
    if expect_fail:
     self.assertNotEqual(r.returncode,0,"SQL_SHOULD_FAIL")
     self.assertIn(expect_fail,r.stderr[-5000:])
    else:self.assertEqual(r.returncode,0,"SQL_FAILED:\n"+r.stderr[-5000:]+"\nSQL="+statement[:500])
    return r.stdout.strip()
   for _ in range(60):
    r=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres","-d","postgres"],
     capture_output=True,text=True,timeout=20)
    if r.returncode==0: break
    time.sleep(1)
   else:self.fail("POSTGRES_READY_TIMEOUT")
   version=sql("SHOW server_version_num;").splitlines()[-1]
   self.assertEqual(version,expected)
   sql(SLICE.read_text(encoding="utf-8"))
   # PR #3803 V2 original SQL replayed under a synthetic Train context.
   import json
   def q(s): return "'"+str(s).replace("'","''")+"'"
   trainid="43379990001"; code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
   target="supabase/migrations/"+code+".sql"
   repo="cristhianlujan/claude-persona-lf-patch"
   manifest={"producer":"lf-migration-merge-train","pr":3803,
      "train_run_id":trainid,"head_sha":"e"*40,
      "router_authority_receipt":{
        "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
        "operation_code":"ACTUALIZACION_DB_LF","target_repo":repo,
        "target_code":code,"target_path":target,
        "route_eligibility_only":True,"scope_attested":False}}
   trainexec="EXEC-DB-TRAIN-PR3803-20261113030000-R"+trainid
   sql(f"""INSERT INTO public.lf_operation_execution(
     execution_id,operation_code,target_type,target_code,target_repo,target_path,status,
     request_sha256,manifest,idempotency_key,created_by_execution_id)
     VALUES({q(trainexec)},'ACTUALIZACION_DB_LF','MIGRATION',{q(code)},{q(repo)},
       {q(target)},'IN_PROGRESS',{q('f'*64)},
       {q(json.dumps(manifest,separators=(',',':')))}::jsonb,
       {q('train:20261113030000:'+'e'*40)},
       'LF-MIGRATION-TRAIN-RUN-43379990001');""")
   sql(V2.read_text(encoding="utf-8"))
   self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NOT NULL;"),"t")
   sql(SEED.read_text(encoding="utf-8"))
   before=sql(PREIMAGE)
   self.assertEqual(len(before),64)
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO' AND vigente;"),"14")
   self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE id IN (-70701,-70702);"),"2")
   sql(UP.read_text(encoding="utf-8"))
   self.assertEqual(sql("""SELECT count(*) FROM information_schema.columns
       WHERE (table_schema='lf_ops' AND table_name='reglas'
         AND column_name IN ('lifecycle_state','lifecycle_source_sha256',
           'lifecycle_decision_ref','lifecycle_changed_at'))
          OR (table_schema='saly' AND table_name='reglas'
         AND column_name IN ('lifecycle_state','lifecycle_source_sha256',
           'lifecycle_decision_ref','lifecycle_changed_at','lifecycle_origin_estado'));"""),"9")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE lifecycle_state IS NOT NULL;"),"0")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO' AND vigente;"),"14")
   sql("UPDATE lf_ops.reglas SET lifecycle_state='CI_ONLY' WHERE id=-70701;",
       expect_fail="lf_b07_lifecycle_bundle_v1")
   sql("UPDATE saly.reglas SET lifecycle_source_sha256='not-a-hash' WHERE id=1;",
       expect_fail="saly_b07_lifecycle_sha_v1")
   sql("UPDATE saly.reglas SET lifecycle_origin_estado='VIGENTE' WHERE id=1;",
       expect_fail="saly_b07_lifecycle_origin_v1")
   both=sql("""BEGIN;
     UPDATE lf_ops.reglas SET lifecycle_state='CI_ONLY',lifecycle_source_sha256=repeat('a',64),
       lifecycle_decision_ref='CI-ONLY',lifecycle_changed_at=now() WHERE id=-70701;
     UPDATE saly.reglas SET lifecycle_state='CI_ONLY',lifecycle_source_sha256=repeat('b',64),
       lifecycle_decision_ref='CI-ONLY',lifecycle_changed_at=now(),
       lifecycle_origin_estado='VALIDADO' WHERE id=1;
     SELECT (SELECT estado FROM lf_ops.reglas WHERE id=-70701)||'|'||
            (SELECT estado FROM saly.reglas WHERE id=1);
     ROLLBACK;""")
   self.assertIn("CANDIDATO|VALIDADO",both)
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE lifecycle_state IS NOT NULL;"),"0")
   # This update is COMMITTED in disposable PG only to test fail-closed DOWN.
   sql("""UPDATE saly.reglas SET lifecycle_state='CI_ONLY',
        lifecycle_source_sha256=repeat('c',64),lifecycle_decision_ref='CI-ONLY',
        lifecycle_changed_at=now(),lifecycle_origin_estado='VALIDADO' WHERE id=1;""")
   sql(DOWN.read_text(encoding="utf-8"),expect_fail="B07_DOWN_NONEMPTY_EVIDENCE_BLOCKED")
   self.assertEqual(sql("SELECT lifecycle_state||'|'||estado FROM saly.reglas WHERE id=1;"),
                    "CI_ONLY|VALIDADO")
   sql("""UPDATE saly.reglas SET lifecycle_state=NULL,lifecycle_source_sha256=NULL,
        lifecycle_decision_ref=NULL,lifecycle_changed_at=NULL,
        lifecycle_origin_estado=NULL WHERE id=1;""")
   sql(DOWN.read_text(encoding="utf-8"))
   after=sql(PREIMAGE)
   self.assertEqual(before,after,"PREIMAGE_DIFF_AFTER_UP_DOWN")
   self.assertEqual(sql("SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO';"),"14")
   self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NOT NULL;"),"t")
   # Replaying DOWN cannot silently succeed or drop other objects.
   sql(DOWN.read_text(encoding="utf-8"),expect_fail="B07_DOWN_EXACT_SHAPE_REQUIRED")
   print("PASS_B07_CANDIDATE_"+image.replace(":","_")+" PG="+version+
       " PREIMAGE_SHA256="+before+" POST_DOWN_SHA256="+after,flush=True)
   print("PASS_B07_NEGATIVES_INCOMPLETE_SHA_ORIGIN_AND_DATA_BEARING_DOWN",flush=True)
   print("B07_NOT_CLOSED_ALL_NINE_COLUMNS_INFERRED_OWNER_DECISION_AND_LIVE_TRAIN_MISSING",flush=True)
   print("FIXTURE=LF_LIVE_OBJECT_SLICE_PLUS_14_SALY_SYNTHETIC_CONTENT_ROWS",flush=True)
  finally:
   subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=90)
 def test_pg17_6(self):self.verify("postgres:17.6","170006")
 def test_pg18_7(self):self.verify("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
