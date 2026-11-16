"""E21 source-bound IG Validator response contracts and native retry semantics.
Runs under both pytest and the repository's unittest R17 discovery.
All external Edge/SQL calls are explicit in-memory fakes; no profile RUN created.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from datetime import datetime,timezone,timedelta
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[3]
os.environ.setdefault("LF_PROFILE_EDGE_URL","https://test.invalid")
SPEC=importlib.util.spec_from_file_location("e21_ig_resume",ROOT/"scripts/lf_profile_native_resume.py")
MODULE=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
VALID=MODULE.is_direct_validator_continuation
RUN="EXEC-PROFILE-GATE2-"+"B"*24
SKILL="INPUT_GOVERNANCE_CONTEXT_PACK"

def validator_response(code="SKILL_RUNTIME_VALIDATOR_RESUME_REQUIRED",screen=51):
    return {
       "outcome":"CONTINUATION_REQUIRED","code":code,
       "execution_id":RUN,"skill_code":SKILL,"pantalla_id":screen,
       "consumer":"CONTEXT_PACK","transport":"DIRECT_EDGE_INVOCATION",
       "queue_required":False,"polling_required":False,
       "result":{"status":"VALIDATOR_RESUME_REQUIRED"}}

class E21IGValidatorTransport(unittest.TestCase):
    def test_skill_and_ig_real_202_contracts(self):
        for code in ("SKILL_RUNTIME_VALIDATOR_RESUME_REQUIRED",
                     "IG_CONTEXT_PACK_VALIDATOR_RESUME_REQUIRED"):
            self.assertTrue(VALID(202,validator_response(code),
                execution_id=RUN,pantalla_id=51,skill_code=SKILL),code)
            nested=validator_response(code)
            nested["result"]={"result":{"status":"VALIDATOR_RESUME_REQUIRED"}}
            self.assertTrue(VALID(202,nested,
                execution_id=RUN,pantalla_id=51,skill_code=SKILL),code)

    def test_foreign_screen_identity_queue_and_result_rejected(self):
        ok=validator_response()
        negatives=[
            (202,{**ok,"pantalla_id":52}),
            (202,{**ok,"execution_id":"EXEC-PROFILE-GATE2-OTHER"}),
            (202,{**ok,"skill_code":"OTHER_SKILL"}),
            (202,{**ok,"queue_required":True}),
            (202,{**ok,"transport":"QUEUED"}),
            (202,{**ok,"result":{"status":"READY"}}),
            (202,{**ok,"code":"UNVERIFIED_RESPONSE"}),
            (409,ok),
        ]
        for http,payload in negatives:
            with self.subTest(http=http,payload=payload):
                self.assertFalse(VALID(http,payload,
                    execution_id=RUN,pantalla_id=51,skill_code=SKILL))
        ig=validator_response("IG_CONTEXT_PACK_VALIDATOR_RESUME_REQUIRED")
        self.assertFalse(VALID(202,ig,execution_id=RUN,pantalla_id=None,skill_code=SKILL))

    def test_valid_validator_continuation_does_not_consume_error_budget(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            file=root/"profiles"/"test_profile"/"SKILL.md"
            file.parent.mkdir(parents=True)
            file.write_text("# Verified profile source\n",encoding="utf-8")
            expiry=(datetime.now(timezone.utc)+timedelta(minutes=3)).isoformat()
            calls=[]
            prepare_count=0
            worker_count=0

            def fake_call(_url,data,_headers):
                nonlocal prepare_count,worker_count
                calls.append(data["action"])
                if data["action"]=="profile_native_source_bind_v1":
                    return 200,{"outcome":"SOURCE_BINDING_REQUIRED","execution_id":RUN,
                        "profile_code":"PERFIL-TEST",
                        "target_repo":"test-owner/test-repo",
                        "target_path":"profiles/test_profile/SKILL.md",
                        "source_revision_required":"a"*40,
                        "operation_plan":{"status":"READY",
                            "operation_code":"EJECUCION_PERFIL_LF",
                            "profile_code":"PERFIL-TEST",
                            "steps":[{"step_order":i,"step_id":"step_"+str(i)}
                                     for i in range(11)],"skills":[]}}
                if data["action"]=="profile_native_continue_v1":
                    prepare_count+=1
                    if prepare_count<=3:
                        return 200,{"outcome":"CONTINUATION_REQUIRED",
                            "phase":"SKILL_RUNTIME_REQUIRED","execution_id":RUN,
                            "result":{"skill_code":SKILL,
                              "input_governance_runtime_request":{
                                 "transport":"DIRECT_EDGE_INVOCATION",
                                 "queue_required":False,"polling_required":False,
                                 "ticket_expires_at":expiry,
                                 "request_headers":{"X-LF-Profile-Runtime-Ticket":
                                     "11111111-1111-4111-8111-111111111111"},
                                 "request_body":{"action":"profile_skill_runtime_v1",
                                     "execution_id":RUN,"skill_code":SKILL,"pantalla_id":51}}}}
                    return 200,{"outcome":"CONTINUATION_REQUIRED",
                        "phase":"NATIVE_MODEL_INPUT_READY","execution_id":RUN,
                        "profile_code":"PERFIL-TEST"}
                if data["action"]=="profile_skill_runtime_v1":
                    worker_count+=1
                    if worker_count==1:return 202,validator_response()
                    return 409,{"outcome":"BLOCKED",
                        "code":"SKILL_RUNTIME_NON_TERMINAL_AS_FINDING",
                        "execution_id":RUN,"pantalla_id":51}
                raise AssertionError("UNEXPECTED_ACTION:"+data["action"])

            env={"LF_PROFILE_EDGE_URL":"https://test.invalid",
                 "GITHUB_SHA":"a"*40,"GITHUB_REPOSITORY":"test-owner/test-repo",
                 "GITHUB_RUN_ID":"54321"}
            with patch.dict(os.environ,env,clear=False),\
                 patch("pathlib.Path.cwd",return_value=root),\
                 patch("time.sleep",return_value=None):
                main=MODULE.main
                with patch.dict(main.__globals__,{
                    "governed_request":lambda:(RUN,"",None,None),
                    "oidc":lambda:"opaque-test-only",
                    "call_json":fake_call}):
                    rc=main()
            self.assertEqual(rc,1) # The REAL Step50 RAW is not provided by the fixture.
            self.assertEqual(worker_count,3,
                "One validator 202 plus two errors; validator continuation is NOT a retry")
            self.assertEqual(prepare_count,4)
            checkpoint=json.loads((root/"profile-native-continuation.json").read_text())
            self.assertEqual(checkpoint["next_step"],"execute_profile")
            self.assertFalse(checkpoint["last_run_completed"])

if __name__=="__main__":
    unittest.main()
