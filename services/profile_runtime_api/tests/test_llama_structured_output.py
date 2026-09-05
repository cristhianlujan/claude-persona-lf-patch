from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any

from profile_runtime_api.llama import (
    CANONICAL_GENERATION_POLICY,
    UI_FOCUSED_GENERATION_POLICY,
    LlamaHTTPClient,
    LlamaTransportError,
    PersistentLlamaServerAdapter,
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
                "selected_visual_type": {"type": "string", "minLength": 3},
                "size_or_coverage": {"type": "string", "minLength": 3},
                "density_limits": {"type": "string", "minLength": 3},
                "depth_style": {"type": "string", "minLength": 3},
                "visual_weight": {"type": "string", "minLength": 3},
                "relationship_to_main_element": {"type": "string", "minLength": 3},
                "implementation_format": {"type": "string", "minLength": 3},
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
        self.assertEqual(generated["properties"]["selected_visual_type"]["minLength"], 18)
        self.assertEqual(generated["properties"]["size_or_coverage"]["minLength"], 12)
        self.assertEqual(generated["properties"]["density_limits"]["minLength"], 12)
        self.assertEqual(generated["properties"]["depth_style"]["minLength"], 12)
        self.assertEqual(generated["properties"]["visual_weight"]["minLength"], 16)
        self.assertEqual(
            generated["properties"]["relationship_to_main_element"]["minLength"], 20
        )
        self.assertEqual(generated["properties"]["implementation_format"]["minLength"], 16)
        self.assertEqual(generated["properties"]["hard_exclusions"]["maxItems"], 4)
        self.assertEqual(
            generated["properties"]["hard_exclusions"]["items"]["maxLength"], 120
        )
        self.assertNotIn("maxLength", canonical["properties"]["decision_subject"])
        self.assertNotIn("maxItems", canonical["properties"]["hard_exclusions"])
        self.assertEqual(completion["generation_schema_policy"], UI_FOCUSED_GENERATION_POLICY)
        self.assertTrue(completion["generation_schema_sha256"])

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
                "runtime_output_mode": "UI_FOCUSED_DECISION",
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


if __name__ == "__main__":
    unittest.main()
