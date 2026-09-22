from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

DEPS_AVAILABLE = all(
    importlib.util.find_spec(name) is not None for name in ("jsonschema", "pydantic")
)

if DEPS_AVAILABLE:
    from profile_runtime_api.engine import ProfileRuntimeEngine
    from profile_runtime_api.hashing import canonical_json_sha256, sha256_text
    from profile_runtime_api.models import ResearchBaselineRequest
    from profile_runtime_api.settings import Settings


class FakeBaselineLlama:
    def __init__(self) -> None:
        self.chat_calls = 0
        self.last_kwargs: dict[str, Any] | None = None

    def health(self) -> dict[str, Any]:
        return {"ready": True, "status": "READY", "model_ids": ["same-selected-model"]}

    def chat(self, **kwargs: Any) -> dict[str, Any]:
        self.chat_calls += 1
        self.last_kwargs = kwargs
        return {
            "content": json.dumps({"snapshot": {"leading_solution": "Use the existing shared authority."}}),
            "id": "baseline-1",
            "model": "same-selected-model",
            "usage": {"prompt_tokens": 10, "completion_tokens": 5},
            "timings": {"predicted_ms": 1.0},
            "finish_reason": "stop",
            "generation_schema_sha256": "a" * 64,
            "generation_schema_policy": "CANONICAL",
        }


@unittest.skipUnless(DEPS_AVAILABLE, "runtime dependencies unavailable")
class ResearchBaselineEndpointTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(__file__).resolve().parents[3]
        self.settings = Settings(
            repo_root=self.repo,
            state_dir=Path(self.temp.name),
            api_token="test-token",
            source_sha="8" * 40,
        )
        self.client = FakeBaselineLlama()
        self.engine = ProfileRuntimeEngine(self.settings, llama_client=self.client)  # type: ignore[arg-type]
        self.paths = [
            "profiles/systemic_root_cause_repair_lf/SKILL.md",
            "profiles/systemic_root_cause_repair_lf/contracts/main_contract.md",
        ]
        manifest = [
            {
                "ref": source_path,
                "content_sha256": sha256_text(
                    (self.repo / source_path).read_text(encoding="utf-8")
                ),
            }
            for source_path in sorted(self.paths)
        ]
        self.source_digest = "sha256:" + canonical_json_sha256(manifest)
        self.literal = "Find the systemic repair using only the supplied internal input before research."
        self.input_digest = "sha256:" + sha256_text(self.literal)
        self.contract = {
            "contract_version": "PROFILE_RESEARCH_BASELINE_BINDING_V1",
            "capture_stage": "PROFILE_DEFINED_PRE_RESEARCH",
            "snapshot_schema": {
                "type": "object",
                "additionalProperties": False,
                "required": [
                    "leading_solution",
                    "input_digest",
                    "profile_source_digest",
                    "evidence_refs",
                    "capture_stage",
                ],
                "properties": {
                    "leading_solution": {"type": "string", "minLength": 1},
                    "input_digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                    "profile_source_digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                    "evidence_refs": {
                        "type": "array",
                        "minItems": 2,
                        "items": {"type": "string", "minLength": 5},
                    },
                    "capture_stage": {"const": "PROFILE_DEFINED_PRE_RESEARCH"},
                },
            },
            "snapshot_binding_paths": {
                "input_digest": ["input_digest"],
                "profile_source_digest": ["profile_source_digest"],
                "evidence_refs": ["evidence_refs"],
                "capture_stage": ["capture_stage"],
            },
            "output_snapshot_path": ["research_assurance", "baseline_solution_snapshot"],
            "output_digest_path": ["research_assurance", "baseline_digest"],
            "profile_validator_binding": "PROFILE_OUTPUT_VALIDATOR_BOUND_V1",
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def request(self) -> "ResearchBaselineRequest":
        return ResearchBaselineRequest(
            request_id="11111111-2222-3333-4444-555555555555",
            profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            profile_slug="systemic_root_cause_repair_lf",
            profile_source_paths=self.paths,
            input_literal=self.literal,
            input_digest=self.input_digest,
            profile_source_digest=self.source_digest,
            research_baseline_contract=self.contract,
        )

    def test_baseline_uses_one_selected_model_call_and_canonical_digest(self) -> None:
        result = self.engine.run_research_baseline(self.request())
        inner = result["result"]
        self.assertEqual(inner["status"], "PASS")
        self.assertEqual(inner["baseline_model_call_count"], 1)
        self.assertFalse(inner["external_research_context_supplied"])
        self.assertEqual(self.client.chat_calls, 1)
        snapshot = inner["baseline_envelope"]["snapshot"]
        self.assertEqual(
            inner["baseline_envelope"]["baseline_digest"],
            "sha256:" + canonical_json_sha256(snapshot),
        )
        self.assertEqual(inner["runtime_model_id"], "same-selected-model")
        self.assertEqual(snapshot["input_digest"], self.input_digest)
        self.assertEqual(snapshot["profile_source_digest"], self.source_digest)
        self.assertEqual(snapshot["capture_stage"], "PROFILE_DEFINED_PRE_RESEARCH")
        self.assertEqual(
            snapshot["evidence_refs"],
            ["input:" + self.input_digest, "profile-source-manifest:" + self.source_digest],
        )
        generation_schema = (self.client.last_kwargs or {}).get("schema", {})
        generated_snapshot_schema = generation_schema.get("properties", {}).get("snapshot", {})
        generated_properties = generated_snapshot_schema.get("properties", {})
        self.assertNotIn("input_digest", generated_properties)
        self.assertNotIn("profile_source_digest", generated_properties)
        self.assertNotIn("evidence_refs", generated_properties)
        self.assertNotIn("capture_stage", generated_properties)
        self.assertNotIn("governed_operation", self.client.last_kwargs or {})

    def test_duplicate_snapshot_binding_path_is_rejected_before_model(self) -> None:
        bad = dict(self.contract)
        bad["snapshot_binding_paths"] = {
            "input_digest": ["input_digest"],
            "profile_source_digest": ["input_digest"],
        }
        with self.assertRaises(ValueError):
            ResearchBaselineRequest(
                request_id="11111111-2222-3333-4444-555555555555",
                profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
                profile_slug="systemic_root_cause_repair_lf",
                profile_source_paths=[self.path],
                input_literal=self.literal,
                input_digest=self.input_digest,
                profile_source_digest=self.source_digest,
                research_baseline_contract=bad,
            )

    def test_source_digest_mismatch_fails_before_model(self) -> None:
        request = self.request().model_copy(
            update={"profile_source_digest": "sha256:" + "0" * 64}
        )
        result = self.engine.run_research_baseline(request)
        self.assertEqual(result["result"]["status"], "FAIL")
        self.assertIn(
            "RESEARCH_BASELINE_PROFILE_SOURCE_DIGEST_MISMATCH",
            result["result"]["blocking_codes"],
        )
        self.assertEqual(self.client.chat_calls, 0)


if __name__ == "__main__":
    unittest.main()
