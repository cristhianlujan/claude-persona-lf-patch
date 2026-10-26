from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any

from profile_runtime_api.llama import LlamaTransportError, PersistentLlamaServerAdapter
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.settings import Settings


class FakeClient:
    def health(self) -> dict[str, Any]:
        return {"ready": True}

    def chat(self, **_: Any) -> dict[str, Any]:
        return {
            "content": '{"ok":true}',
            "id": "completion-attestation-test",
            "model": "/opt/profile-runtime-benchmark/model/model.gguf",
            "usage": {"prompt_tokens": 10, "completion_tokens": 4},
            "timings": {},
            "finish_reason": "stop",
            "generation_schema_sha256": "a" * 64,
            "generation_schema_policy": "CANONICAL_SCHEMA",
        }


class ExecutorModeAttestationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(
            repo_root=Path(__file__).resolve().parents[3],
            state_dir=Path(self.temp.name),
            api_token="test-token",
            max_output_tokens=128,
        )
        schema = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False}
        self.binding = SchemaBinding(
            payload=schema,
            raw=b'{"type":"object"}',
            sha256="b" * 64,
            source_refs=("benchmark.schema.json",),
            mode="BENCHMARK",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def adapter(self) -> PersistentLlamaServerAdapter:
        return PersistentLlamaServerAdapter(
            settings=self.settings,
            client=FakeClient(),  # type: ignore[arg-type]
            schema=self.binding,
            structural_context={"schema":"benchmark","source":"QUEUE_NATIVE_TEXT_PROFILE"},
            image_bytes=None,
            image_media_type=None,
            model_profile_sources=[{"ref":"profiles/p/SKILL.md","content":"# P\n"}],
            generation_schema=self.binding.payload,
            execution_budget={"max_prompt_tokens":7600,"max_output_tokens":128},
        )

    @staticmethod
    def request(mode: str) -> dict[str, Any]:
        return {
            "executor_mode": mode,
            "input_literal": "choose A",
            "profile_slug": "p",
            "profile_sources": [{"ref":"profiles/p/SKILL.md","content":"# P\n"}],
            "lf_adapter_sources": [],
            "request_sha256": "1" * 64,
            "profile_source_sha256": "2" * 64,
            "input_sha256": "3" * 64,
            "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": "PERFIL-P",
        }

    def test_remote_api_mode_is_attested(self) -> None:
        response=self.adapter().execute(self.request("REMOTE_API"))
        self.assertEqual(response["runtime_attestation"]["executor_mode"], "REMOTE_API")
        self.assertEqual(response["runtime_attestation"]["provider"], "local_llama_cpp_hetzner_persistent")

    def test_non_remote_mode_fails_before_model_call(self) -> None:
        with self.assertRaises(LlamaTransportError) as ctx:
            self.adapter().execute(self.request("GPT_NATIVE"))
        self.assertEqual(ctx.exception.code, "LLAMA_EXECUTOR_MODE_INVALID")


if __name__ == "__main__":
    unittest.main()
