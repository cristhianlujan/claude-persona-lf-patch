"""Postgres 17.6/18.7 disposable JSONB input matrix + rollback.
The SQL fixture is not a replacement for Deno/Python runtime guards;
it verifies the same field-boundary contract at PostgreSQL JSONB level.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixture_ig_transport_flow_matrix_rollback_v1.sql"

class PgIgTransportFlowRollback(unittest.TestCase):
    def verify(self,image,version_prefix):
        self.assertTrue(shutil.which("docker"),"NOT_TESTED_DOCKER_MISSING")
        name="lf-ig-field-"+uuid.uuid4().hex[:11]
        r=subprocess.run(["docker","run","--rm","-d","--name",name,
            "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=180)
        self.assertEqual(r.returncode,0,r.stderr[-1000:])
        try:
            for _ in range(90):
                x=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                    capture_output=True,text=True,timeout=5)
                if x.returncode==0:break
                time.sleep(.8)
            else:self.fail("PG_READY_TIMEOUT")
            db=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
                "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                input="SHOW server_version_num;\n"+SQL.read_text(encoding="utf-8"),
                text=True,capture_output=True,timeout=120)
            self.assertEqual(db.returncode,0,db.stderr[-3800:])
            observed=db.stdout.splitlines()
            self.assertTrue(observed[0].startswith(version_prefix),observed[:2])
            self.assertIn("PASS_PG_IG_GUARD_53_CASES|53|43",observed)
            self.assertIn("PASS_PG_IG_MATRIX_ROLLBACK_CLEAN",observed)
            # Strong post-query: a rolled-back disposable matrix left no table.
            verify=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
                "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                input="SELECT to_regclass('pg_temp.lf_ig_transport_test_receipt') IS NULL;",
                text=True,capture_output=True,timeout=30)
            self.assertEqual(verify.returncode,0,verify.stderr)
            self.assertEqual(verify.stdout.strip(),"t")
            print("PASS_IG_PG_JSONB_FIELD_BY_FIELD_ROLLBACK_"+image,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=45)

    def test_pg176(self):
        self.verify("postgres:17.6","170006")

    def test_pg187(self):
        self.verify("postgres:18.7","180007")

if __name__=="__main__":unittest.main()
