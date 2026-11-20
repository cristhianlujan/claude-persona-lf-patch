"""E7 PG17.6/18.7 migration regression: same-load ORIGINAL CLEAN ownership gate.

This tests the database contract only. It does not certify actual authenticated
upload, object storage integrity, malware scanner or profile->IG runtime.
All business test rows are transactionally rolled back in disposable DBs.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261116135008_lf_b2b_bulk_cross_load_file_integrity_v1.sql"
BASE=r"""
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.cargas_lotes (
 load_id uuid PRIMARY KEY, load_code text NOT NULL,
 processed_count integer NOT NULL DEFAULT 0, source_file_id uuid
);
CREATE TABLE lf_ops.cargas_archivos (
 file_id uuid PRIMARY KEY, load_id uuid NOT NULL REFERENCES lf_ops.cargas_lotes(load_id),
 file_role text NOT NULL, malware_scan_status text NOT NULL
);
CREATE FUNCTION lf_ops.cargas_lotes_block_unsafe_processing_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'lf_ops'
AS $fn$ BEGIN IF NEW.processed_count>0 AND NOT EXISTS (
 SELECT 1 FROM lf_ops.cargas_archivos a WHERE a.file_id=NEW.source_file_id
 AND a.malware_scan_status='CLEAN') THEN
 RAISE EXCEPTION 'LF_B2B_UNSAFE_FILE_PROCESSING_BLOCKED load=%',NEW.load_code
 USING ERRCODE='check_violation'; END IF; RETURN NEW; END $fn$;
CREATE TRIGGER trg_cargas_lotes_block_unsafe_processing_v1 BEFORE INSERT OR UPDATE
OF processed_count,source_file_id ON lf_ops.cargas_lotes
FOR EACH ROW EXECUTE FUNCTION lf_ops.cargas_lotes_block_unsafe_processing_v1();
"""
CHECKS=r"""
BEGIN;
INSERT INTO lf_ops.cargas_lotes(load_id,load_code,processed_count)
VALUES ('00000000-0000-4000-8000-000000000011','A',0),
 ('00000000-0000-4000-8000-000000000022','B',0);
INSERT INTO lf_ops.cargas_archivos(file_id,load_id,file_role,malware_scan_status)
VALUES
 ('00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000011','ORIGINAL','CLEAN'),
 ('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000022','RESULT','CLEAN'),
 ('00000000-0000-4000-8000-000000000103','00000000-0000-4000-8000-000000000022','ORIGINAL','PENDING'),
 ('00000000-0000-4000-8000-000000000104','00000000-0000-4000-8000-000000000022','ORIGINAL','CLEAN');

DO $negative$
DECLARE test_case text; file_ref uuid;
BEGIN
 FOR test_case,file_ref IN SELECT * FROM (VALUES
 ('CROSS_LOAD','00000000-0000-4000-8000-000000000101'::uuid),
 ('WRONG_ROLE','00000000-0000-4000-8000-000000000102'::uuid),
 ('PENDING_SCAN','00000000-0000-4000-8000-000000000103'::uuid),
 ('MISSING_SOURCE','00000000-0000-4000-8000-000000000105'::uuid)
 ) v(label,source) LOOP
  BEGIN
   UPDATE lf_ops.cargas_lotes
   SET source_file_id=file_ref,processed_count=1
   WHERE load_code='B';
   RAISE EXCEPTION 'UNSAFE_%_ACCEPTED',test_case;
  EXCEPTION WHEN check_violation THEN
   IF SQLERRM NOT LIKE 'LF_B2B_UNSAFE_FILE_PROCESSING_BLOCKED%' THEN
      RAISE EXCEPTION 'WRONG_GUARD_%:%',test_case,SQLERRM;
   END IF;
   RAISE NOTICE 'BLOCK_%',test_case;
  END;
 END LOOP;
END $negative$;

UPDATE lf_ops.cargas_lotes
 SET source_file_id='00000000-0000-4000-8000-000000000104',processed_count=1
 WHERE load_code='B';
SELECT 'SAME_LOAD_CLEAN='||count(*) FROM lf_ops.cargas_lotes
 WHERE load_code='B' AND processed_count=1;
DO $drift$
BEGIN
 BEGIN
  UPDATE lf_ops.cargas_lotes SET source_file_id=
    '00000000-0000-4000-8000-000000000101' WHERE load_code='B';
  RAISE EXCEPTION 'SOURCE_DRIFT_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'LF_B2B_UNSAFE_FILE_PROCESSING_BLOCKED%' THEN
     RAISE EXCEPTION 'DRIFT_WRONG_GUARD:%',SQLERRM;
  END IF;
  RAISE NOTICE 'BLOCK_SOURCE_DRIFT';
 END;
END $drift$;
ROLLBACK;
SELECT 'ROLLBACK_LOADS='||count(*) FROM lf_ops.cargas_lotes;
SELECT 'ROLLBACK_FILES='||count(*) FROM lf_ops.cargas_archivos;
"""

class BulkLoadOwnershipGatePGDual(unittest.TestCase):
 def test_real_pgdual_and_rollback(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  mig=MIG.read_text(encoding="utf-8")
  self.assertTrue(mig.startswith("BEGIN;\n") and mig.rstrip().endswith("COMMIT;"))
  self.assertIn("a.load_id = NEW.load_id",mig)
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-e7-"+uuid.uuid4().hex[:10]
    started=subprocess.run(["docker","run","-d","--rm","--name",name,
     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
     capture_output=True,text=True,timeout=180)
    self.assertEqual(started.returncode,0,started.stderr[-1500:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,text=True,timeout=10)
      logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
      if ready.returncode==0 and "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
       break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(source):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=source,capture_output=True,text=True,timeout=120)
      self.assertEqual(p.returncode,0,p.stderr[-5000:]+p.stdout[-2000:])
      return p.stdout,p.stderr
     sql(BASE)
     sql(mig)
     out,err=sql(CHECKS)
     for x in ("SAME_LOAD_CLEAN=1","ROLLBACK_LOADS=0","ROLLBACK_FILES=0"):
      self.assertIn(x,out,x)
     for x in ("BLOCK_CROSS_LOAD","BLOCK_WRONG_ROLE","BLOCK_PENDING_SCAN",
               "BLOCK_MISSING_SOURCE","BLOCK_SOURCE_DRIFT"):
      self.assertIn(x,err,x)
     print("PASS_PG"+pg+"_E7_BULK_OWNERSHIP_GUARD_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],
      capture_output=True,text=True,timeout=30)
if __name__=="__main__": unittest.main()
