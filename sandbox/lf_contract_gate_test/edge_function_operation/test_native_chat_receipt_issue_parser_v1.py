"""Contract: same governed Issue/OIDC lane, no caller nonce/SHA/role."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[3]
os.environ.setdefault("LF_PROFILE_EDGE_URL","https://test-only.invalid")
spec=importlib.util.spec_from_file_location("governed_native_receiver",ROOT/"scripts/lf_profile_native_resume.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
RUN="EXEC-PROFILE-GATE2-100EAF5F03DA504596AC0706"
REPO="cristhianlujan/claude-persona-lf-patch"
KIND="LF_NATIVE_CHAT_RECEIPT_APPEND_REQUEST_V1"
def message(kind,event):
    return {"schema_version":KIND,"execution_id":RUN,"kind":kind,"event":event}

class IssueInputOnly(unittest.TestCase):
    def parse(self,body):
        event={"action":"labeled","label":{"name":"lf-profile-resume-governed"},
               "issue":{"state":"open","repository_url":"https://api.github.com/repos/"+REPO,
                        "body":json.dumps(body,ensure_ascii=False)}}
        with tempfile.TemporaryDirectory() as tmp:
            file=Path(tmp)/"event.json"
            file.write_text(json.dumps(event),encoding="utf8")
            with patch.dict(os.environ,{"LF_PROFILE_RESUME_REQUEST_MODE":"ISSUE",
                       "GITHUB_EVENT_NAME":"issues","GITHUB_EVENT_PATH":str(file),
                       "GITHUB_REPOSITORY":REPO}):
                return mod.governed_request()

    def test_request_is_empty_and_nonce_is_db_owned(self):
        r=self.parse(message("REQUEST",{}))
        self.assertEqual(r["kind"],"NATIVE_CHAT_RECEIPT_APPEND")
        self.assertEqual(r["receipt_kind"],"REQUEST")
        self.assertEqual(r["event"],{})
        for extra in ({"nonce":"fake"},{"candidate_sha256":"a"*64},
                      {"frozen_bundle_sha256":"a"*64}):
            with self.subTest(extra=extra),self.assertRaises(ValueError):
                self.parse(message("REQUEST",extra))

    def test_executor_requires_true_original_fields(self):
        r=self.parse(message("EXECUTOR",{
            "executor_context_ref":"actions://verified/sandbox/workflow",
            "producer_schema_id":"SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6",
            "producer_eval_id":"PROFILE_OUTPUT_VALIDATION_RESULT_V1",
            "producer_profile_id":"PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        }))
        self.assertEqual(r["receipt_kind"],"EXECUTOR")
        with self.assertRaises(ValueError):
            self.parse(message("EXECUTOR",{"producer_schema_id":"UNKNOWN"}))

    def test_judge_requires_actual_raw_eval_not_placeholder(self):
        with self.assertRaises(ValueError):
            self.parse(message("JUDGE",{"review_mode":"INDEPENDENT_EVAL_CONTEXT"}))
        with self.assertRaises(ValueError):
            self.parse(message("JUDGE",{
                "review_mode":"INDEPENDENT_EVAL_CONTEXT",
                "reviewer_context_ref":"context://other",
                "reviewer_schema_id":"LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1",
                "reviewer_eval_id":"LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1",
                "reviewer_profile_id":"PERFIL-QUALITY-PACK",
                "reviewer_context_cleared":True,
                "eval_status":"PASS","review_payload":{},
                "nonce":"forged",
            }))

if __name__=="__main__":unittest.main()
