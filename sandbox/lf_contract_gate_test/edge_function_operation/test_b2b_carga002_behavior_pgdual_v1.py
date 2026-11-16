"""Owner 22:40. PG17.6/PG18.7 real Postgres constraints and trigger from EXACT
migration 20261116040000. This is scoped database behavior (not malware-scanner
service or end-to-end authenticated upload). All behavioral writes BEGIN/ROLLBACK.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from test_b2b_validonly_storage_current_pg_gaps_v1 import DDL

ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_b2b_carga002_hardening_v1.sql"))
if len(MIGS)!=1:
 raise RuntimeError("LF_B2B_HARDENING_MIGRATION_AMBIGUOUS_OR_MISSING")
MIG=MIGS[0]
EXT_DDL="""
ALTER TABLE lf_ops.cargas_lotes ADD COLUMN source_file_id text;
ALTER TABLE lf_ops.cargas_archivos ADD COLUMN file_role text NOT NULL DEFAULT 'ORIGINAL';
"""
TXN=r"""
BEGIN;
INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
 checksum_sha256,malware_scan_status,file_role)
VALUES('CLEANFILE','good.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 123,repeat('a',64),'CLEAN','ORIGINAL');
DO $negative$
DECLARE v_constraint text;
BEGIN
 BEGIN
  INSERT INTO lf_ops.cargas_lotes(
   load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
   rejected_count,duplicate_count,processed_count,not_processed_count,source_file_id)
  VALUES('BAD_VALID','bad valid only','invalid-val-key',3,1,1,1,0,2,0,'CLEANFILE');
  RAISE EXCEPTION 'INVALID_VALID_ONLY_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
  IF v_constraint<>'cargas_lotes_valid_only_processed_chk' THEN
   RAISE EXCEPTION 'WRONG_VALID_ONLY_CONSTRAINT:%',v_constraint;
  END IF;
  RAISE NOTICE 'BLOCK_VALID_ONLY_PROCESSED_GT_VALID';
 END;
 BEGIN
  INSERT INTO lf_ops.cargas_lotes(
   load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
   rejected_count,duplicate_count,processed_count,not_processed_count,source_file_id)
  VALUES('BAD_SUM','bad sum','invalid-sum-key',2,2,1,1,0,0,0,NULL);
  RAISE EXCEPTION 'INVALID_SUM_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
  IF v_constraint<>'cargas_lotes_counts_sum_chk' THEN
   RAISE EXCEPTION 'WRONG_SUM_CONSTRAINT:%',v_constraint;
  END IF;
  RAISE NOTICE 'BLOCK_COUNTS_SUM_GT_TOTAL';
 END;
 BEGIN
  INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
   checksum_sha256,malware_scan_status,file_role)
  VALUES('EXE','payload.exe',
   'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
   128,repeat('f',64),'PENDING','ORIGINAL');
  RAISE EXCEPTION 'EXE_MIME_SPOOF_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
  IF v_constraint<>'cargas_archivos_ext_mime_chk' THEN
   RAISE EXCEPTION 'WRONG_EXTENSION_MIME_CONSTRAINT:%',v_constraint;
  END IF;
  RAISE NOTICE 'BLOCK_EXE_MIME_SPOOF';
 END;
 BEGIN
  INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
   checksum_sha256,malware_scan_status,file_role)
  VALUES('BADCHECK','bad.xlsx',
   'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
   128,'not-sha256','CLEAN','ORIGINAL');
  RAISE EXCEPTION 'BAD_CHECKSUM_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
  IF v_constraint<>'cargas_archivos_checksum_chk' THEN
   RAISE EXCEPTION 'WRONG_CHECKSUM_CONSTRAINT:%',v_constraint;
  END IF;
  RAISE NOTICE 'BLOCK_BAD_CHECKSUM';
 END;
 BEGIN
  INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
   checksum_sha256,malware_scan_status,file_role)
  VALUES('ZERO','good.xlsx',
   'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    0,repeat('b',64),'CLEAN','ORIGINAL');
  RAISE EXCEPTION 'BAD_SIZE_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
  IF v_constraint<>'cargas_archivos_size_ck' THEN
   RAISE EXCEPTION 'WRONG_SIZE_CONSTRAINT:%',v_constraint;
  END IF;
  RAISE NOTICE 'BLOCK_ZERO_SIZE';
 END;
END $negative$;

INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
 checksum_sha256,malware_scan_status,file_role)
VALUES('PENDINGFILE','pending.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 128,repeat('c',64),'PENDING','ORIGINAL');
DO $malware$
BEGIN
 BEGIN
  INSERT INTO lf_ops.cargas_lotes(
   load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
   rejected_count,duplicate_count,processed_count,not_processed_count,source_file_id)
  VALUES('UNSAFE','unsafe file','unsafe-key',1,1,0,0,0,1,0,'PENDINGFILE');
  RAISE EXCEPTION 'PENDING_FILE_PROCESSING_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'LF_B2B_UNSAFE_FILE_PROCESSING_BLOCKED%' THEN
   RAISE EXCEPTION 'WRONG_UNSAFE_PROCESSING_BLOCK:%',SQLERRM;
  END IF;
  RAISE NOTICE 'BLOCK_PROCESSING_FILE_NOT_CLEAN';
 END;
END $malware$;

INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
 rejected_count,duplicate_count,processed_count,not_processed_count,source_file_id)
