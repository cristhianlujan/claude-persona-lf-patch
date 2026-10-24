from __future__ import annotations
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient
from profile_runtime_api.app import create_app
from profile_runtime_api.hashing import canonical_json_sha256
from profile_runtime_api.models import ExecuteRequest
from profile_runtime_api.settings import Settings
from tests import test_api as api_tests


class CompletionAPITest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.release=threading.Event()
        self.engine=api_tests.FakeAPIEngine();self.callback=lambda notice:None
        self.settings=Settings(repo_root=Path(__file__).resolve().parents[3],state_dir=Path(self.tmp.name),api_token="test",source_sha="a"*40,max_workers=1)
        self.ctx=TestClient(create_app(self.settings,engine_factory=lambda _:self.engine,completion_observer=lambda notice:self.callback(notice)))
        self.client=self.ctx.__enter__();self.auth={"Authorization":"Bearer test"}

    def tearDown(self):
        self.release.set()
        for t in threading.enumerate():
            if t.name=="lf-completion-observation":t.join(3)
        self.ctx.__exit__(None,None,None);self.tmp.cleanup()

    def post(self,request_id):
        response=self.client.post("/v1/profile/execute",headers=self.auth,json=api_tests.APITest.payload(request_id))
        self.assertEqual(response.status_code,202);return response.json()

    def completed(self,accepted):
        for _ in range(100):
            job=self.client.get(accepted["status_url"],headers=self.auth).json()
            if job["status"] in {"COMPLETED","FAILED"}:return job
            time.sleep(.01)
        self.fail("job did not finish")

    def test_completion_precedes_observer_failure_and_duplicate_does_not_repeat(self):
        seen=[];done=threading.Event()
        def callback(notice):
            stored=self.client.get("/v1/jobs/"+notice["job_id"],headers=self.auth).json()
            seen.append((notice,stored));done.set();raise RuntimeError("synthetic observer error")
        self.callback=callback
        accepted=self.post("completion-first");job=self.completed(accepted);self.assertTrue(done.wait(2))
        self.assertEqual(seen[0][1]["status"],"COMPLETED")
        self.assertEqual(job["result"],{"kind":"execute","request_id":"completion-first","downstream_authorized":False})
        self.assertIsNone(job["error"])
        self.assertTrue(self.post("completion-first")["reused"])
        self.assertEqual(len(seen),1)
        self.assertEqual(self.completed(accepted)["result"],job["result"])

    def test_blocked_observers_do_not_occupy_single_job_worker(self):
        started=threading.Event();seen=[]
        def callback(notice):seen.append(notice);started.set();self.release.wait(3)
        self.callback=callback
        first=self.post("slow-one");self.assertTrue(started.wait(1))
        second=self.post("slow-two");third=self.post("capacity-three")
        for accepted in (first,second,third):self.assertEqual(self.completed(accepted)["status"],"COMPLETED")
        self.assertLessEqual(len(seen),2)

    def test_base_failure_remains_failed_and_never_observed(self):
        seen=[];self.callback=seen.append
        def fail(_):raise RuntimeError("base-engine-failure")
        self.engine.run_execute=fail
        job=self.completed(self.post("base-failure"));self.assertEqual(job["status"],"FAILED")
        self.assertEqual(job["error"]["code"],"UNEXPECTED_JOB_FAILURE");self.assertEqual(seen,[])

    def test_dispatch_failure_cannot_fail_completed_job(self):
        with patch("profile_runtime_api.app.CompletionObservation.submit",side_effect=RuntimeError("dispatch")):
            job=self.completed(self.post("dispatch-failure"))
        self.assertEqual(job["status"],"COMPLETED");self.assertIsNone(job["error"])

    def test_full_api_to_bound_ro_caller_unknown_preserves_result(self):
        from analysis_a6_a9_ro_transport_v1 import A6A9CompletionObserver, CompletionBinding, PROFILE
        from analysis_a6_a9_readonly_caller_v1 import ExpectedContext, READ_SQL
        payload=api_tests.APITest.payload("bound-ro")
        payload["profile"].update(profile_code=PROFILE,profile_slug="programming_analysis_lf",profile_source_paths=["profiles/programming_analysis_lf/SKILL.md"])
        rendered=ExecuteRequest.model_validate(payload).model_dump(mode="json",by_alias=True)
        expected=ExpectedContext("PROGRAMMING_AGENT","subject://test","2026-10-24T00:00:00Z","11111111-1111-4111-8111-111111111111","a"*64)
        reads=[];done=threading.Event()
        def read(sql,params):
            reads.append((sql,params));return {"resolution":{"schema_version":"LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1","state":"UNKNOWN"},"transaction_read_only":True}
        observer=A6A9CompletionObserver(read,enabled=True,bindings=(CompletionBinding("bound-ro",canonical_json_sha256(rendered),"execute",expected),))
        def callback(notice):observer(notice);done.set()
        self.callback=callback
        accepted=self.client.post("/v1/profile/execute",headers=self.auth,json=payload).json()
        job=self.completed(accepted);self.assertTrue(done.wait(2))
        self.assertEqual(job["status"],"COMPLETED");self.assertEqual(job["result"]["request_id"],"bound-ro")
        self.assertEqual(reads,[(READ_SQL,(expected.consumer_code,expected.subject_ref,expected.as_of))])
        self.assertEqual(observer.diagnostics()[0]["state"],"SKIPPED_NO_CONTEXT")

if __name__=="__main__":unittest.main()
