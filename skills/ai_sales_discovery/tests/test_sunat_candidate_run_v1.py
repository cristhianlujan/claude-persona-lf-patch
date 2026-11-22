import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'adapters'))
import test_sunat_dual_stream_v1 as fixtures
from sunat_candidate_run_v1 import run_candidate_qa

class Response(io.BytesIO):
    status=200
    def __init__(self,data,url):
        super().__init__(data); self.url=url; self.headers={'Content-Length':str(len(data))}
    def geturl(self): return self.url

class TestRun(unittest.TestCase):
    def setUp(self):
        f=fixtures.TestDual(); f.setUp(); self.addCleanup(f.doCleanups)
        m,r=f.sources()
        self.data={s['url']:Path(s['path']).read_bytes() for s in (m,r)}
        self.request=dict(mode='PINNED_QA_ONLY',evidence_ref='fixture',departments=['15','11'],
            sources={k:{p:s[p] for p in ('url','zip_sha256','header_sha256')} for k,s in (('monthly',m),('reduced',r))},
            limits=f.limits,transport=dict(attempts=2,socket_timeout=1,deadline_seconds=5,backoff_seconds=1,total_seconds=30),
            expected=dict(rows=2,monthly_rows=6,monthly_selected=5,reduced_rows=6))
        self.dir=tempfile.TemporaryDirectory(); self.addCleanup(self.dir.cleanup)
        self.opener=Mock(); self.opener.open.side_effect=lambda req,timeout:Response(self.data[req.full_url],req.full_url)
    def run_qa(self): return run_candidate_qa(self.request,opener=self.opener,directory=self.dir.name)
    def test_real_transport_to_join_fixture(self):
        r=self.run_qa(); self.assertTrue(r['qa_baseline_match']); self.assertEqual(r['rows'],2)
        self.assertFalse(r['db_write_confirmed']); self.assertFalse(r['rights_verified']); self.assertFalse(r['runtime_authorized'])
        self.assertEqual(self.opener.open.call_count,2); self.assertEqual(list(Path(self.dir.name).iterdir()),[])
        self.assertEqual(r,self.run_qa())
    def test_changed_snapshot_blocks_and_cleans(self):
        r=self.request['sources']['reduced']; self.data[r['url']]+=b'x'
        with self.assertRaisesRegex(ValueError,'^SNAPSHOT_CHANGED$'): self.run_qa()
        self.assertEqual(list(Path(self.dir.name).iterdir()),[])
    def test_baseline_mismatch(self):
        self.request['expected']['rows']=3
        with self.assertRaisesRegex(ValueError,'^BASELINE_MISMATCH$'): self.run_qa()
        self.assertEqual(list(Path(self.dir.name).iterdir()),[])
    def test_preflight_blocks_before_http(self):
        self.request['mode']='PRODUCTION'
        with self.assertRaisesRegex(ValueError,'^QA_MODE$'): self.run_qa()
        self.request['mode']='PINNED_QA_ONLY'; self.request['sources']['reduced']['url']='https://invalid.example/file.zip'
        with self.assertRaisesRegex(ValueError,'^SOURCE_URL$'): self.run_qa()
        self.opener.open.assert_not_called()

if __name__=='__main__': unittest.main()
