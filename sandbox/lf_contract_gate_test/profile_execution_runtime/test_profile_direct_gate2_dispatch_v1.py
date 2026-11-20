"""No-manual-Issue LF Gate2 -> existing OIDC native RUN entry.

Transport contract tests: admission and execution remain owned by the
canonical Edge/SQL source, never the Python parser.
"""
import json
import os
import runpy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[3]
RUNNER=ROOT/"scripts/lf_profile_native_resume.py"
WORKFLOW=ROOT/".github/workflows/lf-edge-deploy-credential-readback.yml"

class DirectGate2Dispatch(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.event_path=Path(self.tmp.name)/"event.json"
        self.context={
          "schema_version":"LF_ROUTER_EXECUTION_PIPELINE_V1",
          "status":"GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
          "transport_mode":"CONTEXT_TRANSPORT",
          "next_step":"HANDOFF_CONTEXT_TO_SELECTED_PROFILE",
          "effect_authority":False,
          "downstream_execution_allowed":False,
          "selected_profile_code":"PERFIL-PRODUCT-DIRECTOR-LF",
          "router_authorization_receipt":{"source":"fixture-no-credentials"},
        }
        self.raw=json.dumps(self.context,ensure_ascii=False,separators=(",",":"))
        self.event={"inputs":{"action":"begin-native-profile",
                      "router_context_json":self.raw,"execution_id":""}}
        self.env={
           "LF_PROFILE_RESUME_REQUEST_MODE":"DISPATCH_BEGIN",
           "GITHUB_EVENT_NAME":"workflow_dispatch",
           "GITHUB_REF":"refs/heads/main",
           "GITHUB_REPOSITORY":"cristhianlujan/claude-persona-lf-patch",
           "GITHUB_EVENT_PATH":str(self.event_path),
           "PROFILE_ROUTER_GATE2_JSON":self.raw,
           "PROFILE_EXECUTION_ID":"",
        }
        with patch.dict(os.environ,{"LF_PROFILE_EDGE_URL":"https://example.invalid/functions/v1/caller"},clear=False):
            self.fn=runpy.run_path(str(RUNNER),run_name="test_direct_entry")["governed_request"]

    def invoke(self):
        self.event_path.write_text(json.dumps(self.event),encoding="utf8")
        with patch.dict(os.environ,self.env,clear=True):
            return self.fn()

    def test_direct_request_preserves_full_gate2_unchanged_without_issue(self):
        out=self.invoke()
        self.assertEqual(out,{"kind":"BEGIN","router_context":self.context,
                              "executor_mode":"GPT_NATIVE"})
        self.assertNotIn("issue",self.event)
        workflow=WORKFLOW.read_text(encoding="utf8")
        self.assertIn("- begin-native-profile",workflow)
        self.assertIn("PROFILE_ROUTER_GATE2_JSON: "+"$"+"{{ inputs.router_context_json }}",workflow)
        self.assertIn("id-token: write",workflow)
        self.assertIn("lf-profile-resume-governed",workflow)
        source=RUNNER.read_text(encoding="utf8")
        self.assertIn('"action":"profile_native_begin_from_context_v1"',source)
        self.assertIn('request["router_context"]',source)
        self.assertNotIn("service_role",self.raw)

    def test_event_input_mismatch_rejected(self):
        self.event["inputs"]["router_context_json"]="{}"
        with self.assertRaisesRegex(ValueError,"SOURCE_BINDING_INVALID"):
            self.invoke()

    def test_missing_gate2_rejected(self):
        self.context["status"]="PROFILE_SELECTION_READY"
        self.raw=json.dumps(self.context)
        self.env["PROFILE_ROUTER_GATE2_JSON"]=self.raw
        self.event["inputs"]["router_context_json"]=self.raw
        with self.assertRaisesRegex(ValueError,"CONTRACT_INVALID"):
            self.invoke()

    def test_no_off_main_dispatch(self):
        self.env["GITHUB_REF"]="refs/heads/test"
        with self.assertRaisesRegex(ValueError,"MAIN_ONLY"):self.invoke()

    def test_no_external_run_id_from_dispatch(self):
        self.env["PROFILE_EXECUTION_ID"]="EXEC-PROFILE-GATE2-UNTRUSTED"
        with self.assertRaisesRegex(ValueError,"ACTION_OR_RUN_INVALID"):self.invoke()

    def test_no_issue_path_masquerading_as_dispatch(self):
        self.env["GITHUB_EVENT_NAME"]="issues"
        with self.assertRaisesRegex(ValueError,"EVENT_INVALID"):self.invoke()

    def test_no_unrecognized_dispatch_action(self):
        self.event["inputs"]["action"]="deploy-caller"
        with self.assertRaisesRegex(ValueError,"ACTION_OR_RUN_INVALID"):self.invoke()

if __name__=="__main__":unittest.main()
