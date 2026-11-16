"""PG17.6/PG18.7 behavior of CURRENT lf_ops CHECK/UNIQUE constraints from SELECT.

This is a constraint-level *gap detector*. It reproduces exact pg_get_constraintdef
fragments from actual sandbox tables at 2026-11-16 and executes SQL transactions
in ephemeral PostgreSQL. It DOES NOT exercise an upload processing endpoint,
malware scanning service or full real DB, so it MUST NOT award promotion A=40.
The SQL intentionally proves that metadata alone can hold unsafe combinations.
"""
import shutil
import subprocess
import time
import unittest
import uuid

SOURCE_CONSTRAINTS={
 "lf_ops.cargas_lotes.cargas_lotes_counts_ck":
  "CHECK (((total_records >= 0) AND (valid_count >= 0) AND "
  "(observed_count >= 0) AND (rejected_count >= 0) AND "
  "(duplicate_count >= 0) AND (processed_count >= 0) AND "
  "(not_processed_count >= 0)))",
 "lf_ops.cargas_archivos.cargas_archivos_scan_ck":
  "CHECK ((malware_scan_status = ANY (ARRAY['PENDING'::text, 'CLEAN'::text, "
  "'REJECTED'::text, 'FAILED'::text])))",
 "lf_ops.cargas_archivos.cargas_archivos_size_ck":"CHECK ((size_bytes > 0))",
 "lf_ops.cargas_lotes.cargas_lotes_idempotency_key_key":"UNIQUE (idempotency_key)",
}
DDL="""CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.cargas_lotes(
 load_code text PRIMARY KEY,
 load_name text NOT NULL,
 idempotency_key text NOT NULL,
 total_records integer NOT NULL,
 valid_count integer NOT NULL,
 observed_count integer NOT NULL,
 rejected_count integer NOT NULL,
 duplicate_count integer NOT NULL,
 processed_count integer NOT NULL,
 not_processed_count integer NOT NULL,
 CONSTRAINT cargas_lotes_counts_ck CHECK (((total_records >= 0)
  AND (valid_count >= 0) AND (observed_count >= 0) AND (rejected_count >= 0)
  AND (duplicate_count >= 0) AND (processed_count >= 0)
  AND (not_processed_count >= 0))),
 CONSTRAINT cargas_lotes_idempotency_key_key UNIQUE(idempotency_key));
CREATE TABLE lf_ops.cargas_archivos(
 file_id text PRIMARY KEY, file_name text NOT NULL, mime_type text NOT NULL,
 size_bytes bigint NOT NULL, checksum_sha256 text NOT NULL,
 malware_scan_status text NOT NULL,
 CONSTRAINT cargas_archivos_size_ck CHECK ((size_bytes > 0)),
 CONSTRAINT cargas_archivos_scan_ck CHECK ((malware_scan_status = ANY (
 ARRAY['PENDING'::text,'CLEAN'::text,'REJECTED'::text,'FAILED'::text]))));
"""
BEHAVIOR="""BEGIN;
INSERT INTO lf_ops.cargas_lotes(load_code,load_name,idempotency_key,
 total_records,valid_count,observed_count,rejected_count,duplicate_count,
 processed_count,not_processed_count)
VALUES ('B001','MANUAL_NAME','key-one',3,1,1,1,0,2,0);
INSERT INTO lf_ops.cargas_lotes(load_code,load_name,idempotency_key,
 total_records,valid_count,observed_count,rejected_count,duplicate_count,
 processed_count,not_processed_count)
VALUES ('B002','MANUAL_NAME','key-two',3,3,0,0,0,0,0);
INSERT INTO lf_ops.cargas_archivos(file_id,file_name,mime_type,size_bytes,
 checksum_sha256,malware_scan_status)
VALUES ('FILE1','payload.exe',
'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',1,
repeat('f',64),'PENDING');
SELECT 'GAP_VALID_ONLY_PROCESSED_GT_VALID='||count(*)
 FROM lf_ops.cargas_lotes WHERE processed_count>valid_count;
SELECT 'GAP_MANUAL_DUPLICATE_NAMES='||count(*)
 FROM lf_ops.cargas_lotes WHERE load_name='MANUAL_NAME';
SELECT 'GAP_MIME_EXTENSION_AND_PENDING_SCAN='||count(*)
 FROM lf_ops.cargas_archivos WHERE file_name LIKE '%.exe'
 AND mime_type LIKE '%spreadsheet%' AND malware_scan_status='PENDING';
SELECT 'CURRENT_CHECKS='||count(*) FROM pg_constraint c JOIN pg_class t
 ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
 WHERE n.nspname='lf_ops' AND c.conname IN
 ('cargas_lotes_counts_ck','cargas_lotes_idempotency_key_key',
 'cargas_archivos_scan_ck','cargas_archivos_size_ck');
DO $$
BEGIN
 BEGIN
  INSERT INTO lf_ops.cargas_lotes(load_code,load_name,idempotency_key,
   total_records,valid_count,observed_count,rejected_count,duplicate_count,
   processed_count,not_processed_count)
  VALUES ('B003','DUPE_KEY','key-one',1,1,0,0,0,0,0);
  RAISE EXCEPTION 'IDEMP_UNIQUE_NOT_ENFORCED';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
END $$;
SELECT 'DUPLICATE_IDEMPOTENCY_REJECTED='||(
 SELECT count(*) FROM lf_ops.cargas_lotes WHERE idempotency_key='key-one');
ROLLBACK;
SELECT 'ROLLBACK_LOAD_ROWS='||count(*) FROM lf_ops.cargas_lotes;
SELECT 'ROLLBACK_FILE_ROWS='||count(*) FROM lf_ops.cargas_archivos;
"""
class LiveConstraintGapPGDual(unittest.TestCase):
    def test_current_constraint_behavior_does_not_prove_backend(self):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
        for engine in ("17.6","18.7"):
            with self.subTest(pg=engine):
                name="lf-b2b-gap-"+uuid.uuid4().hex[:10]
                start=subprocess.run(["docker","run","-d","--rm","--name",name,
                  "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+engine],
                  capture_output=True,text=True,timeout=180)
                self.assertEqual(start.returncode,0,start.stderr[-2000:])
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
                    def sql(src):
                        p=subprocess.run(["docker","exec","-i",name,"psql",
                          "-X","-A","-t","-v","ON_ERROR_STOP=1","-U",
                          "postgres","-d","postgres"],input=src,
                          capture_output=True,text=True,timeout=120)
                        self.assertEqual(p.returncode,0,p.stderr[-4000:])
                        return p.stdout
                    out=sql("BEGIN;\n"+DDL+"\nCOMMIT;\n")
                    out=sql(BEHAVIOR)
                    for marker in (
                      "GAP_VALID_ONLY_PROCESSED_GT_VALID=1",
                      "GAP_MANUAL_DUPLICATE_NAMES=2",
                      "GAP_MIME_EXTENSION_AND_PENDING_SCAN=1",
                      "CURRENT_CHECKS=4",
                      "DUPLICATE_IDEMPOTENCY_REJECTED=1",
                      "ROLLBACK_LOAD_ROWS=0","ROLLBACK_FILE_ROWS=0",
                    ):
                        self.assertIn(marker,out,marker+"\n"+out[-3400:])
                    print(f"PASS_PG{engine}_SOURCE_CONSTRAINT_BEHAVIOR_GAPS_NO_BACKEND_ATTESTATION",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],
                      capture_output=True,text=True,timeout=30)

if __name__=="__main__":
    unittest.main()
