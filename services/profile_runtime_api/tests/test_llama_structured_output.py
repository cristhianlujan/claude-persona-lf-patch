from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from profile_runtime_api.llama import (
    CANONICAL_GENERATION_POLICY,
    UI_FOCUSED_GENERATION_POLICY,
    UI_PRODUCTION_GENERATION_POLICY,
    UI_PRODUCTION_SEMANTIC_GENERATION_POLICY,
    compact_model_context,
    LlamaHTTPClient,
    LlamaTransportError,
    PersistentLlamaServerAdapter,
    ui_focused_profile_model_view,
    ui_production_profile_model_view,
    ui_production_semantic_context_view,
)
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.settings import Settings


class RecordingClient(LlamaHTTPClient):
    def __init__(self, settings: Settings, content: str) -> None:
        super().__init__(settings)
        self.content = content
        self.last_payload: dict[str, Any] | None = None

    def _request(
        self, method: str, path: str, payload: dict[str, Any] | None, timeout: int
    ) -> Any:
        self.last_payload = payload
        return {
            "id": "completion-test",
            "model": "fake-local-model",
            "choices": [
                {
                    "message": {"content": self.content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {},
            "timings": {},
        }


class StructuredOutputBoundaryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(
            repo_root=Path(__file__).resolve().parents[3],
            state_dir=Path(self.temp.name),
            api_token="test-token",
        )
        self.schema = {
            "type": "object",
            "required": ["ok"],
            "properties": {"ok": {"type": "boolean"}},
            "additionalProperties": False,
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def call(
        self,
        content: str,
        *,
        profile_slug: str = "ui_architect",
        schema_mode: str = "AUTO",
    ) -> RecordingClient:
        client = RecordingClient(self.settings, content)
        client.chat(
            system_prompt="system",
            user_prompt="user",
            schema=self.schema,
            profile_slug=profile_slug,
            schema_mode=schema_mode,
        )
        return client

    def test_ui_architect_auto_preserves_proven_unconstrained_v27_fallback(self) -> None:
        client = self.call('{"ok":true}', profile_slug="ui_architect", schema_mode="AUTO")
        assert client.last_payload is not None
        self.assertNotIn("response_format", client.last_payload)

    def test_ui_architect_explicit_mode_uses_exact_schema_constraint(self) -> None:
        client = self.call(
            '{"ok":true}',
            profile_slug="ui_architect",
            schema_mode="UI_FOCUSED_DECISION",
        )
        assert client.last_payload is not None
        self.assertEqual(
            client.last_payload["response_format"],
            {"type": "json_object", "schema": self.schema},
        )

    def test_ui_focused_generation_schema_is_bounded_without_mutating_canonical(self) -> None:
        canonical = {
            "type": "object",
            "required": ["decision_subject", "hard_exclusions", "status"],
            "properties": {
                "decision_subject": {"type": "string", "minLength": 3},
                "short_generator_prompt": {"type": "string", "minLength": 3},
                "hard_exclusions": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"type": "string", "minLength": 2},
                },
                "status": {"type": "string", "enum": ["CANDIDATE_READ_ONLY"]},
            },
            "additionalProperties": False,
        }
        client = RecordingClient(
            self.settings,
            '{"decision_subject":"overflow","hard_exclusions":["none"],"status":"CANDIDATE_READ_ONLY"}',
        )
        completion = client.chat(
            system_prompt="system",
            user_prompt="user",
            schema=canonical,
            profile_slug="ui_architect",
            schema_mode="UI_FOCUSED_DECISION",
        )
        assert client.last_payload is not None
        generated = client.last_payload["response_format"]["schema"]
        self.assertEqual(generated["properties"]["decision_subject"]["maxLength"], 160)
        self.assertEqual(generated["properties"]["short_generator_prompt"]["maxLength"], 240)
        self.assertEqual(generated["properties"]["hard_exclusions"]["maxItems"], 4)
        self.assertEqual(
            generated["properties"]["hard_exclusions"]["items"]["maxLength"], 120
        )
        self.assertNotIn("maxLength", canonical["properties"]["decision_subject"])
        self.assertNotIn("maxItems", canonical["properties"]["hard_exclusions"])
        self.assertEqual(completion["generation_schema_policy"], UI_FOCUSED_GENERATION_POLICY)
        self.assertTrue(completion["generation_schema_sha256"])

    def test_ui_focused_generation_schema_requires_minimum_semantic_phrase_space(self) -> None:
        canonical = json.loads(
            (self.settings.repo_root / "profiles/ui_architect/schemas/ui_focused_decision.schema.json").read_text(encoding="utf-8")
        )
        client = RecordingClient(self.settings, '{"decision_subject":"placeholder"}')
        client.chat(
            system_prompt="system", user_prompt="user", schema=canonical,
            profile_slug="ui_architect", schema_mode="UI_FOCUSED_DECISION",
        )
        assert client.last_payload is not None
        props = client.last_payload["response_format"]["schema"]["properties"]
        self.assertGreaterEqual(props["size_or_coverage"]["minLength"], 8)
        self.assertGreaterEqual(props["density_limits"]["minLength"], 6)
        self.assertGreaterEqual(props["relationship_to_main_element"]["minLength"], 10)
        self.assertGreaterEqual(props["hard_exclusions"]["items"]["minLength"], 8)
        self.assertEqual(canonical["properties"]["size_or_coverage"]["minLength"], 3)

    def test_other_profiles_keep_canonical_generation_schema(self) -> None:
        client = RecordingClient(self.settings, '{"ok":true}')
        completion = client.chat(
            system_prompt="system",
            user_prompt="user",
            schema=self.schema,
            profile_slug="quality_pack",
            schema_mode="AUTO",
        )
        assert client.last_payload is not None
        self.assertEqual(client.last_payload["response_format"]["schema"], self.schema)
        self.assertEqual(completion["generation_schema_policy"], CANONICAL_GENERATION_POLICY)

    def test_other_profiles_use_pinned_llama_schema_constrained_shape(self) -> None:
        client = self.call('{"ok":true}', profile_slug="quality_pack")
        assert client.last_payload is not None
        self.assertEqual(
            client.last_payload["response_format"],
            {"type": "json_object", "schema": self.schema},
        )
        self.assertNotEqual(
            client.last_payload["response_format"],
            {"type": "json_schema", "schema": self.schema},
        )

    def test_fenced_json_fails_closed_without_normalization(self) -> None:
        client = RecordingClient(self.settings, '```json\n{"ok":true}\n```')
        with self.assertRaises(LlamaTransportError) as ctx:
            client.chat(
                system_prompt="system",
                user_prompt="user",
                schema=self.schema,
                profile_slug="ui_architect",
            )
        self.assertEqual(ctx.exception.code, "LLAMA_STRUCTURED_OUTPUT_FENCED")

    def test_invalid_json_fails_closed(self) -> None:
        client = RecordingClient(self.settings, '{"ok":')
        with self.assertRaises(LlamaTransportError) as ctx:
            client.chat(
                system_prompt="system",
                user_prompt="user",
                schema=self.schema,
                profile_slug="ui_architect",
            )
        self.assertEqual(ctx.exception.code, "LLAMA_STRUCTURED_OUTPUT_JSON_INVALID")
        self.assertEqual(ctx.exception.diagnostics["model_raw_output"], '{"ok":')
        self.assertEqual(ctx.exception.diagnostics["model_raw_output_chars"], 6)
        self.assertEqual(len(ctx.exception.diagnostics["model_raw_output_sha256"]), 64)
        self.assertEqual(ctx.exception.diagnostics["finish_reason"], "stop")

    def test_json_array_fails_closed(self) -> None:
        client = RecordingClient(self.settings, '[{"ok":true}]')
        with self.assertRaises(LlamaTransportError) as ctx:
            client.chat(
                system_prompt="system",
                user_prompt="user",
                schema=self.schema,
                profile_slug="ui_architect",
            )
        self.assertEqual(ctx.exception.code, "LLAMA_STRUCTURED_OUTPUT_ROOT_NOT_OBJECT")

    def test_focused_prompt_requires_noncontradictory_concrete_treatment(self) -> None:
        binding = SchemaBinding(
            payload=self.schema,
            raw=b'{}',
            sha256="a" * 64,
            source_refs=("test.schema.json",),
            mode="UI_FOCUSED_DECISION",
        )
        adapter = PersistentLlamaServerAdapter(
            settings=self.settings,
            client=RecordingClient(self.settings, '{"ok":true}'),
            schema=binding,
            structural_context={},
            image_bytes=None,
            image_media_type=None,
        )
        prompt = adapter._system_prompt(
            {
                "profile_sources": [{"ref": "profiles/x/SKILL.md", "content": "TASK: REMEDIATE_EXISTING"}],
                "lf_adapter_sources": [],
            }
        )
        self.assertIn("corrective visual/interaction treatment", prompt)
        self.assertIn("hard_exclusions must never prohibit", prompt)
        self.assertIn("bare generic labels", prompt)

    def test_queue_context_flags_do_not_imply_missing_input(self) -> None:
        binding = SchemaBinding(
            payload=self.schema,
            raw=b'{}',
            sha256="a" * 64,
            source_refs=("test.schema.json",),
        )
        adapter = PersistentLlamaServerAdapter(
            settings=self.settings,
            client=RecordingClient(self.settings, '{"ok":true}'),
            schema=binding,
            structural_context={
                "screen_governance_applicable": False,
                "downstream_authorized": False,
            },
            image_bytes=None,
            image_media_type=None,
        )
        prompt = adapter._system_prompt(
            {
                "profile_sources": [{"ref": "profiles/x/SKILL.md", "content": "TASK: CREATE_NEW"}],
                "lf_adapter_sources": [],
            }
        )
        self.assertIn("does not block profile analysis", prompt)
        self.assertIn("not by itself a reason to return NEEDS_INPUT or RETURN_TO_ORCHESTRATOR", prompt)
        self.assertIn("first non-whitespace response character MUST be {", prompt)

    def test_ui_production_generation_is_compact_transport_and_uses_mode_budget(self) -> None:
        required_deliverable = [
            "screen_definition", "component_tree", "layout_grid", "visual_hierarchy",
            "state_map", "token_map", "spacing_typography", "density_rules",
            "risk_controls", "prompt_constraints",
        ]
        canonical = {
            "type": "object",
            "required": ["worker", "output_type", "deliverable_created", "score", "handoff_to_next", "self_verdict"],
            "properties": {
                "worker": {"type": "string"}, "output_type": {"type": "string"},
                "deliverable_created": {"type": "object", "required": required_deliverable, "properties": {}},
                "score": {"type": "object"}, "handoff_to_next": {"type": "object"},
                "self_verdict": {"type": "string"},
            },
        }
        compact = '{"w":"ui_architect","o":"PRODUCTION_UI_SPEC","d":{"s":["CREATE_NEW","screen","purpose","header","READY","clear"],"c":[],"l":["header","desktop","mobile"],"h":[],"m":[],"t":["surface","text","action","border","relative"],"p":["space","type","relative"],"y":["dense"],"r":["safe"],"q":["keep"]},"x":[4,4,4,4,4],"n":["composer","READY"],"v":"PASS"}'
        client = RecordingClient(self.settings, compact)
        completion = client.chat(
            system_prompt="system", user_prompt="user", schema=canonical,
            profile_slug="ui_architect", schema_mode="UI_PRODUCTION_SPEC",
        )
        assert client.last_payload is not None
        generated = client.last_payload["response_format"]["schema"]
        self.assertFalse(generated["additionalProperties"])
        self.assertEqual(generated["required"], ["w", "o", "d", "x", "n", "v"])
        deliverable = generated["properties"]["d"]
        self.assertFalse(deliverable["additionalProperties"])
        self.assertEqual(deliverable["properties"]["c"]["maxItems"], 12)
        self.assertEqual(deliverable["properties"]["x"]["maxItems"] if "x" in deliverable["properties"] else generated["properties"]["x"]["maxItems"], 5)
        self.assertEqual(client.last_payload["max_tokens"], 1050)
        self.assertEqual(completion["generation_schema_policy"], UI_PRODUCTION_GENERATION_POLICY)
        self.assertNotIn("additionalProperties", canonical)

    def test_ui_production_semantic_transport_uses_deterministic_acceptance_and_lower_budget(self) -> None:
        required_deliverable = [
            "screen_definition", "component_tree", "layout_grid", "visual_hierarchy",
            "state_map", "token_map", "spacing_typography", "density_rules",
            "risk_controls", "prompt_constraints",
        ]
        canonical = {
            "type": "object",
            "required": ["worker", "output_type", "deliverable_created", "score", "handoff_to_next", "self_verdict"],
            "properties": {
                "worker": {"type": "string"}, "output_type": {"type": "string"},
                "deliverable_created": {"type": "object", "required": required_deliverable, "properties": {}},
                "score": {"type": "object"}, "handoff_to_next": {"type": "object"},
                "self_verdict": {"type": "string"},
            },
        }
        acceptance = {
            "task_mode": "CREATE_NEW",
            "implementation_readiness": "READY",
            "required_component_ids": ["header_search", "service_cards", "service_cta"],
            "required_state_component_ids": ["header_search", "service_cta"],
            "required_sections": ["header", "service_cards"],
            "required_design_intents": ["clear", "easy_to_navigate"],
            "required_source_bindings": {
                "service_cards.items": "DATA_BOUND",
                "service_cta.label": "DATA_BOUND:call_to_action",
            },
            "required_responsive_modes": ["desktop", "mobile"],
            "minimum_component_count": 3,
            "minimum_hierarchy_depth_edges": 2,
            "minimum_risk_control_count": 2,
        }
        semantic = '{"v":5,"d":{"l":"STANDARD_GRID_STACK","h":["service_cards","service_cta"]}}'
        client = RecordingClient(self.settings, semantic)
        completion = client.chat(
            system_prompt="system", user_prompt="user", schema=canonical,
            profile_slug="ui_architect", schema_mode="UI_PRODUCTION_SPEC",
            acceptance=acceptance,
        )
        assert client.last_payload is not None
        generated = client.last_payload["response_format"]["schema"]
        self.assertEqual(generated["required"], ["v", "d"])
        self.assertEqual(generated["properties"]["v"]["const"], 5)
        self.assertNotIn("c", generated["properties"]["d"]["properties"])
        self.assertEqual(generated["properties"]["d"]["properties"]["h"]["uniqueItems"], True)
        self.assertNotIn("z", generated["properties"]["d"]["properties"])
        self.assertNotIn("p", generated["properties"]["d"]["properties"])
        self.assertNotIn("o", generated["properties"]["d"]["properties"])
        self.assertNotIn("score", generated["properties"]["d"]["properties"])
        self.assertEqual(client.last_payload["max_tokens"], 600)
        self.assertEqual(completion["generation_schema_policy"], UI_PRODUCTION_SEMANTIC_GENERATION_POLICY)

    def test_ui_focused_profile_view_strips_unrelated_production_rules(self) -> None:
        skill_path = self.settings.repo_root / "profiles/ui_architect/SKILL.md"
        full_skill = skill_path.read_text(encoding="utf-8")
        model_view = ui_focused_profile_model_view(full_skill)
        self.assertLess(len(model_view), len(full_skill) // 2)
        self.assertIn("Focused UI Decision Spec", model_view)
        self.assertIn("Focused runtime/safety rules", model_view)
        self.assertNotIn("top_amount_strip", model_view)
        self.assertNotIn("V6 Composer structural boundary", model_view)

    def test_artifact_set_model_context_drops_repeated_structural_payload(self) -> None:
        verbose = "x" * 4000
        full_context = {
            "schema": "lf-profile-runtime-artifact-set-context/v1",
            "contract": "NON_CANONICAL_ARTIFACT_SET_V1",
            "subject_mode": "NON_CANONICAL_ARTIFACT",
            "artifact_set_fingerprint": "f" * 64,
            "artifact_count": 2,
            "artifacts": [
                {
                    "artifact_ref": f"drive:{idx}",
                    "artifact_sha256": str(idx) * 64,
                    "filename": f"{idx}.png",
                    "screen_code": f"NONCANONICAL_{idx}",
                    "width_px": 1600,
                    "height_px": 1000,
                    "structural_context": {
                        "visible_ui_evidence": [
                            {"id": "h", "role": "PAGE_HEADER", "text": "Nueva carga", "bbox": [1,2,3,4], "text_source": "ORIGINAL_OCR"}
                        ],
                        "decomposer_context": {"verbose": verbose},
                        "dynamic_data": {"count": 0, "policy": "NO_DYNAMIC"},
                        "targeted_reread": {"status": "NOT_REQUIRED", "regions": 0},
                    },
                }
                for idx in (1, 2)
            ],
            "input_governance": {
                "status": "ADVISORY_READ_ONLY",
                "decision": "ADVISORY",
                "subject_mode": "NON_CANONICAL_ARTIFACT",
                "constraints": {"read_only": True, "no_write": True, "no_promotion": True},
                "receipt_ref": "verbose-ref-that-model-does-not-need",
            },
            "runtime_typed_context": {
                "classification": {"surface_code": "PROFILE:ui_architect", "task_code": "EJECUCION_PERFIL_LF:UI_FOCUSED_DECISION"},
                "input": {"input_fields": {}},
                "card_resolution": {"mode": "NO_CARD_GOVERNED"},
                "authority_resolution": [{"authority_type": "PROFILE_SOURCE", "authority_id": "verbose", "source_sha256": "a" * 64}],
                "adapter_binding": [{"adapter_code": "ADAPTER_LF_SHELL_PROFILE"}],
                "runtime_schema": {"mode": "UI_FOCUSED_DECISION", "source_ref": "focused.schema.json"},
                "typed_context_sha256": "b" * 64,
            },
            "lf_cards": [],
        }
        compact = compact_model_context(full_context)
        self.assertEqual(compact["schema"], "lf-profile-runtime-artifact-set-model-context/v1")
        self.assertEqual(compact["source"], "NON_CANONICAL_ARTIFACT_SET")
        self.assertEqual(len(compact["artifacts"]), 2)
        serialized = str(compact)
        self.assertNotIn(verbose, serialized)
        self.assertNotIn("verbose-ref-that-model-does-not-need", serialized)
        self.assertIn("Nueva carga", serialized)
        self.assertEqual(compact["adapter_codes"], ["ADAPTER_LF_SHELL_PROFILE"])

    def test_ui_production_semantic_views_strip_deterministic_authority(self) -> None:
        skill_path = self.settings.repo_root / "profiles/ui_architect/SKILL.md"
        full_skill = skill_path.read_text(encoding="utf-8")
        model_view = ui_production_profile_model_view(full_skill, task_mode="CREATE_NEW")
        self.assertLess(len(model_view), len(full_skill))
        self.assertIn("CREATE_NEW semantic rules", model_view)
        self.assertNotIn("top_amount_strip", model_view)

        acceptance = {
            "task_mode": "CREATE_NEW",
            "implementation_readiness": "READY",
            "required_component_ids": ["header_search", "service_cards"],
            "required_state_component_ids": ["header_search"],
            "required_sections": ["header", "service_cards"],
            "required_design_intents": ["clear"],
            "required_responsive_modes": ["desktop", "mobile"],
            "required_source_bindings": {
                "header_search.value": "USER_INPUT",
                "service_cards.items": "DATA_BOUND",
            },
            "minimum_component_count": 2,
            "minimum_hierarchy_depth_edges": 1,
            "minimum_risk_control_count": 1,
        }
        context = {
            "schema": "lf-profile-runtime-model-context/v1",
            "input_fields": {"gate_f_acceptance": acceptance, "domain_scope": "SERVICES"},
        }
        prompt_view = ui_production_semantic_context_view(context)
        exposed = prompt_view["input_fields"]["gate_f_acceptance"]
        self.assertNotIn("required_source_bindings", exposed)
        self.assertEqual(exposed["component_ids"], acceptance["required_component_ids"])
        self.assertEqual(exposed["hierarchy_depth"], 1)
        self.assertEqual(context["input_fields"]["gate_f_acceptance"], acceptance)

    def test_ui_production_generation_fails_closed_on_canonical_root_drift(self) -> None:
        canonical = {"type": "object", "required": ["worker"], "properties": {"worker": {"type": "string"}}}
        client = RecordingClient(self.settings, '{"worker":"ui_architect"}')
        with self.assertRaises(LlamaTransportError) as ctx:
            client.chat(system_prompt="system", user_prompt="user", schema=canonical, profile_slug="ui_architect", schema_mode="UI_PRODUCTION_SPEC")
        self.assertEqual(ctx.exception.code, "UI_PRODUCTION_CANONICAL_ROOT_DRIFT")

    def test_ui_production_prompt_compacts_queue_context_and_reference_only_source(self) -> None:
        binding = SchemaBinding(
            payload=self.schema, raw=b'{}', sha256="a" * 64,
            source_refs=("profiles/ui_architect/schemas/ui_production_spec.schema.json",),
            mode="UI_PRODUCTION_SPEC",
        )
        full_context = {
            "schema": "lf-profile-runtime-queue-context/v1",
            "source": "QUEUE_NATIVE_TEXT_PROFILE",
            "screen_governance_applicable": False,
            "downstream_authorized": False,
            "runtime_typed_context": {
                "classification": {"surface_code": "UI_SCREEN_DESIGN", "task_code": "CREATE_NEW"},
                "input": {"input_fields": {
                    "task_mode": "CREATE_NEW",
                    "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
                    "policy_snapshot_sha256": "b" * 64,
                    "gate_f_input_ref": "sandbox/huge-ref",
                }},
                "card_resolution": {"mode": "NO_CARD_GOVERNED"},
                "authority_resolution": [
                    {"authority_type": "USER_REQUIREMENT", "authority_id": "verbose-id", "source_sha256": "c" * 64},
                    {"authority_type": "PROFILE_CONTRACT", "authority_id": "verbose-profile", "source_sha256": "d" * 64},
                ],
                "adapter_binding": [],
                "runtime_schema": {"mode": "UI_PRODUCTION_SPEC", "source_ref": "schema.json"},
                "typed_context_sha256": "e" * 64,
            },
            "lf_cards": [],
        }
        compact = compact_model_context(full_context)
        self.assertEqual(compact["schema"], "lf-profile-runtime-model-context/v1")
        self.assertNotIn("policy_snapshot_sha256", compact["input_fields"])
        self.assertNotIn("gate_f_input_ref", compact["input_fields"])
        self.assertEqual(compact["authority_types"], ["PROFILE_CONTRACT", "USER_REQUIREMENT"])

        adapter = PersistentLlamaServerAdapter(
            settings=self.settings, client=RecordingClient(self.settings, '{"ok":true}'),
            schema=binding, structural_context=full_context, image_bytes=None, image_media_type=None,
        )
        boundary_body = "BOUNDARY_BODY_MUST_NOT_ENTER_MODEL_CONTEXT"
        prompt = adapter._system_prompt({
            "profile_sources": [
                {"ref": "profiles/ui_architect/SKILL.md", "content": "PROFILE_INSTRUCTIONS"},
                {"ref": "profiles/ui_architect/contracts/composer_payload_boundary_v1.md", "content": boundary_body},
            ],
            "lf_adapter_sources": [],
        })
        self.assertIn("PROFILE_INSTRUCTIONS", prompt)
        self.assertNotIn(boundary_body, prompt)
        self.assertIn("CANONICAL SOURCE BOUND BY REFERENCE", prompt)
        self.assertIn("lf-profile-runtime-model-context/v1", prompt)
        self.assertNotIn("verbose-id", prompt)
        self.assertIn("compact semantic transport UICT1", prompt)
        self.assertIn("Use | only as list separator", prompt)


if __name__ == "__main__":
    unittest.main()
