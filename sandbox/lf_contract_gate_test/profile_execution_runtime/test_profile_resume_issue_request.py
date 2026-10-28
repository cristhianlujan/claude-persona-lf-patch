import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "lf_profile_native_resume.py"
SCHEMA = "LF_PROFILE_NATIVE_RESUME_REQUEST_V1"
LABEL = "lf-profile-resume-governed"


class NativeProfileIssueRequestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.event_path = Path(self.tmp.name) / "event.json"
        self.event = {
            "action": "labeled",
            "label": {"name": LABEL},
            "issue": {
                "state": "open",
                "repository_url": "https://api.github.com/repos/test-owner/test-repo",
                "body": json.dumps({"schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE"}),
            },
        }
        self.env = {
            "LF_PROFILE_EDGE_URL": "https://example.supabase.co/functions/v1/example",
            "LF_PROFILE_RESUME_REQUEST_MODE": "ISSUE",
            "GITHUB_EVENT_NAME": "issues",
            "GITHUB_REPOSITORY": "test-owner/test-repo",
            "GITHUB_EVENT_PATH": str(self.event_path),
            "PROFILE_EXECUTION_ID": "",
        }
        with patch.dict(os.environ, self.env, clear=True):
            self.get_request = runpy.run_path(str(SCRIPT), run_name="native_resume_test")["governed_request"]

    def check(self):
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        with patch.dict(os.environ, self.env, clear=True):
            return self.get_request()

    def test_valid_issue_payload(self):
        self.assertEqual(self.check(), ("EXEC-PROFILE-GATE2-EXAMPLE", ""))

    def test_semantic_decision_passed_as_data(self):
        decision = {"decision": "SELECTED", "selected_screen_code": "NOT_HARDCODED"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE",
            "screen_selection_draft": decision,
        })
        raw_id, raw_draft = self.check()
        self.assertEqual(raw_id, "EXEC-PROFILE-GATE2-EXAMPLE")
        self.assertEqual(json.loads(raw_draft), decision)

    def test_reject_wrong_label_or_event(self):
        for update in ({"label": {"name": "not-governed"}},
                       {"action": "opened"},
                       {"issue": {**self.event["issue"], "state": "closed"}},
                       {"issue": {**self.event["issue"], "repository_url": "https://api.github.com/repos/foreign/repo"}}):
            old = self.event.copy()
            try:
                self.event.update(update)
                with self.assertRaises(ValueError):
                    self.check()
            finally:
                self.event = old

    def test_reject_unrecognized_fields(self):
        body = json.loads(self.event["issue"]["body"])
        body["profile_code"] = "HARDCODE_ATTEMPT"
        self.event["issue"]["body"] = json.dumps(body)
        with self.assertRaises(ValueError):
            self.check()

    def test_reject_invalid_schema_and_draft(self):
        for bad in [
            {"schema_version": "V0", "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE"},
            {"schema_version": SCHEMA, "execution_id": 123},
            {"schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE", "screen_selection_draft": "AUTO"},
        ]:
            self.event["issue"]["body"] = json.dumps(bad)
            with self.assertRaises(ValueError):
                self.check()


if __name__ == "__main__":
    unittest.main()
