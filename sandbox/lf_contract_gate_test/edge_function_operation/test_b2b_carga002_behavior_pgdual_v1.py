"""Owner 22:08: behavior of real PostgreSQL CHECK/UNIQUE readback from lf_ops tables.

The fixture recreates the EXACT four critical current CHECK/UNIQUE constraints
read from Supabase, in PostgreSQL 17.6 and 18.7. It does not connect to Supabase,
run an upload-scanner, or test a backend transition processor. Report contract FAIL
for real DB gaps; never stamp them PG PASS merely because regression tests pass.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from test_b2b_validonly_storage_current_pg_gaps_v1 import DDL

TXN=r"""
BEGIN;
INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,
 valid_count,observed_count,rejected_count,duplicate_count,
 processed_count,not_processed_count)
VALUES('VALID-ONLY-CHECK','Carga VALID_ONLY','load-key-valid',3,
 1,1,1,0,2,0);
SELECT 'VALID_ONLY_GAP_ACCEPTED='||count(*) FROM lf_ops.cargas_lotes
 WHERE load_code='VALID-ONLY-CHECK' AND processed_count>valid_count;
INSERT INTO lf_ops.cargas_archivos (
 file_id,file_name,mime_type,size_bytes,checksum_sha256,malware_scan_status)
 VALUES('EXE','payload.exe',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 128,repeat('f',64),'PENDING');
SELECT 'STORAGE_MIME_EXE_GAP_ACCEPTED='||count(*) FROM lf_ops.cargas_archivos
 WHERE file_id='EXE' AND file_name LIKE '%.exe'
 AND mime_type LIKE '%spreadsheet%' AND malware_scan_status='PENDING';
DO $negative$
BEGIN
 BEGIN
  INSERT INTO lf_ops.cargas_archivos(
   file_id,file_name,mime_type,size_bytes,checksum_sha256,malware_scan_status)
  VALUES('ZERO','good.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    0,repeat('a',64),'CLEAN');
  RAISE EXCEPTION 'SIZE_0_UNEXPECTED_ACCEPT';
 EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'STORAGE_SIZE_ZERO_BLOCKED';
 END;
END $negative$;
SELECT 'STORAGE_ZERO_ROWS='||count(*) FROM lf_ops.cargas_archivos WHERE file_id='ZERO';
INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,
 valid_count,observed_count,rejected_count,duplicate_count,
 processed_count,not_processed_count)
VALUES('I-FIRST','Idempotencia','same-idempotency-key',1,
 1,0,0,0,0,0);
INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,
 valid_count,observed_count,rejected_count,duplicate_count,
 processed_count,not_processed_count)
VALUES('I-SECOND','Idempotencia','same-idempotency-key',1,
 1,0,0,0,0,0)
ON CONFLICT (idempotency_key) DO NOTHING;
SELECT 'IDEMP_TWO_REQUESTS_ONE_ROW='||count(*) FROM lf_ops.cargas_lotes
 WHERE idempotency_key='same-idempotency-key';
SELECT 'VALIDATION-CONTRACT=FAIL';
SELECT 'STORAGE-CONTRACT=FAIL';
SELECT 'IDEMP-KEY-CONTRACT=PASS';
ROLLBACK;
SELECT 'ROLLBACK_NO_LOAD_ROWS='||count(*) FROM lf_ops.cargas_lotes;
SELECT 'ROLLBACK_NO_FILE_ROWS='||count(*) FROM lf_ops.cargas_archivos;
"""
class B2BCarga002PGDual(unittest.TestCase):
 def test_source_bound_real_postgres_constraints_and_failures(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-b2b-beh-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
       capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-2000:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready",
        "-U","postgres"],capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],
          capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(statement):
      proc=subprocess.run(["docker","exec","-i",name,"psql",
         "-X","-A","-t","-v","ON_ERROR_STOP=1",
         "-U","postgres","-d","postgres"],
         input=statement,capture_output=True,text=True,timeout=180)
      self.assertEqual(proc.returncode,0,proc.stderr[-5000:]+"\n"+proc.stdout[-2500:])
      return proc.stdout,proc.stderr
     sql(DDL)
     out,err=sql(TXN)
     for expected in (
      "VALID_ONLY_GAP_ACCEPTED=1",
      "STORAGE_MIME_EXE_GAP_ACCEPTED=1",
      "STORAGE_ZERO_ROWS=0",
      "IDEMP_TWO_REQUESTS_ONE_ROW=1",
      "VALIDATION-CONTRACT=FAIL",
      "STORAGE-CONTRACT=FAIL",
      "IDEMP-KEY-CONTRACT=PASS",
      "ROLLBACK_NO_LOAD_ROWS=0",
      "ROLLBACK_NO_FILE_ROWS=0"
     ):
      self.assertIn(expected,out,expected+"\n"+out[-2200:])
     self.assertIn("STORAGE_SIZE_ZERO_BLOCKED",err)
     print("PASS_B2B_CARGA002_PG"+pg+"_VALID_FAIL_STORAGE_FAIL_IDEMP_PASS_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)

if __name__=="__main__":
 unittest.main()
