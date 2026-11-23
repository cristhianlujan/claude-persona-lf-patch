import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'adapters'))
from sunat_verified_delivery_v1 import verified_candidate_payloads, _Staging, sha, canonical
import test_sunat_candidate_run_v1 as fixtures


class TestDelivery(unittest.TestCase):
    def setUp(self):
        f=fixtures.TestRun(); f.setUp(); self.addCleanup(f.doCleanups)
        self.f=f; self.prior=f.enable_plan()
        result=f.run_qa(); plan=result['batch_plan']
        self.expected=dict(state='CANDIDATE_PLAN_ONLY',qa_baseline_match=True,runtime_authorized=False,
            db_write_confirmed=False,rights_verified=False,rows=plan['rows'],batches=plan['batches'],
            total_bytes=plan['total_bytes'],batch_digest_sha256=plan['batch_digest_sha256'],
            manifest_digest_sha256=sha(canonical(plan['plan'])),source_sha256=plan['snapshot_sha256'],
            unique_batch_keys=plan['batches'],stats=result['stats'])

    def open(self):
        return verified_candidate_payloads(self.f.request,expected_manifest=self.expected,
            opener=self.f.opener,directory=self.f.dir.name)

    def clean(self):
        self.assertEqual(list(Path(self.f.dir.name).iterdir()),[])

    def test_exact_transport_reconciliation_and_cleanup(self):
        with self.open() as (receipt,stream):
            entries=list(stream)
            self.assertEqual([meta for meta,_ in entries],receipt['batch_plan']['plan'])
            self.assertEqual(sum(len(payload) for _,payload in entries),self.expected['total_bytes'])
            self.assertTrue(all(sha(payload)==meta['capture_sha256'] for meta,payload in entries))
            self.assertFalse(receipt['runtime_authorized'])
        self.clean()

    def test_wrong_manifest_no_delivery(self):
        self.expected['manifest_digest_sha256']='f'*64
        with self.assertRaisesRegex(ValueError,'^STAGE_MANIFEST_MISMATCH$'):
            with self.open(): self.fail('delivered')
        self.clean()

    def test_tamper_after_seal(self):
        with self.open() as (_,stream):
            stage_dir=next(Path(self.f.dir.name).iterdir())
            (stage_dir/'1').write_bytes(b'x')
            with self.assertRaisesRegex(ValueError,'^STAGE_HASH$'): next(stream)
        self.clean()

    def test_consumer_failure_cleanup(self):
        with self.assertRaisesRegex(RuntimeError,'consumer'):
            with self.open() as (_,stream):
                next(stream)
                raise RuntimeError('consumer')
        self.clean()

    def test_source_drift_no_delivery(self):
        key=self.f.request['sources']['reduced']['url']; self.f.data[key]+=b'x'
        with self.assertRaisesRegex(ValueError,'^SNAPSHOT_CHANGED$'):
            with self.open(): self.fail('delivered')
        self.clean()

    def test_quota_before_download(self):
        self.f.request['batch_plan']['limits']['max_total_bytes']=1
        self.f.opener.open.reset_mock()
        with self.assertRaisesRegex(ValueError,'^STAGE_EXPECTED_LIMITS$'):
            with self.open(): self.fail('delivered')
        self.f.opener.open.assert_not_called(); self.clean()

    def test_unsealed_staging_never_delivers(self):
        stage=_Staging(self.f.dir.name,dict(max_bytes=10,max_batches=1,max_total_bytes=10))
        stage.append(b'[]')
        with self.assertRaisesRegex(ValueError,'^STAGE_NOT_VERIFIED$'): next(stage.iter_verified())

if __name__=='__main__': unittest.main()
