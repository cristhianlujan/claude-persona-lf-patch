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
            self.blocked_ig_receipt = mod["record_blocked_ig_receipt"]
            self.unwrap_profile_native_evidence = mod["unwrap_profile_native_evidence"]
            self.attach_bound_evidence_manifest = mod["attach_bound_evidence_manifest"]

    def check(self):
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        with patch.dict(os.environ, self.env, clear=True):
            return self.get_request()

    def _mock_operation_plan(self, profile_code):
        # Transport-only fixture; DB resolution is independently tested in PG.
        return {
            "status": "READY", "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": profile_code,
            "steps": [{"step_order": i * 10, "step_id": "fixture_step_" + str(i)}
                      for i in range(11)],
            "skills": [],
        }

    def test_native_phrase_issue_parser_preserves_text_no_gate2(self):
        literal = ("Probar la carga masiva B2B (pantalla B2B-CARGA-002, "
                   "wizard de nueva carga; relacionadas B2B-CARGA-001 y "
                   "B2B-CARGA-007) entrando por el Router ACT-0001")
        stage1 = {
          "schema_version":"LF_ROUTER_STAGE1_V2",
          "texto_original":literal,"es_operacion":True,"ambiguo":False,
          "respuesta_directa":False,"sujeto":"carga masiva B2B",
          "accion":"ejecutar perfil sobre B2B-CARGA-002",
          "formas_busqueda":["carga masiva B2B","wizard de nueva carga","B2B-CARGA-002"],
          "alternativas":[],"correcciones":[],
          "downstream_execution_allowed":False,
          "canal_candidato":"PRODUCTO","negocio_codigo":"LF",
          "razon_seleccion":"alcance y aceptación de nueva carga",
          "alcance":{"target_type":"PANTALLA","target_hint":"B2B-CARGA-002",
                     "resolution_status":"UNRESOLVED"},
        }
        semantic = {"decision":"SELECTED",
          "selected_profile_code":"PERFIL-PRODUCT-DIRECTOR-LF",
          "ambiguous_profile_codes":[],"material_ambiguities":[],
          "reason":"La tarea es de producto y requiere criterios de aceptación",
          "evidence_refs":[{"kind":"ACTIVATION",
            "profile_code":"PERFIL-PRODUCT-DIRECTOR-LF",
            "source_section":"Activation triggers"},
            {"kind":"PURPOSE","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF",
             "source_section":"Purpose"}]}
        request={"schema_version":"LF_PROFILE_RUN_FROM_PHRASE_V1",
          "request_text":literal,"stage1_decision":stage1,
          "profile_semantic_decision":semantic,"executor_mode":"GPT_NATIVE"}
        self.event["issue"]["body"] = json.dumps(request,ensure_ascii=False)
        read=self.check()
        self.assertEqual(read["kind"],"PHRASE_BEGIN")
        self.assertEqual(read["request_text"],literal)
        self.assertEqual(read["stage1_decision"],stage1)
        self.assertNotIn("router_context",read)
        # No invented Gate2 allowed at input boundary.
        request["router_context"]={"status":"GATE2_DERIVED_PENDING_GOVERNED_ADMISSION"}
        self.event["issue"]["body"]=json.dumps(request)
        with self.assertRaisesRegex(ValueError,"PROFILE_PHRASE_SCHEMA_INVALID"):
            self.check()
        request.pop("router_context")
        request["stage1_decision"]["texto_original"]="Different owner sentence"
        self.event["issue"]["body"]=json.dumps(request)
        with self.assertRaisesRegex(ValueError,"PROFILE_PHRASE_SEMANTIC_INVALID"):
            self.check()

    def test_native_phrase_begin_routes_oidc_then_fails_closed_before_source(self):
        literal = "Probar la carga masiva B2B B2B-CARGA-002"
        request={"schema_version":"LF_PROFILE_RUN_FROM_PHRASE_V1",
          "request_text":literal,"executor_mode":"GPT_NATIVE",
          "stage1_decision":{
            "schema_version":"LF_ROUTER_STAGE1_V2","texto_original":literal,
            "negocio_codigo":"LF","downstream_execution_allowed":False},
          "profile_semantic_decision":{
            "decision":"SELECTED","selected_profile_code":"PERFIL-PRODUCT-DIRECTOR-LF"}}
        self.event["issue"]["body"]=json.dumps(request)
        self.event_path.write_text(json.dumps(self.event))
        calls=[]
        execution_id="EXEC-PROFILE-GATE2-"+"F"*24
        def fake(_url,body,_headers):
            calls.append(body.copy())
            if body["action"]=="profile_native_begin_from_phrase_v1":
                self.assertEqual(body["request_text"],literal)
                self.assertNotIn("router_context",body)
                return 200,{"outcome":"NATIVE_EXECUTION_READY","result":{
                  "status":"NATIVE_EXECUTION_READY",
                  "execution_id":execution_id,
                  "profile_code":"PERFIL-PRODUCT-DIRECTOR-LF"}}
            if body["action"]=="profile_native_source_bind_v1":
                return 409,{"outcome":"BLOCKED","code":"SOURCE_BIND_EXPECTED_FIXTURE"}
            raise AssertionError("no further step without source")
        env={**self.env,"GITHUB_SHA":"a"*40,"GITHUB_RUN_ID":"123"}
        with patch.dict(os.environ,env,clear=True):
            runner=runpy.run_path(str(SCRIPT),run_name="phrase_issue_test")["main"]
            with patch.dict(runner.__globals__,{"oidc":lambda:"test-oidc",
                  "call_json":fake}):
                self.assertEqual(runner(),1)
        self.assertEqual([x["action"] for x in calls],[
          "profile_native_begin_from_phrase_v1","profile_native_source_bind_v1"
        ])

    def _blocked_ig_edge_reply(self):
        execution_id = "EXEC-PROFILE-GATE2-" + "A" * 24
        profile_code = "PERFIL-PRODUCT-DIRECTOR-LF"
        return execution_id, profile_code, {
            "outcome": "BLOCKED",
            "phase": "BLOCKED",
            "code": "BLOCK_PROFILE_INPUT_GOVERNANCE",
            "execution_id": execution_id,
            "profile_code": profile_code,
            "result": {
                "execution_id": execution_id,
                "status": "BLOCKED",
                "blocking_code": "BLOCK_PROFILE_INPUT_GOVERNANCE",
                "input_validate": {
                    "status": "BLOCKED",
                    "blocking_code": "BLOCK_PROFILE_INPUT_GOVERNANCE",
                    "input_governance": {
                        "applicable": True,
                        "status": "BLOCKED",
                        "decision": "BLOCKED",
                        "continuation_allowed": False,
                        "profile_code": profile_code,
                        "pantalla_id": 51,
                        "consumer": "CONTEXT_PACK",
                        "governance_result": {
                            "status": "BLOCKED",
                            "consumer": "CONTEXT_PACK",
                            "pantalla_id": 51,
                            "run_id": 949,
                            "output_sha256": "a" * 64,
                            "raw_sensitive_data": {
                                "service_role_key": "SECRET_NEVER_ARTIFACT",
                                "original_producer_json": "PRIVATE_RAW_NEVER_ARTIFACT",
                            },
                        },
                    },
                },
            },
        }

    def test_semantic_skill_resume_payload_requires_one_bounded_decision(self):
        execution_id = "EXEC-PROFILE-GATE2-" + "A" * 24
        decision = {"selected_skill_code": "FICTICIA_SEMANTICA",
                    "reason": "source-bound", "evidence_refs": ["fixture://source/a"],
                    "descriptor_revision": "fixture-sem-1",
                    "review_mode": "CURRENT_CONTEXT_REVIEW"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": execution_id,
            "skill_semantic_decision": decision,
        })
        self.assertEqual(self.check(), {
            "kind": "SKILL_SEMANTIC_CONTINUATION",
            "execution_id": execution_id,
            "skill_semantic_decision": decision,
        })
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": execution_id,
            "skill_semantic_decision": decision, "profile_output": {"forged": True},
        })
        with self.assertRaisesRegex(ValueError, "PROFILE_GOVERNED_SKILL_SEMANTIC_SELECTION_INVALID"):
            self.check()

    def test_native_skill_semantic_candidates_checkpoint_same_run(self):
        execution_id = "EXEC-PROFILE-GATE2-" + "A" * 24
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": execution_id,
        })
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        calls = []
        def fake_call(_url, body, _headers):
            calls.append(body.copy())
            return 200, {
                "outcome": "SKILL_SEMANTIC_SELECTION_REQUIRED",
                "execution_id": execution_id,
                "profile_code": "PERFIL-TEST",
                "semantic_candidates": [{"skill_code": "FICTICIA_SEMANTICA",
                                         "source_revision": "fixture-sem-1",
                                         "descriptor": {"description": "synthetic"}}],
                "required_skills": [],
            }
        env = {**self.env, "GITHUB_SHA": "a" * 40}
        with patch.dict(os.environ, env, clear=True), patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
            main = runpy.run_path(str(SCRIPT), run_name="native_skill_semantic_test")["main"]
            with patch.dict(main.__globals__, {"oidc": lambda: "opaque-oidc", "call_json": fake_call}):
                self.assertEqual(main(), 1)
        self.assertEqual([x["action"] for x in calls], ["profile_native_source_bind_v1"])
        self.assertEqual(calls[0]["execution_id"], execution_id)
        checkpoint = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
        selection = json.loads((Path(self.tmp.name) / "profile-native-skill-semantic.json").read_text())
        self.assertEqual(checkpoint["next_step"], "skill_selection")
        self.assertEqual(checkpoint["execution_id"], selection["execution_id"])
        self.assertEqual(selection["semantic_candidates"][0]["skill_code"], "FICTICIA_SEMANTICA")
        self.assertFalse(checkpoint["last_run_completed"])

    def test_readonly_ig_blocked_ticket_continues_only_after_step40_readback(self):
        """Generic policy-selected runtime ticket; never let a worker 409 alone bypass Step40."""
        from datetime import datetime, timezone, timedelta
        execution_id = "EXEC-PROFILE-GATE2-" + "A" * 24
        profile_code = "PERFIL-PRODUCT-DIRECTOR-LF"
        skill_code = "INPUT_GOVERNANCE_CONTEXT_PACK"
        expiry = (datetime.now(timezone.utc)+timedelta(minutes=3)).isoformat()
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": execution_id})
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        p = Path(self.tmp.name) / "profiles" / "test_profile" / "SKILL.md"
        p.parent.mkdir(parents=True)
        p.write_text("# profile test source\n", encoding="utf-8")
        calls = []
        def fake_call(_url, data, headers):
            calls.append((data.copy(), headers.copy()))
            if data["action"] == "profile_native_source_bind_v1":
                return 200, {"outcome": "SOURCE_BINDING_REQUIRED",
                    "execution_id": execution_id, "profile_code": profile_code,
                    "source_revision_required": "a" * 40,
                    "target_repo": "test-owner/test-repo",
                    "target_path": "profiles/test_profile/SKILL.md",
                    "operation_plan": self._mock_operation_plan(profile_code)}
            if data["action"] == "profile_skill_runtime_v1":
                self.assertEqual(data["skill_code"],skill_code)
                return 409, {"outcome":"BLOCKED",
                    "code":"SKILL_RUNTIME_BLOCKED_AS_FINDING",
                    "terminal_status":"BLOCKED",
                    "execution_id":execution_id,
                    "skill_code":skill_code,
                    "result":{"result":{"status":"BLOCKED","consumer":"CONTEXT_PACK",
                        "pantalla_id":51,"run_id":951,
                        "remediation_state":"INTERNAL_REMEDIATION_REQUIRED",
                        "owner_interruption_required":False,
                        "promotion_authorized":False,
                        "production_authorized":False,
                        "execution_mode":"REUSE_COMPLETED_CURRENT_RUN",
                        "output_sha256":"5"*64,
                        "predecision_crosscheck":{
                            "status":"CANONICAL_READBACK_ONLY","run_id":951,
                            "deterministic_finding_count":3}}}}
            if data["action"] == "profile_native_continue_v1":
                if sum(k[0]["action"] == "profile_native_continue_v1" for k in calls) == 1:
                    return 200, {"outcome":"CONTINUATION_REQUIRED",
                        "phase":"SKILL_RUNTIME_REQUIRED",
                        "result":{
                            "skill_code":skill_code,
                            "input_governance_runtime_request":{
                                "transport":"DIRECT_EDGE_INVOCATION",
                                "queue_required":False,"polling_required":False,
                                "ticket_expires_at":expiry,
                                "request_headers":{"X-LF-Profile-Runtime-Ticket":"fixture-ticket"},
                                "request_body":{"action":"profile_skill_runtime_v1",
                                                "execution_id":execution_id,
                                                "skill_code":skill_code}}}}
                return 200, {"outcome":"CONTINUATION_REQUIRED",
                    "phase":"NATIVE_MODEL_INPUT_READY",
                    "execution_id":execution_id,"profile_code":profile_code,
                    "result":{"execution_write_mode":"READ_ONLY",
                        "skill_findings":[{"skill_code":skill_code,
                            "status":"SKILL_FAILED_AS_FINDING"}],
                        "input_governance":{"status":"BLOCKED",
                            "analysis_scope":"READ_ONLY_WITH_IG_FINDINGS",
                            "governance_result":{"run_id":951,
                                "output_sha256":"5"*64,
                                "predecision_crosscheck":{
                                    "deterministic_finding_count":3}}}}}
            raise AssertionError("unrecognized mocked Edge action")
        env = {**self.env,"GITHUB_SHA":"a"*40,"GITHUB_RUN_ID":"42"}
        with patch.dict(os.environ,env,clear=True), patch("pathlib.Path.cwd",return_value=Path(self.tmp.name)):
            main = runpy.run_path(str(SCRIPT),run_name="read_only_ticket_test")["main"]
            with patch.dict(main.__globals__, {"oidc":lambda:"opaque-oidc",
                                                  "call_json":fake_call}):
                self.assertEqual(main(),1)
        steps=[x[0]["action"] for x in calls]
        self.assertEqual(steps,["profile_native_source_bind_v1",
                                "profile_native_continue_v1",
                                "profile_skill_runtime_v1",
                                "profile_native_continue_v1"])
        checkpoint=json.loads((Path(self.tmp.name)/"profile-native-continuation.json").read_text())
        self.assertEqual(checkpoint["execution_id"],execution_id)
        self.assertEqual(checkpoint["next_step"],"execute_profile")
        self.assertFalse(checkpoint["last_run_completed"])

    def test_native_profile_single_resume_automatically_chains_50_60_70_80(self):
        """One Issue carries native RAW+V3; mock only transport, never claim live SQL."""
        import hashlib
        execution_id = "EXEC-PROFILE-GATE2-" + "A" * 24
        profile_code = "PERFIL-TEST"
        native_raw = {"result": "fixture-native-output"}
        review = {"verdict": "PASS_REVIEWED_CURRENT_CONTEXT"}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": execution_id,
            "profile_output": native_raw, "semantic_judge_review": review,
        })
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        self.assertEqual(self.check()[2:], (native_raw, review))
        path = Path(self.tmp.name) / "profiles" / "test_profile" / "SKILL.md"
        path.parent.mkdir(parents=True)
        path.write_text("# Test native source\\n", encoding="utf-8")
        steps = []
        def fake_call(_url, body, _headers):
            steps.append((body["action"], body.copy()))
            if body["action"] == "profile_native_source_bind_v1":
                return 200, {
                    "outcome": "SOURCE_BINDING_REQUIRED", "execution_id": execution_id,
                    "source_revision_required": "a" * 40, "target_repo": "test-owner/test-repo",
                    "target_path": "profiles/test_profile/SKILL.md", "profile_code": profile_code, "operation_plan": self._mock_operation_plan(profile_code),
                }
            if "profile_output" in body:
                return 200, {"phase": "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED", "profile_code": profile_code}
            if "semantic_judge_result" in body:
                return 200, {"phase": "PROFILE_EXECUTION_COMPLETED", "profile_code": profile_code}
            return 200, {"phase": "NATIVE_MODEL_INPUT_READY", "profile_code": profile_code}
        env = {**self.env, "GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "12345"}
        with patch.dict(os.environ, env, clear=True), patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
            module = runpy.run_path(str(SCRIPT), run_name="same_run_test")
            main = module["main"]
            with patch.dict(main.__globals__, {
                "oidc": lambda: "fake-oidc-not-sent", "call_json": fake_call,
                "run_bound_validator": lambda *_: (
                    {"schema": "PROFILE_OUTPUT_VALIDATION_RESULT_V1"}, "actions://raw", "actions://validator"),
                "validate_independent_semantic_review": lambda _: None,
                "build_semantic_receipt": lambda _: {"status": "PASS", "verdict": review["verdict"]},
            }):
                self.assertEqual(main(), 0)
        self.assertEqual([a for a, _ in steps], [
            "profile_native_source_bind_v1", "profile_native_continue_v1",
            "profile_native_continue_v1", "profile_native_continue_v1",
        ])
        self.assertEqual(steps[2][1]["profile_output"], native_raw)
        self.assertEqual(steps[3][1]["semantic_judge_result"]["verdict"], review["verdict"])
        self.assertEqual({body["execution_id"] for _, body in steps}, {execution_id})
        self.assertTrue((Path(self.tmp.name) / "profile-semantic-judge.json").is_file())

    def test_blocked_ig_records_only_bound_hash_receipt_and_remains_nonpass(self):
        execution_id, profile_code, response = self._blocked_ig_edge_reply()
        with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
            self.assertTrue(self.blocked_ig_receipt(409, response, execution_id, profile_code))
        output = Path(self.tmp.name) / "profile-native-continuation.json"
        self.assertTrue(output.is_file())
        raw = output.read_text(encoding="utf-8")
        artifact = json.loads(raw)
        self.assertEqual(artifact["schema_version"], "LF_PROFILE_NATIVE_IG_BLOCKED_EVIDENCE_V1")
        self.assertEqual(artifact["execution_id"], execution_id)
        self.assertEqual(artifact["profile_code"], profile_code)
        self.assertEqual(artifact["status"], "BLOCKED_NOT_COMPLETE")
        self.assertEqual(artifact["governance_run_id"], 949)
        self.assertEqual(artifact["governance_declared_output_sha256"], "a" * 64)
        self.assertRegex(artifact["edge_response_canonical_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(artifact["governance_result_canonical_sha256"], r"^[0-9a-f]{64}$")
        self.assertFalse(artifact["last_run_completed"])
        self.assertFalse(artifact["continuation_allowed"])
        self.assertFalse(artifact["pass_claimed"])
        self.assertFalse(artifact["raw_payload_persisted"])
        self.assertNotIn("SECRET_NEVER_ARTIFACT", raw)
        self.assertNotIn("PRIVATE_RAW_NEVER_ARTIFACT", raw)
        self.assertNotIn('"governance_result":', raw)

    def test_main_409_from_governed_edge_writes_evidence_and_never_continues(self):
        execution_id, profile_code, blocked = self._blocked_ig_edge_reply()
        source_file = Path(self.tmp.name) / "profiles" / "product_director_lf" / "SKILL.md"
        source_file.parent.mkdir(parents=True)
        source_file.write_text("# Profile source fixture\n", encoding="utf-8")
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        # The test executes the same main() branch as GitHub Actions but never
        # requests a real OIDC token or calls Supabase.
        with patch.dict(os.environ, {**self.env, "GITHUB_SHA": "a" * 40},
                        clear=True), patch("pathlib.Path.cwd",
                                           return_value=Path(self.tmp.name)):
            module = runpy.run_path(str(SCRIPT), run_name="ig_blocked_bridge_test")
            calls = []
            def fake_call(url, body, headers):
                calls.append(body["action"])
                if body["action"] == "profile_native_source_bind_v1":
                    return 200, {
                        "outcome": "SOURCE_BINDING_REQUIRED",
                        "execution_id": execution_id,
                        "source_revision_required": "a" * 40,
                        "target_repo": "test-owner/test-repo",
                        "target_path": "profiles/product_director_lf/SKILL.md",
                        "profile_code": profile_code, "operation_plan": self._mock_operation_plan(profile_code),
                    }
                return 409, blocked
            # Issue request references the same execution, not a new BEGIN.
            self.event["issue"]["body"] = json.dumps({
                "schema_version": SCHEMA,
                "execution_id": execution_id,
            })
            self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
            main = module["main"]
            with patch.dict(main.__globals__,
                            {"oidc": lambda: "test-token", "call_json": fake_call}):
                self.assertEqual(main(), 1)
        self.assertEqual(calls, [
            "profile_native_source_bind_v1", "profile_native_continue_v1",
        ])
        receipt_path = Path(self.tmp.name) / "profile-native-continuation.json"
        self.assertTrue(receipt_path.is_file())
        receipt = json.loads(receipt_path.read_text())
        self.assertEqual(receipt["execution_id"], execution_id)
        self.assertEqual(receipt["status"], "BLOCKED_NOT_COMPLETE")
        self.assertFalse(receipt["pass_claimed"])
        self.assertNotIn("SECRET_NEVER_ARTIFACT", receipt_path.read_text())

    def test_blocked_ig_canonical_receipt_digest_detects_body_changes(self):
        execution_id, profile_code, response = self._blocked_ig_edge_reply()
        with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
            self.assertTrue(self.blocked_ig_receipt(409, response, execution_id, profile_code))
            original = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
            response["result"]["input_validate"]["input_governance"]["governance_result"]["run_id"] = 950
            self.assertTrue(self.blocked_ig_receipt(409, response, execution_id, profile_code))
            updated = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
        self.assertNotEqual(original["governance_result_canonical_sha256"],
                            updated["governance_result_canonical_sha256"])
        self.assertNotEqual(original["edge_response_canonical_sha256"],
                            updated["edge_response_canonical_sha256"])

    def test_blocked_ig_fails_closed_on_unrelated_or_untrusted_responses(self):
        execution_id, profile_code, response = self._blocked_ig_edge_reply()
        invalid = []
        invalid.append((200, response))
        for mutate in [
            lambda x: x.update(execution_id="EXEC-PROFILE-GATE2-" + "B" * 24),
            lambda x: x["result"].update(execution_id="EXEC-PROFILE-GATE2-" + "B" * 24),
            lambda x: x.update(profile_code="PERFIL-OTHER"),
            lambda x: x.update(code="UNRELATED_409"),
            lambda x: x["result"].update(status="READY"),
            lambda x: x["result"]["input_validate"].update(status="READY"),
            lambda x: x["result"]["input_validate"]["input_governance"].update(
                continuation_allowed=True),
            lambda x: x["result"]["input_validate"]["input_governance"].update(
                consumer="STORY_CREATOR"),
            lambda x: x["result"]["input_validate"]["input_governance"].update(
                pantalla_id=52),
            lambda x: x["result"]["input_validate"]["input_governance"][
                "governance_result"].update(status="READY"),
            lambda x: x["result"]["input_validate"]["input_governance"][
                "governance_result"].update(output_sha256="INVALID"),
            lambda x: x["result"]["input_validate"]["input_governance"].pop(
                "governance_result"),
        ]:
            copy = json.loads(json.dumps(response))
            mutate(copy)
            invalid.append((409, copy))
        with patch("pathlib.Path.cwd", return_value=Path(self.tmp.name)):
            for code, bad in invalid:
                with self.subTest(code=code, invalid=bad):
                    self.assertFalse(self.blocked_ig_receipt(
                        code, bad, execution_id, profile_code))
                    self.assertFalse((Path(self.tmp.name) /
                                      "profile-native-continuation.json").exists())

    def test_reparador_v06_manifest_is_separate_from_raw_and_sha_bound(self):
        profile = "profiles/systemic_root_cause_repair_lf/SKILL.md"
        manifest = {"manifest_version": "SRCR_EVIDENCE_MANIFEST_V1",
                    "bundle_id": "evidence-current-case",
                    "evidence": [{"evidence_id": "EV-CURRENT",
                                  "source_locator": "supabase://public/lf_operation_execution/EXAMPLE",
                                  "state": "CURRENT"}]}
        candidate = {"status": "NEEDS_MORE_EVIDENCE", "profile_pack_id": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"}
        envelope = {"candidate": candidate, "evidence_manifest": manifest}
        self.event["issue"]["body"] = json.dumps({
            "schema_version": SCHEMA, "execution_id": "EXEC-PROFILE-GATE2-EXAMPLE",
            "profile_output": envelope})
        self.assertEqual(self.check()[2], envelope)
        actual, source = self.unwrap_profile_native_evidence(profile, envelope)
        self.assertEqual(actual, candidate)
        self.assertEqual(source, manifest)
        packet = {"schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1"}
        import hashlib
        root = Path(self.tmp.name)
        self.attach_bound_evidence_manifest(root, packet, source)
        stored = root / packet["evidence_manifest_ref"]
        self.assertEqual(stored.name, "profile-native-evidence-manifest.json")
        self.assertEqual(packet["evidence_manifest_sha256"], hashlib.sha256(stored.read_bytes()).hexdigest())
        self.assertEqual(json.loads(stored.read_text()), manifest)

    def test_v06_missing_or_malformed_manifest_fails_closed(self):
        profile = "profiles/systemic_root_cause_repair_lf/SKILL.md"
        candidate = {"status": "NEEDS_MORE_EVIDENCE"}
        valid = {"manifest_version": "SRCR_EVIDENCE_MANIFEST_V1",
                 "evidence": [{"evidence_id": "EV-A"}]}
        cases = [
            candidate,
            {"candidate": candidate},
            {"candidate": candidate, "evidence_manifest": None},
            {"candidate": [], "evidence_manifest": valid},
            {"candidate": candidate, "evidence_manifest": {"manifest_version": "BAD", "evidence": [{"evidence_id": "EV-A"}]}},
            {"candidate": candidate, "evidence_manifest": {"manifest_version": "SRCR_EVIDENCE_MANIFEST_V1", "evidence": []}},
            {"candidate": candidate, "evidence_manifest": valid, "extra": "surplus"},
        ]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(ValueError):
                self.unwrap_profile_native_evidence(profile, case)
        other = "profiles/product_director_lf/SKILL.md"
        self.assertEqual(self.unwrap_profile_native_evidence(other, candidate), (candidate, None))
        packet = {}
        with self.assertRaises(ValueError):
            self.attach_bound_evidence_manifest(Path(self.tmp.name), packet, {"junk": "x" * 25000})
        self.assertFalse((Path(self.tmp.name) / "profile-native-evidence-manifest.json").exists())

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

    def _skill_body(self, **over):
        body = {"schema_version": "LF_PROFILE_NATIVE_SKILL_INVOKE_REQUEST_V1",
                "execution_id": "EXEC-PROFILE-GATE2-" + "A" * 24, "skill_code": "PROFILE_UPDATE_APPLY",
                "input": {"target_code": "PERFIL-X-LF", "target_path": "profiles/x/SKILL.md"}}
        body.update(over)
        return body

    def test_skill_invoke_request_is_parsed_with_bounded_fields(self):
        self.event["issue"]["body"] = json.dumps(self._skill_body())
        got = self.check()
        self.assertEqual(got["kind"], "SKILL_INVOKE")
        self.assertEqual(got["skill_code"], "PROFILE_UPDATE_APPLY")
        self.assertEqual(got["input"]["target_code"], "PERFIL-X-LF")

    def test_skill_invoke_request_rejects_extra_fields_and_bad_values(self):
        for body in (self._skill_body(parent_execution_id="EXEC-ATTACKER"), self._skill_body(skill_code="profile_update_apply"),
                     self._skill_body(skill_code="X; DROP"), self._skill_body(execution_id="EXEC-ATTACKER-0000"),
                     self._skill_body(input="text"), self._skill_body(input=[1]), self._skill_body(input={"x": "a" * 60000})):
            self.event["issue"]["body"] = json.dumps(body)
            with self.assertRaises(ValueError):
                self.check()
        missing = self._skill_body(); del missing["skill_code"]
        self.event["issue"]["body"] = json.dumps(missing)
        with self.assertRaises(ValueError):
            self.check()

    def test_skill_invoke_calls_only_the_skill_action_and_fails_closed(self):
        self.event["issue"]["body"] = json.dumps(self._skill_body())
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        for code, reply, expected_rc in (
            (200, {"outcome": "SKILL_INVOKED", "result": {"status": "CHILD_OPENED"}}, 0),
            (409, {"outcome": "BLOCKED", "code": "PROFILE_SKILL_INVOKE_REJECTED", "detail": "falta autoridad"}, 1),
            (200, {"outcome": "BLOCKED"}, 1),
        ):
            with patch.dict(os.environ, {**self.env, "GITHUB_SHA": "a" * 40}, clear=True):
                main = runpy.run_path(str(SCRIPT), run_name="native_skill_test")["main"]
                calls = []
                def fake_call(url, body, headers):
                    calls.append(body)
                    return code, reply
                with patch.dict(main.__globals__, {"oidc": lambda: "t", "call_json": fake_call}):
                    self.assertEqual(main(), expected_rc)
            self.assertEqual([c["action"] for c in calls], ["profile_native_skill_invoke_v1"])
            self.assertEqual(calls[0]["execution_id"], "EXEC-PROFILE-GATE2-" + "A" * 24)

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
        self.assertIn('def complete_native_profile_semantic_and_report(', source)
        self.assertIn('if semantic_review is None:\n        return record_incomplete_continuation(', source)
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



    def _skill_plan_issue(self, calls):
        self.event["issue"]["body"] = json.dumps({
            "schema_version": "LF_PROFILE_NATIVE_SKILL_PLAN_REQUEST_V1",
            "execution_id": "EXEC-PROFILE-GATE2-" + "A" * 24,
            "calls": calls,
        })
        return self.check()

    def test_skill_plan_accepts_dynamic_targets_only_for_non_effecting_skills(self):
        request = self._skill_plan_issue([
            {"skill_code": "SCREEN_RULES_SNAPSHOT", "input": {"pantalla_codigo": "B2B-AUTH-001"}},
            {"skill_code": "RULE_UPDATE_PROPOSE", "input": {"regla_codigo": "B2B-RULE-AUTH-047"}},
        ])
        self.assertEqual(request["kind"], "SKILL_PLAN")
        self.assertEqual(len(request["calls"]), 2)
        self.assertTrue(request["execution_id"].startswith("EXEC-PROFILE-GATE2-"))

    def test_skill_plan_rejects_write_and_duplicate_or_unbounded_calls(self):
        valid = [{"skill_code": "SCREEN_RULES_SNAPSHOT", "input": {"pantalla_codigo": "HOME-001"}}]
        for calls in (
            [{"skill_code": "RULE_UPDATE_APPLY", "input": {"regla_codigo": "X"}}],
            valid * 2,
            [],
            valid * 9,
            [{"skill_code": "SCREEN_RULES_SNAPSHOT", "input": {"pantalla_codigo": "X"}, "authority": "FAKE"}],
            [{"skill_code": "SCREEN_RULES_SNAPSHOT", "input": "not_an_object"}],
        ):
            with self.subTest(calls=calls), self.assertRaises(ValueError):
                self._skill_plan_issue(calls)

    def test_skill_plan_calls_existing_edge_sequentially_and_never_closes_parent(self):
        calls = [
            {"skill_code": "SCREEN_RULES_SNAPSHOT", "input": {"pantalla_codigo": "B2B-AUTH-001"}},
            {"skill_code": "RULE_UPDATE_PROPOSE", "input": {"regla_codigo": "B2B-RULE-AUTH-047"}},
        ]
        self._skill_plan_issue(calls)
        with patch.dict(os.environ, self.env, clear=True), patch(
            "pathlib.Path.cwd", return_value=Path(self.tmp.name)
        ):
            m = runpy.run_path(str(SCRIPT), run_name="skill_plan_runtime_test")
            observed = []
            def fake_edge(url, body, headers):
                observed.append(body)
                self.assertEqual(body["action"], "profile_native_skill_invoke_v1")
                self.assertEqual(body["execution_id"], "EXEC-PROFILE-GATE2-" + "A" * 24)
                self.assertNotIn("service_role", json.dumps(body).lower())
                i = len(observed)
                return 200, {"outcome": "SKILL_INVOKED", "result": {
                    "status": "COMPLETED", "skill_run_id": "RUN-" + str(i),
                    "evidence_ref": "SKILLRUN:RUN-" + str(i) + ":digest",
                    "next_action": "CONTINUE_PROFILE",
                }}
            with patch.dict(m["main"].__globals__, {
                "oidc": lambda: "test-token", "call_json": fake_edge,
            }):
                self.assertEqual(m["main"](), 1)
        self.assertEqual([c["skill_code"] for c in observed],
                         ["SCREEN_RULES_SNAPSHOT", "RULE_UPDATE_PROPOSE"])
        receipt = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
        self.assertEqual(receipt["status"], "SKILL_PLAN_EVIDENCE_READY")
        self.assertEqual(len(receipt["calls"]), 2)
        self.assertEqual(receipt["next_step"], "execute_profile")
        self.assertFalse(receipt["profile_execution_complete"])
        self.assertFalse(receipt["business_write_performed"])
        self.assertTrue(receipt["same_parent_execution"])

    def test_skill_plan_denial_and_unexpected_child_fail_closed(self):
        call_items = [
            {"skill_code": "SCREEN_RULES_SNAPSHOT", "input": {"pantalla_codigo": "B2B-AUTH-001"}},
            {"skill_code": "RULE_UPDATE_PROPOSE", "input": {"regla_codigo": "B2B-RULE-AUTH-047"}},
        ]
        for denied in (True, False):
            with self.subTest(denied=denied):
                self._skill_plan_issue(call_items)
                with patch.dict(os.environ, self.env, clear=True), patch(
                    "pathlib.Path.cwd", return_value=Path(self.tmp.name)
                ):
                    m = runpy.run_path(str(SCRIPT), run_name="skill_plan_blocked_test")
                    observed = []
                    def fake_edge(url, body, headers):
                        observed.append(body)
                        if denied:
                            return 403, {"outcome": "BLOCKED", "code": "DENIED"}
                        return 200, {"outcome": "SKILL_INVOKED", "result": {
                            "status": "COMPLETED", "skill_run_id": "RUN-1",
                            "evidence_ref": "SKILLRUN:RUN-1:digest",
                            "child_execution_id": "EXEC-SKILL-UNEXPECTED",
                        }}
                    with patch.dict(m["main"].__globals__, {
                        "oidc": lambda: "test-token", "call_json": fake_edge,
                    }):
                        self.assertEqual(m["main"](), 1)
                self.assertEqual(len(observed), 1)
                receipt = json.loads((Path(self.tmp.name) / "profile-native-continuation.json").read_text())
                self.assertEqual(receipt["status"], "BLOCKED")
                self.assertEqual(receipt["next_step"], "skill_plan_repair")
                self.assertFalse(receipt["profile_execution_complete"])


    def _child_step_body(self):
        return {
            "schema_version": "LF_PROFILE_NATIVE_SKILL_STEP_BATCH_REQUEST_V1",
            "execution_id": "EXEC-PROFILE-GATE2-" + "A" * 24,
            "child_execution_id": "EXEC-SKILL-49797550002EE84C",
            "steps": [
                {"step_id": "router", "evidence_ref": "git:verified-router",
                 "evidence_payload": {"router_read": "c" * 64,
                                      "action": "SKILL_UPDATE", "blocking_codes": []}},
                {"step_id": "skill_resolve", "evidence_ref": "git:owner-readback",
                 "evidence_payload": {"codigo_activo": "ACT-0045",
                                      "repo_path": "skills/profile_creator",
                                      "exact_skill_resolved": True, "blocking_codes": []}},
            ],
        }

    def test_child_step_batch_parses_under_same_parent_without_credentials(self):
        body = self._child_step_body()
        self.event["issue"]["body"] = json.dumps(body)
        result = self.check()
        self.assertEqual(result["kind"], "SKILL_STEP_BATCH")
        self.assertEqual(result["execution_id"], body["execution_id"])
        self.assertEqual(result["child_execution_id"], body["child_execution_id"])
        self.assertEqual(len(result["steps"]), 2)

    def test_child_step_batch_rejects_forged_pass_wrong_order_and_write_step(self):
        original = self._child_step_body()
        for mutate in [
            lambda x: x.update(service_role="FAKE"),
            lambda x: x.update(child_execution_id="EXEC-ATTACKER"),
            lambda x: x["steps"].reverse(),
            lambda x: x["steps"].append(x["steps"][0]),
            lambda x: x["steps"][1].update(step_id="github_write"),
            lambda x: x["steps"][0]["evidence_payload"].update(server_assertions=["PASS"]),
            lambda x: x["steps"][0]["evidence_payload"].update(step_result="STEP_PASS_WITH_EVIDENCE"),
        ]:
            item = json.loads(json.dumps(original))
            mutate(item)
            self.event["issue"]["body"] = json.dumps(item)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                self.check()

    def test_post60_batch_uses_same_request_schema_and_run(self):
        body = self._child_step_body()
        names = ["github_write", "github_readback", "deterministic_validation",
                 "semantic_judge", "regression_after", "close", "report_output"]
        body["steps"] = [
            {"step_id": step, "evidence_ref": "git:verified:" + step,
             "evidence_payload": {"pr_number": 3746, "blocking_codes": []}}
            for step in names
        ]
        self.event["issue"]["body"] = json.dumps(body)
        result = self.check()
        self.assertEqual(result["kind"], "SKILL_STEP_BATCH")
        self.assertEqual(result["execution_id"], body["execution_id"])
        self.assertEqual(result["child_execution_id"], body["child_execution_id"])
        self.assertEqual([s["step_id"] for s in result["steps"]], names)

    def test_post60_rejects_mixed_phase_and_forged_judge(self):
        body = self._child_step_body()
        cases = [
            [{"step_id": "pre_write_execution_binding_gate", "evidence_ref": "git:gate",
              "evidence_payload": {}},
             {"step_id": "github_write", "evidence_ref": "git:write",
              "evidence_payload": {}}],
            [{"step_id": "semantic_judge", "evidence_ref": "git:review",
              "evidence_payload": {"derived_result": "STEP_PASS_WITH_EVIDENCE"}}],
            [{"step_id": "github_readback", "evidence_ref": "git:readback",
              "evidence_payload": {}},
             {"step_id": "github_write", "evidence_ref": "git:write",
              "evidence_payload": {}}],
        ]
        for steps in cases:
            item = json.loads(json.dumps(body))
            item["steps"] = steps
            self.event["issue"]["body"] = json.dumps(item)
            with self.subTest(steps=steps), self.assertRaises(ValueError):
                self.check()

    def test_child_step_batch_uses_existing_oidc_edge_action_only(self):
        body = self._child_step_body()
        self.event["issue"]["body"] = json.dumps(body)
        self.event_path.write_text(json.dumps(self.event), encoding="utf-8")
        with patch.dict(os.environ, self.env, clear=True):
            m = runpy.run_path(str(SCRIPT), run_name="skill_child_step_test")
            requests = []
            def edge(url, b, headers):
                requests.append(b)
                self.assertEqual(b["action"], "profile_native_skill_step_batch_v1")
                self.assertEqual(b["execution_id"], body["execution_id"])
                self.assertEqual(b["child_execution_id"], body["child_execution_id"])
                self.assertNotIn("service_role", json.dumps(b).lower())
                return 200, {"outcome": "SKILL_CHILD_STEP_BATCH_RECORDED",
                    "execution_id": b["execution_id"],
                    "child_execution_id": b["child_execution_id"], "steps_recorded": 2}
            with patch.dict(m["main"].__globals__, {
                "oidc": lambda: "test-oidc-token", "call_json": edge,
            }):
                self.assertEqual(m["main"](), 0)
        self.assertEqual(len(requests), 1)


if __name__ == "__main__":
    unittest.main()