VALUES('GOOD','good load','good-key',1,1,0,0,0,1,0,'CLEANFILE');
SELECT 'POSITIVE_CLEAN_XLSX_SHA='||count(*) FROM lf_ops.cargas_lotes
 WHERE load_code='GOOD' AND processed_count=1 AND valid_count=1
 AND source_file_id='CLEANFILE';
SELECT 'INVALID_LOADS_REMAIN='||count(*) FROM lf_ops.cargas_lotes
 WHERE load_code IN ('BAD_VALID','BAD_SUM','UNSAFE');
SELECT 'INVALID_FILES_REMAIN='||count(*) FROM lf_ops.cargas_archivos
 WHERE file_id IN ('EXE','BADCHECK','ZERO');

INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
 rejected_count,duplicate_count,processed_count,not_processed_count)
VALUES('I-FIRST','Idempotencia','same-idempotency-key',1,1,0,0,0,0,0);
INSERT INTO lf_ops.cargas_lotes(
 load_code,load_name,idempotency_key,total_records,valid_count,observed_count,
 rejected_count,duplicate_count,processed_count,not_processed_count)
VALUES('I-SECOND','Idempotencia','same-idempotency-key',1,1,0,0,0,0,0)
ON CONFLICT (idempotency_key) DO NOTHING;
SELECT 'IDEMP_TWO_REQUESTS_ONE_ROW='||count(*) FROM lf_ops.cargas_lotes
 WHERE idempotency_key='same-idempotency-key';

SELECT 'HARDENING_CHECKS='||count(*) FROM pg_constraint c
 JOIN pg_namespace n ON n.oid=(SELECT relnamespace FROM pg_class WHERE oid=c.conrelid)
 WHERE n.nspname='lf_ops' AND c.conname IN(
 'cargas_lotes_valid_only_processed_chk','cargas_lotes_counts_sum_chk',
 'cargas_archivos_ext_mime_chk','cargas_archivos_checksum_chk') AND c.convalidated;
SELECT 'HARDENING_TRIGGER='||count(*) FROM pg_trigger t
 WHERE t.tgname='trg_cargas_lotes_block_unsafe_processing_v1' AND NOT t.tgisinternal;
SELECT 'VALIDATION-CONTRACT=PASS';
SELECT 'STORAGE-CONTRACT=PASS';
SELECT 'IDEMP-KEY-CONTRACT=PASS';
ROLLBACK;
SELECT 'ROLLBACK_NO_LOAD_ROWS='||count(*) FROM lf_ops.cargas_lotes;
SELECT 'ROLLBACK_NO_FILE_ROWS='||count(*) FROM lf_ops.cargas_archivos;
"""

class B2BCarga002PGDual(unittest.TestCase):
 def test_source_bound_real_postgres_hardening_and_rollback(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=MIG.read_text(encoding="utf-8")
  self.assertTrue(migration.startswith("BEGIN;\n"))
  self.assertTrue(migration.rstrip().endswith("COMMIT;"))
  self.assertIn("trg_cargas_lotes_block_unsafe_processing_v1",migration)
  self.assertIn("cargas_archivos_checksum_chk",migration)
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-b2b-hard-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
       capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-2000:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready",
        "-U","postgres"],capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(statement):
      proc=subprocess.run(["docker","exec","-i",name,"psql",
         "-X","-A","-t","-v","ON_ERROR_STOP=1",
         "-U","postgres","-d","postgres"],
         input=statement,capture_output=True,text=True,timeout=180)
      self.assertEqual(proc.returncode,0,proc.stderr[-5500:]+"\n"+proc.stdout[-3200:])
      return proc.stdout,proc.stderr
     sql(DDL+"\n"+EXT_DDL)
     sql(migration)
     out,err=sql(TXN)
     for expected in (
      "POSITIVE_CLEAN_XLSX_SHA=1",
      "INVALID_LOADS_REMAIN=0",
      "INVALID_FILES_REMAIN=0",
      "IDEMP_TWO_REQUESTS_ONE_ROW=1",
      "HARDENING_CHECKS=4",
      "HARDENING_TRIGGER=1",
      "VALIDATION-CONTRACT=PASS",
      "STORAGE-CONTRACT=PASS",
      "IDEMP-KEY-CONTRACT=PASS",
      "ROLLBACK_NO_LOAD_ROWS=0",
      "ROLLBACK_NO_FILE_ROWS=0"
     ):
      self.assertIn(expected,out,expected+"\n"+out[-3200:])
     for negative in (
      "BLOCK_VALID_ONLY_PROCESSED_GT_VALID",
      "BLOCK_COUNTS_SUM_GT_TOTAL",
      "BLOCK_EXE_MIME_SPOOF",
      "BLOCK_BAD_CHECKSUM",
      "BLOCK_ZERO_SIZE",
      "BLOCK_PROCESSING_FILE_NOT_CLEAN"
     ):
      self.assertIn(negative,err,negative+"\n"+err[-2500:])
     print("PASS_B2B_CARGA002_PG"+pg+"_VALID_PASS_STORAGE_PASS_IDEMP_PASS_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":
 unittest.main()
