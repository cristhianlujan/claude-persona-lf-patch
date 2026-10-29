import json
import os
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "lf_profile_router_admit.py"
CTX = {
    "schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
    "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
    "transport_mode": "CONTEXT_TRANSPORT",
}


class RouterAdmitRequestTest(unittest.TestCase):
    def run_request(self, context, mode):
        env = {"ROUTER_CONTEXT_JSON": context if isinstance(context, str) else json.dumps(context),
               "EXECUTOR_MODE": mode}
        with patch.dict(os.environ, env, clear=True):
            return runpy.run_path(str(SCRIPT), run_name="admit_test")["governed_request"]()

    def test_both_native_modes_accepted(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            self.assertEqual(self.run_request(CTX, mode), (CTX, mode))

    def test_remote_and_unknown_modes_rejected(self):
        for mode in ("REMOTE_API", "", "claude_native", "OTHER"):
            with self.assertRaises(ValueError):
                self.run_request(CTX, mode)

    def test_bad_envelopes_rejected(self):
        for key, value in (("schema_version", "X"), ("status", "READY"), ("transport_mode", "READ_ONLY_CONTEXT")):
            with self.assertRaises(ValueError):
                self.run_request({**CTX, key: value}, "CLAUDE_NATIVE")

    def test_non_object_empty_and_oversize_rejected(self):
        for raw in ("[]", "", json.dumps({**CTX, "pad": "x" * 61000})):
            with self.assertRaises(ValueError):
                self.run_request(raw, "CLAUDE_NATIVE")


class RouterAdmitIssueTest(unittest.TestCase):
    LABEL = "lf-profile-admit-governed"

    def issue_request(self, body=None, label=None, state="open", pr=None, repo_url=None):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "event.json"
            payload = {"schema_version": "LF_PROFILE_ROUTER_ADMIT_REQUEST_V1",
                       "router_context": CTX, "executor_mode": "CLAUDE_NATIVE"}
            event = {"action": "labeled", "label": {"name": label or self.LABEL},
                     "issue": {"state": state, "pull_request": pr,
                               "repository_url": repo_url or "https://api.github.com/repos/o/r",
                               "body": json.dumps(payload) if body is None else body}}
            path.write_text(json.dumps(event), encoding="utf-8")
            env = {"LF_PROFILE_ADMIT_REQUEST_MODE": "ISSUE", "GITHUB_EVENT_NAME": "issues",
                   "GITHUB_REPOSITORY": "o/r", "GITHUB_EVENT_PATH": str(path)}
            with patch.dict(os.environ, env, clear=True):
                return runpy.run_path(str(SCRIPT), run_name="admit_issue_test")["governed_request"]()

    def test_valid_issue(self):
        self.assertEqual(self.issue_request(), (CTX, "CLAUDE_NATIVE"))

    def test_wrong_label_state_pr_or_repo_rejected(self):
        for kw in ({"label": "other"}, {"state": "closed"}, {"pr": {}}, {"repo_url": "https://api.github.com/repos/x/y"}):
            with self.assertRaises(ValueError):
                self.issue_request(**kw)

    def test_bad_body_rejected(self):
        for body in ("not json", "[]", json.dumps({"schema_version": "X"}),
                     json.dumps({"schema_version": "LF_PROFILE_ROUTER_ADMIT_REQUEST_V1",
                                 "router_context": CTX, "executor_mode": "REMOTE_API"}),
                     json.dumps({"schema_version": "LF_PROFILE_ROUTER_ADMIT_REQUEST_V1",
                                 "router_context": CTX, "executor_mode": "CLAUDE_NATIVE", "extra": 1})):
            with self.assertRaises((ValueError, json.JSONDecodeError)):
                self.issue_request(body=body)


if __name__ == "__main__":
    unittest.main()
