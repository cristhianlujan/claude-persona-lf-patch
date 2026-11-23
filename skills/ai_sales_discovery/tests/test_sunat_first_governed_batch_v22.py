import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sunat_first_governed_batch_v22 as m
from sunat_batch_plan_v1 import sha, canonical

class FirstBatch(unittest.TestCase):
    def test_reviewed_evidence_pair_exact(self):
        exact,prior=m.expected()
        self.assertEqual((exact["rows"],exact["batches"]),(478657,479))
        self.assertEqual(exact["manifest_digest_sha256"],m.expected()[0]["manifest_digest_sha256"])
        req=m.request_for(prior)
        self.assertEqual(req["batch_plan"]["expected"],prior)
        self.assertEqual(req["mode"],"PINNED_QA_ONLY")

    def test_sql_literal_never_breaks_query(self):
        self.assertEqual(m.sql_literal("O'Neil"),"'O''Neil'")
        with self.assertRaisesRegex(ValueError,"SQL_LITERAL_INVALID"):
            m.sql_literal("a\x00b")

    def test_one_batch_only_and_all_or_nothing_sql(self):
        payload=b'[{"fixture":"O\'Neil"}]'
        plan=[dict(batch_key="a"*64,ordinal=i+1,rows=1,bytes=len(payload),
                   capture_sha256=sha(payload),consulta_evidencia_ref="fixture")
              for i in range(479)]
        exact=dict(batches=479,manifest_digest_sha256=sha(canonical(plan)),
                   source_sha256=["b"*64,"c"*64])
        sql=m.build_transaction(plan[0],payload,plan,exact)
        self.assertIn("BEGIN;",sql)
        self.assertIn("COMMIT;",sql)
        self.assertIn("saly.ventas_sunat_batch_execute_v1",sql)
        self.assertIn("fn_lf_operation_reserve_execution_v1",sql)
        self.assertIn("fn_lf_operation_acquire_lease_v1",sql)
        self.assertIn("SUNAT_FIRST_READBACK",sql)
        self.assertIn("O''Neil",sql)
        self.assertNotIn("INSERT INTO saly.ventas_hallazgos",sql)
        with self.assertRaisesRegex(ValueError,"FIRST_BATCH_PAYLOAD_DRIFT"):
            m.build_transaction(plan[1],payload,plan,exact)
        with self.assertRaisesRegex(ValueError,"FIRST_BATCH_PLAN_DRIFT"):
            m.build_transaction(plan[0],payload,plan,dict(exact,manifest_digest_sha256="f"*64))

    def test_psql_safe_error_redacts_stderr(self):
        e=dict(os.environ,PGPASSWORD="fixture",PGHOST=m.DBHOST,PGUSER=m.DBUSER,PGDATABASE=m.DBNAME)
        with patch.dict(os.environ,e),patch.object(m.subprocess,"run",return_value=Mock(returncode=1,stderr="SENSITIVE_SQL_PASSWORD",stdout="")):
            with self.assertRaisesRegex(ValueError,"^GOVERNED_DB_CALL_REJECTED$") as got:
                m.psql("SELECT 1")
            self.assertNotIn("SENSITIVE",str(got.exception))

    def test_db_preflight_inactive_blocks_before_download(self):
        exact,_=m.expected()
        with patch.object(m,"psql",return_value=dict(configured=False,catalog=False,operation=True,
                                                       manifest=exact["manifest_digest_sha256"],
                                                       snapshots=exact["source_sha256"],existing=0)):
            with self.assertRaisesRegex(ValueError,"^DB_FIRST_BATCH_NOT_ADMITTED$"):
                m.preflight(exact)

if __name__=="__main__":
    unittest.main()
