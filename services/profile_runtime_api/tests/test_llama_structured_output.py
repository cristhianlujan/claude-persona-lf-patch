from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any

from profile_runtime_api.llama import (
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

    def call(self, content: str, *, profile_slug: str = "ui_architect") -> RecordingClient:
        client = RecordingClient(self.settings, content)
        client.chat(
            system_prompt="system",
            user_prompt="user",
            schema=self.schema,
            profile_slug=profile_slug,
        )
        return client

    def test_ui_architect_preserves_proven_unconstrained_v27_fallback(self) -> None:
        client = self.call('{"ok":true}', profile_slug="ui_architect")
        assert client.last_payload is not None
        self.assertNotIn("response_format", client.last_payload)

    def test_other_profiles_keep_existing_schema_constrained_generation(self) -> None:
        client = self.call('{"ok":true}', profile_slug="quality_pack")
        assert client.last_payload is not None
        self.assertEqual(
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
