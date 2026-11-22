"""Small unit tests for sequential-only SALY SUNAT continuation; no DB calls."""
import unittest
from unittest.mock import patch
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import sunat_remaining_sequential_v25 as s
from sunat_batch_plan_v1 import sha


class SequentialBatchTests(unittest.TestCase):
    def test_transaction_one_batch_native_writer_only(self):
        payload=b'[{"fixture":"O\'Neil"}]'
        entry=dict(batch_key='a'*64,ordinal=2,rows=1000,bytes=len(payload),capture_sha256=sha(payload))
        sql=s.build_one_batch_sql(entry,payload,2,2000)
        self.assertIn("BEGIN;",sql)
        self.assertIn("COMMIT;",sql)
        self.assertIn("pg_advisory_xact_lock",sql)
        self.assertIn("v_found<>1",sql)
        self.assertIn("ventas_sunat_batch_execute_v1",sql)
        self.assertIn("SUNAT_SEQUENTIAL_OUT_OF_ORDER",sql)
        self.assertIn("SUNAT_SEQUENTIAL_READBACK",sql)
        self.assertIn("O''Neil",sql)
        self.assertNotIn("INSERT INTO saly.ventas_hallazgos",sql)
        self.assertNotIn("fn_lf_operation_reserve_execution_v1",sql)
        self.assertEqual(sql.count("ventas_sunat_batch_execute_v1"),1)

    def test_fail_ordinal_and_hash(self):
        payload=b'[{"fixture":1}]'
        entry=dict(batch_key='a'*64,ordinal=3,rows=1000,bytes=len(payload),capture_sha256=sha(payload))
        with self.assertRaisesRegex(ValueError,"SEQUENTIAL_ORDINAL"):
            s.build_one_batch_sql(entry,payload,2,2000)
        entry['ordinal']=2
        with self.assertRaisesRegex(ValueError,"SEQUENTIAL_PAYLOAD_HASH"):
            s.build_one_batch_sql(entry,payload+b'!',2,2000)
        with self.assertRaisesRegex(ValueError,"SEQUENTIAL_TOTAL"):
            s.build_one_batch_sql(entry,payload,2,1000)

    def test_preflight_one_found_resume(self):
        exact=dict(batches=479,manifest_digest_sha256='b'*64,source_sha256=['c'*64,'d'*64])
        state=dict(total=479,found=1,expected_done=1000,prefix_ok=True,unusual=0,
            enabled=True,pilot_scope='SEQUENTIAL_ALL_REMAINING_479',
            policy_manifest='b'*64,run_manifest='b'*64,policy_snapshots=['c'*64,'d'*64],
            source_enabled=True,operation_state='IN_PROGRESS',ingestas=1,reported=1000,companies=1000)
        with patch.object(s,'psql',return_value=state):
            self.assertEqual(s.database_prefix(exact),(1,1000))

    def test_preflight_reject_non_prefix_and_count_drift(self):
        exact=dict(batches=479,manifest_digest_sha256='b'*64,source_sha256=['c'*64,'d'*64])
        state=dict(total=479,found=2,expected_done=2000,prefix_ok=False,unusual=0,
            enabled=True,pilot_scope='SEQUENTIAL_ALL_REMAINING_479',
            policy_manifest='b'*64,run_manifest='b'*64,policy_snapshots=['c'*64,'d'*64],
            source_enabled=True,operation_state='IN_PROGRESS',ingestas=2,reported=2000,companies=2000)
        with patch.object(s,'psql',return_value=state):
            with self.assertRaisesRegex(ValueError,'SEQUENTIAL_PREFLIGHT_REJECTED'):
                s.database_prefix(exact)
            state['prefix_ok']=True
            state['companies']=1999
            with self.assertRaisesRegex(ValueError,'SEQUENTIAL_PREFLIGHT_REJECTED'):
                s.database_prefix(exact)


    def test_diagnostic_counts_only(self):
        from sunat_batch_plan_v1 import canonical
        c=dict(normalized=dict(ruc='20000000001',razon_social='Firma',workers_integer_literal=5),
               observations=dict(
                 monthly=dict(raw=dict(RUC='20000000001',NroTrab='5'),
                              evidence=dict(ordinal=1,zip_sha256='a')),
                 reduced=dict(raw=dict(RUC='20000000001',nombre='\u00a0Firma'),
                              evidence=dict(ordinal=1,zip_sha256='b'))))
        data=[dict(capture=c,capture_sha256=sha(canonical(c)))]
        result=s.safe_capture_diagnostic(canonical(data))
        self.assertEqual(result['name_trim'],1)
        self.assertEqual(result['capture_hash'],0)
        self.assertNotIn('Firma',str(result))

if __name__=='__main__':
    unittest.main()
