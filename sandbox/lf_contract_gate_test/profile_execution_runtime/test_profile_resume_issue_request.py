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
            mod = runpy.run_path(str(SCRIPT), run_name="native_resume_test")
            self.get_request = mod["governed_request"]
            self.validator_continuation = mod["is_direct_validator_continuation"]

    def check(self):
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        with patch.dict(os.environ, self.env, clear=True):
            return self.get_request()

    def test_valid_issue_payload(self):
        self.assertEqual(self.check(), ("EXEC-PROFILE-GATE2-EXAMPLE", "", None, None))

    def test_router_profile_entry_is_v2_and_not_generic_asset_lookup(self):
        """Prevent reintroducing the wrong V1 asset resolver for profile execution."""
        root = SCRIPT.parents[1]
        agent = (root / "AGENTS.md").read_text(encoding="utf-8")
        claude = (root / "CLAUDE.md").read_text(encoding="utf-8")
        compact = (root / "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md").read_text(encoding="utf-8")
        historical = (root / "docs/programming-agent/LF_ROUTER_FLOW_V1.md").read_text(encoding="utf-8")
        for doc in (agent, claude, compact):
            self.assertIn("lf_router_pipeline_context_begin_v2", doc)
            self.assertIn("EJECUCION_PERFIL_LF", doc)
            self.assertIn("lf_router_resolve_v1", doc)
            self.assertIn("HANDOFF_CONTEXT_TO_SELECTED_PROFILE", doc)
        self.assertIn("Do **not** run `lf_router_resolve_v1` first", agent)
        self.assertIn("Do not call `lf_router_resolve_v1` first", claude)
        self.assertNotIn("Toda resolución entra por `public.lf_router_resolve_v1`", compact)
        self.assertIn("No es la entrada de `EJECUCION_PERFIL_LF`", compact)
        self.assertIn("Referencia histórica", historical)
        self.assertIn("LF_PROFILE_NATIVE_BEGIN_REQUEST_V1", claude)
        self.assertIn("lf-profile-resume-governed", claude)

    def test_profile_owned_begin_uses_existing_governed_issue_label(self):
        context = {"schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
                   "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
                   "transport_mode": "CONTEXT_TRANSPORT",
                   "stage1_payload": {"texto_original": "Login B2B"}}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": "LF_PROFILE_NATIVE_BEGIN_REQUEST_V1",
            "router_context": context, "executor_mode": "GPT_NATIVE"})
        self.assertEqual(self.check(), {
            "kind": "BEGIN", "router_context": context, "executor_mode": "GPT_NATIVE"})

    def test_profile_begin_calls_only_native_writer_then_source_bind(self):
        context = {"schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
                   "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
                   "transport_mode": "CONTEXT_TRANSPORT"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": "LF_PROFILE_NATIVE_BEGIN_REQUEST_V1",
            "router_context": context, "executor_mode": "GPT_NATIVE"})
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        with patch.dict(os.environ, {**self.env, "GITHUB_SHA": "a" * 40}, clear=True):
            m = runpy.run_path(str(SCRIPT), run_name="native_begin_test")
            main = m["main"]
            calls = []
            def fake_call(url, body, headers):
                calls.append(body["action"])
                if body["action"] == "profile_native_begin_from_context_v1":
                    self.assertEqual(body["context"], context)
                    return 200, {"outcome": "NATIVE_EXECUTION_READY", "result": {
                        "status": "NATIVE_EXECUTION_READY",
                        "execution_id": "EXEC-PROFILE-GATE2-" + "A" * 24,
                        "profile_code": "PERFIL-PRODUCT-DIRECTOR-LF"}}
                return 403, {"outcome": "BLOCKED", "code": "TEST_STOP_AFTER_SOURCE_BIND"}
            with patch.dict(main.__globals__, {
                "oidc": lambda: "test-oidc-token",
                "call_json": fake_call,
            }):
                self.assertEqual(main(), 1)
            self.assertEqual(calls, [
                "profile_native_begin_from_context_v1",
                "profile_native_source_bind_v1",
            ])

    def test_begin_rejects_role_secret_mode_or_context_bypass(self):
        context = {"schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
                   "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
                   "transport_mode": "CONTEXT_TRANSPORT"}
        valid = {"schema_version": "LF_PROFILE_NATIVE_BEGIN_REQUEST_V1",
                 "router_context": context, "executor_mode": "GPT_NATIVE"}
        for bad in [
            {**valid, "service_role": "injected-secret"},
            {**valid, "service_role_key": "injected-secret"},
            {**valid, "executor_mode": "REMOTE_API"},
            {**valid, "router_context": {**context, "status": "READY"}},
            {**valid, "router_context": {"schema_version": "WRONG"}},
            {**valid, "router_context": "untrusted"},
        ]:
            self.event["issue"]["body"] = json.dumps(bad)
            with self.assertRaises(ValueError):
                self.check()

    def test_exact_platform_footer_allowed_other_trailing_data_rejected(self):
        payload = json.dumps({"schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE"})
        footer = "\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_"
        self.event["issue"]["body"] = payload + footer
        self.assertEqual(self.check(), ("EXEC-PROFILE-GATE2-EXAMPLE", "", None, None))
        for tail in ("\nextra", "\n\n---\n_Generated by [Other](https://evil.example)_", footer + "\nmore"):
            self.event["issue"]["body"] = payload + tail
            with self.assertRaises(ValueError):
                self.check()

    def test_semantic_decision_passed_as_data(self):
        decision = {"decision": "SELECTED", "selected_screen_code": "NOT_HARDCODED"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE",
            "screen_selection_draft": decision,
        })
        raw_id, raw_draft, raw_output, semantic_review = self.check()
        self.assertEqual(raw_id, "EXEC-PROFILE-GATE2-EXAMPLE")
        self.assertEqual(json.loads(raw_draft), decision)
        self.assertIsNone(raw_output)
        self.assertIsNone(semantic_review)

    def test_profile_output_passed_as_untrusted_raw_only(self):
        output = {"worker": "product_director_lf", "traceability": {"ig_open_work_resolution": []}}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA,
            "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE",
            "profile_output": output,
        })
        raw_id, raw_draft, raw_output, semantic_review = self.check()
        self.assertEqual(raw_id, "EXEC-PROFILE-GATE2-EXAMPLE")
        self.assertEqual(raw_draft, "")
        self.assertEqual(raw_output, output)
        self.assertIsNone(semantic_review)

    def test_semantic_review_passed_as_separate_untrusted_data(self):
        review = {"verdict": "PASS_INDEPENDENT_SEMANTIC"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA,
            "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE",
            "semantic_judge_review": review,
        })
        raw_id, raw_draft, raw_output, semantic_review = self.check()
        self.assertEqual(raw_id, "EXEC-PROFILE-GATE2-EXAMPLE")
        self.assertEqual(raw_draft, "")
        self.assertIsNone(raw_output)
        self.assertEqual(semantic_review, review)

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
            {"schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE", "profile_output": "SELF_ASSERTED_PASS"},
            {"schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE", "semantic_judge_review": "SELF_ASSERTED_PASS"},
        ]:
            self.event["issue"]["body"] = json.dumps(bad)
            with self.assertRaises(ValueError):
                self.check()

    def test_incomplete_semantic_checkpoint_is_not_success_or_new_authorization(self):
        with patch.dict(os.environ, self.env, clear=True):
            module = runpy.run_path(str(SCRIPT), run_name="continuation_checkpoint_test")
            with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
                code = module["record_incomplete_continuation"](
                    "EXEC-PROFILE-GATE2-EXAMPLE", "PERFIL-PRODUCT-DIRECTOR-LF",
                    "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED", "semantic_judge",
                    "SOURCE_SUPPORTED_V3_REVIEW",
                )
        self.assertNotEqual(code, 0)
        checkpoint = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
        self.assertEqual(checkpoint["status"], "CONTINUATION_REQUIRED_NOT_COMPLETE")
        self.assertFalse(checkpoint["last_run_completed"])
        self.assertEqual(checkpoint["next_step"], "semantic_judge")
        self.assertEqual(checkpoint["execution_id"], "EXEC-PROFILE-GATE2-EXAMPLE")
        self.assertEqual(checkpoint["request_schema_version"], SCHEMA)
        self.assertEqual(checkpoint["issue_label"], LABEL)
        self.assertTrue(checkpoint["reuse_execution_id"])
        self.assertFalse(checkpoint["owner_reauthorization_required"])
        self.assertEqual(checkpoint["credential_route"], "GITHUB_OIDC_TO_EDGE_ONLY")
        self.assertNotIn("service_role", json.dumps(checkpoint))

    def test_all_preterminal_boundaries_cannot_report_success(self):
        with patch.dict(os.environ, self.env, clear=True):
            module = runpy.run_path(str(SCRIPT), run_name="preterminal_checkpoint_test")
            with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
                for next_step in ("screen_selection", "input_governance", "execute_profile", "semantic_judge"):
                    code = module["record_incomplete_continuation"](
                        "EXEC-PROFILE-GATE2-EXAMPLE", "PERFIL-PRODUCT-DIRECTOR-LF",
                        "CONTINUATION_REQUIRED", next_step, "REQUIRED_EVIDENCE",
                    )
                    self.assertNotEqual(code, 0)
                    checkpoint = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
                    self.assertEqual(checkpoint["next_step"], next_step)
                    self.assertEqual(checkpoint["status"], "CONTINUATION_REQUIRED_NOT_COMPLETE")

    def test_unknown_continuation_step_blocks_without_writing_artifact(self):
        with patch.dict(os.environ, self.env, clear=True):
            module = runpy.run_path(str(SCRIPT), run_name="bad_continuation_test")
            with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
                with self.assertRaisesRegex(ValueError, "PROFILE_NATIVE_CONTINUATION_UNRECOGNIZED_STEP"):
                    module["record_incomplete_continuation"](
                        "EXEC-PROFILE-GATE2-EXAMPLE", "PERFIL-PRODUCT-DIRECTOR-LF",
                        "CONTINUATION_REQUIRED", "arbitrary_write", "UNAUTHORIZED",
                    )
        self.assertFalse((Path(self.tmp.name) / "profile-native-continuation.json").exists())

    def test_cli_no_longer_returns_zero_on_missing_v3_or_raw(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('if semantic_review is None:\n            return record_incomplete_continuation(', source)
        self.assertIn('if profile_output is None:\n            return record_incomplete_continuation(', source)
        self.assertNotIn('print("PROFILE_NATIVE_POST_MODEL_CONTINUATION_REQUIRED_NOT_COMPLETE")\n            return 0', source)
        self.assertNotIn('print("PROFILE_NATIVE_PRE_MODEL_PREPARATION_PASS_MODEL_OUTPUT_NOT_PRODUCED")\n            return 0', source)

    def test_only_exact_governed_202_allows_direct_resume(self):
        valid = {
            "outcome": "CONTINUATION_REQUIRED",
            "code": "IG_CONTEXT_PACK_VALIDATOR_RESUME_REQUIRED",
            "transport": "DIRECT_EDGE_INVOCATION",
            "queue_required": False,
            "polling_required": False,
            "result": {"status": "VALIDATOR_RESUME_REQUIRED"},
        }
        self.assertTrue(self.validator_continuation(202, valid))
        self.assertFalse(self.validator_continuation(200, valid))
        self.assertFalse(self.validator_continuation(409, valid))
        for field, wrong in [
            ("code", "UNRELATED"), ("transport", "QUEUED"),
            ("queue_required", True), ("polling_required", True),
            ("outcome", "BLOCKED"), ("result", {"status": "BLOCKED"}),
        ]:
            self.assertFalse(self.validator_continuation(202, {**valid, field: wrong}))
        self.assertFalse(self.validator_continuation(202, {}))



if __name__ == "__main__":
    unittest.main()
