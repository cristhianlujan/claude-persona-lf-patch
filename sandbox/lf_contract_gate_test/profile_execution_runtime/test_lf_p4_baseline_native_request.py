"""P4 native Issue/OIDC typed baseline envelope: positive/negative without a real RUN."""
import json,os,runpy,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[3]
SCRIPT=ROOT/"scripts/lf_profile_native_resume.py"
class P4BaselineIssue(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup)
  self.path=Path(self.t.name)/"event.json"
  self.base={"schema_version":"LF_PROFILE_NATIVE_RESUME_REQUEST_V1",
    "execution_id":"EXEC-PROFILE-GATE2-ABCD1234567890EF"}
  self.envelope={"snapshot":{"approved":True},
    "baseline_digest":"sha256:"+"a"*64,"capture_stage":"C1",
    "input_digest":"sha256:"+"b"*64,
    "profile_source_digest":"sha256:"+"c"*64,
    "evidence_refs":["supabase://source/real"]}
  self.env={"LF_PROFILE_EDGE_URL":"https://invalid.test","LF_PROFILE_RESUME_REQUEST_MODE":"ISSUE",
    "GITHUB_EVENT_NAME":"issues","GITHUB_REPOSITORY":"test/lf","GITHUB_EVENT_PATH":str(self.path)}
  with patch.dict(os.environ,self.env,clear=False):
   self.fn=runpy.run_path(str(SCRIPT),run_name="p4_native_test")["governed_request"]
 def invoke(self,body):
  event={"action":"labeled","label":{"name":"lf-profile-resume-governed"},
         "issue":{"state":"open","repository_url":"https://api.github.com/repos/test/lf",
                   "body":json.dumps(body)}}
  self.path.write_text(json.dumps(event))
  with patch.dict(os.environ,self.env,clear=False):return self.fn()
 def test_positive_baseline_envelope_single_same_run(self):
  result=self.invoke({**self.base,"baseline_envelope":self.envelope})
  self.assertEqual(result["kind"],"BASELINE_CONTINUATION")
  self.assertEqual(result["execution_id"],self.base["execution_id"])
  self.assertEqual(result["baseline_envelope"],self.envelope)
 def test_negative_ambiguous_or_untyped_envelope(self):
  for extra in ({"baseline_envelope":None},{"baseline_envelope":[]},
                {"baseline_envelope":self.envelope,"profile_output":{"self_verdict":"PASS"}}):
   with self.subTest(extra=extra):
    with self.assertRaisesRegex(ValueError,"PROFILE_BASELINE_GOVERNED_REQUEST_INVALID"):
     self.invoke({**self.base,**extra})
if __name__=="__main__":unittest.main()
