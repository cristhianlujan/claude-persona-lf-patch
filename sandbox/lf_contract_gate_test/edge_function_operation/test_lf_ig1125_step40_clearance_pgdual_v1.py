"""Dual PG17/18 preimage-guard and rollback test of the EKB/clearance migration.

Reduced-function fixture only. Not a native 11-step run nor live DB evidence.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261116174000_lf_profile_ig_clearance_step40_step80_v1.sql"
EKB="""
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE public.lf_error_knowledge(
 id uuid, codigo text, categoria text, titulo text, descripcion text,
 causa_raiz text, patron text, prevencion text, validacion text, severidad text,
 frecuencia integer, primera_vez timestamptz, ultima_vez timestamptz,
 lote_origen text, pr text, estado text, evidencia text, lifecycle_phase text,
 consumer_role text[], root_cause_family text, detectability text,
 source_context text, source_ref text, created_at timestamptz, updated_at timestamptz
);
"""
FN="""
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
 p_execution_id text,p_source_revision text,p_source_digest text,p_actor_execution_id text
) RETURNS jsonb LANGUAGE plpgsql AS $f$
BEGIN
 RETURN jsonb_build_object('status','READY',
      'production_authorized',false,'promotion_authorized',false,
      'mutation_authorized',false);
END $f$;
"""
class ClearBlockedIgFindingsPGDual(unittest.TestCase):
 def test_source_exact_guard_and_rollback_pg17_pg18(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=MIGRATION.read_text(encoding="utf-8")
  self.assertTrue(migration.startswith("-- IG 11:25:"))
  self.assertTrue(migration.rstrip().endswith("COMMIT;"))
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-ig1125-"+uuid.uuid4().hex[:10]
    created=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
       capture_output=True,text=True,timeout=180)
    self.assertEqual(created.returncode,0,created.stderr[-1200:])
    try:
     for _ in range(120):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
         capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(source,fail=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
         "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],input=source,
         capture_output=True,text=True,timeout=120)
      if fail:self.assertNotEqual(p.returncode,0,"NEGATIVE_EXPECTED_FAILURE")
      else:self.assertEqual(p.returncode,0,p.stderr[-1800:])
      return p
     sql(EKB+FN)
     broken=FN.replace("'mutation_authorized',false","'mutation_authorized_changed',false")
     sql(broken)
     err=sql(migration,fail=True).stderr
     self.assertIn("LF_IG1125_CLEARANCE_TRANSPORT_PATCH_NOT_APPLIED",err)
     sql(FN)
     # Never commit fixture migration. Real Train alone may apply source.
     body=migration.replace("BEGIN;\nDO $fix$","DO $fix$",1)
     body=body.rsplit("COMMIT;",1)[0]
     receipt=sql("BEGIN;\n"+body+"""
SELECT 'CLEARANCE='||coalesce(
 public.lf_profile_native_bridge_prepare_v1('RUN-TEST','r','d','actor')
 ->>'ig_security_clearance','MISSING');
SELECT 'EKB='||count(*) FROM public.lf_error_knowledge;
ROLLBACK;
SELECT 'POST_ROLLBACK='||count(*) FROM public.lf_error_knowledge;
""").stdout
     self.assertIn("CLEARANCE=false",receipt)
     self.assertIn("EKB=1",receipt)
     self.assertIn("POST_ROLLBACK=0",receipt)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

if __name__=="__main__":unittest.main(verbosity=2)
