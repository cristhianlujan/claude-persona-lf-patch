from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from typing import Any

# Work containers may omit optional service wheels. Use a narrow schema stub only
# there; deployed/CI environments exercise the real pinned jsonschema package.
if importlib.util.find_spec("jsonschema") is None:
    jsonschema_stub = types.ModuleType("jsonschema")

    class SchemaError(Exception):
        pass

    class Draft202012Validator:
        @staticmethod
        def check_schema(_schema: Any) -> None:
            return None

        def __init__(self, _schema: Any) -> None:
            pass

        def iter_errors(self, _payload: Any) -> list[Any]:
            return []

    jsonschema_stub.SchemaError = SchemaError
    jsonschema_stub.Draft202012Validator = Draft202012Validator
    sys.modules["jsonschema"] = jsonschema_stub

from profile_runtime_api.cache import StructuralCache
from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.hashing import canonical_json_sha256
from profile_runtime_api.models import (
    Artifact,
    BatchRequest,
    ExecuteRequest,
    InputGovernanceReceipt,
    ProfileTask,
)
from profile_runtime_api.settings import Settings
from profile_runtime_api.structural import PreparedContext


def valid_quality_output() -> str:
    return json.dumps(
        {
            "review_id": "review-B2B-CARGA-001",
            "reviewed_artifact": "B2B-CARGA-001 exact candidate raster",
            "verdict": "BLOCK_PIPELINE",
            "score_breakdown": {
                "contract_schema_compliance": 5,
                "evidence_integrity": 4,
                "lf_safety_governance": 5,
                "handoff_readiness": 2,
                "leakage_scope_control": 5,
                "total": 21,
            },
            "evidence_map": [
                {
                    "ref": "visible://page-header",
                    "observation": "Historial de cargas is visible in the page header.",
                }
            ],
            "blocking_codes": ["INDEPENDENT_SEMANTIC_REVIEW_NOT_EXECUTED"],
            "repair_actions": [],
            "remaining_risks": ["No independent semantic authority was executed."],
            "next_gate": "STOP",
            "routing": {
                "activation_path": "DIRECT",
                "via": "ORCHESTRATOR",
                "pipeline_action": "BLOCK_PIPELINE",
                "resolution_target": "NONE",
            },
        },
        ensure_ascii=False,
    )


class FakeLlamaClient:
    def __init__(self, output: str) -> None:
        self.output = output
        self.chat_calls = 0

    def health(self) -> dict[str, Any]:
        return {"ready": True, "status": "READY", "model_ids": ["fake-local-model"]}

    def chat(self, **_kwargs: Any) -> dict[str, Any]:
        self.chat_calls += 1
        return {
            "content": self.output,
            "id": f"completion-{self.chat_calls}",
            "model": "fake-local-model",
            "usage": {"prompt_tokens": 10, "completion_tokens": 10},
            "timings": {"predicted_ms": 1.0},
            "finish_reason": "stop",
        }


class FakeStructuralPipeline:
    def __init__(self) -> None:
        self.calls = 0

    def validate(self) -> None:
        return None

    def prepare(self, _artifact: Any, _governance: Any) -> PreparedContext:
        self.calls += 1
        return PreparedContext(
            cache_key="p0v3:" + "a" * 64,
            cache_hit=False,
            pack={"schema": "test-pack/v1", "pack_sha256": "b" * 64},
            prepare_ms=1.0,
        )


class EngineGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(__file__).resolve().parents[3]
        self.settings = Settings(
            repo_root=self.repo,
            state_dir=Path(self.temp.name),
            api_token="test-token",
            source_sha="8e2188bb40c8760da73163497ffb71f1d48d11d8",
        )
        context = {"screen": "B2B-CARGA-001", "authority": "CURRENT_TEST_RECEIPT"}
        self.governance = InputGovernanceReceipt(
            receipt_ref="receipt://test/current",
            current=True,
            ready=True,
            context_sha256=canonical_json_sha256(context),
            context=context,
            status="READY",
        )
        self.artifact = Artifact(
            screen_code="B2B-CARGA-001",
            filename="candidate.png",
            image_sha256="e" * 64,
            width_px=1600,
            height_px=1000,
            observations=[],
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def quality_task(request_id: str) -> ProfileTask:
        return ProfileTask(
            request_id=request_id,
            profile_code="PERFIL-QUALITY-PACK",
            profile_slug="quality_pack",
            profile_source_paths=["profiles/quality_pack/SKILL.md"],
            input_literal=(
                "Evaluate the exact governed candidate using the supplied observed context."
            ),
        )

    def engine(self, output: str) -> tuple[ProfileRuntimeEngine, FakeStructuralPipeline]:
        pipeline = FakeStructuralPipeline()
        cache = StructuralCache(Path(self.temp.name) / "cache")
        engine = ProfileRuntimeEngine(
            self.settings,
            llama_client=FakeLlamaClient(output),  # type: ignore[arg-type]
            cache=cache,
            structural_pipeline=pipeline,  # type: ignore[arg-type]
        )
        engine.initialize()
        return engine, pipeline

    def test_valid_completion_keeps_three_gates_separate(self) -> None:
        engine, _pipeline = self.engine(valid_quality_output())
        request = ExecuteRequest(
            artifact=self.artifact,
            input_governance=self.governance,
            profile=self.quality_task("quality-valid-1"),
        )
        result = engine.run_execute(request)["result"]
        self.assertEqual(result["runtime_completion"]["status"], "PASS")
        self.assertEqual(result["profile_contract_valid"]["status"], "PASS")
        self.assertEqual(result["semantic_utility"]["status"], "PASS")
        self.assertFalse(result["downstream_authorized"])

    def test_transport_success_does_not_promote_label_only_output(self) -> None:
        engine, _pipeline = self.engine("PRODUCT_DIRECTION_SPEC")
        task = ProfileTask(
            request_id="product-label-only-1",
            profile_code="PERFIL-PRODUCT-DIRECTOR-LF",
            profile_slug="product_director_lf",
            profile_source_paths=["profiles/product_director_lf/SKILL.md"],
            input_literal="Evaluate the governed candidate without inventing business facts.",
        )
        result = engine.run_execute(
            ExecuteRequest(
                artifact=self.artifact,
                input_governance=self.governance,
                profile=task,
            )
        )["result"]
        self.assertEqual(result["runtime_completion"]["status"], "PASS")
        self.assertEqual(result["profile_contract_valid"]["status"], "FAIL")
        self.assertEqual(result["semantic_utility"]["status"], "NOT_EVALUATED")

    def test_batch_prepares_context_once_and_continues_all_profiles(self) -> None:
        engine, pipeline = self.engine(valid_quality_output())
        request = BatchRequest(
            batch_id="batch-context-reuse-1",
            artifact=self.artifact,
            input_governance=self.governance,
            profiles=[self.quality_task("quality-1"), self.quality_task("quality-2")],
        )
        result = engine.run_batch(request)
        self.assertEqual(pipeline.calls, 1)
        self.assertEqual(result["context"]["reuse_count"], 1)
        self.assertFalse(result["profile_results"][0]["context"]["reused_within_batch"])
        self.assertTrue(result["profile_results"][1]["context"]["reused_within_batch"])
        self.assertEqual(result["summary"]["runtime_completion_pass"], 2)

    def test_structural_failure_still_returns_all_three_gates(self) -> None:
        engine, pipeline = self.engine(valid_quality_output())

        def fail_prepare(_artifact: Any, _governance: Any) -> PreparedContext:
            error = RuntimeError("structural failure")
            error.code = "STRUCTURAL_CONTEXT_TEST_FAILURE"  # type: ignore[attr-defined]
            raise error

        pipeline.prepare = fail_prepare  # type: ignore[method-assign]
        result = engine.run_execute(
            ExecuteRequest(
                artifact=self.artifact,
                input_governance=self.governance,
                profile=self.quality_task("quality-structural-failure-1"),
            )
        )["result"]
        self.assertEqual(result["runtime_completion"]["status"], "FAIL")
        self.assertEqual(
            result["runtime_completion"]["blocking_codes"],
            ["STRUCTURAL_CONTEXT_TEST_FAILURE"],
        )
        self.assertEqual(result["profile_contract_valid"]["status"], "NOT_EVALUATED")
        self.assertEqual(result["semantic_utility"]["status"], "NOT_EVALUATED")

    def test_full_image_model_path_is_disabled_by_default(self) -> None:
        engine, _pipeline = self.engine(valid_quality_output())
        task = self.quality_task("quality-full-image-blocked-1").model_copy(
            update={"send_image_to_model": True}
        )
        result = engine.run_execute(
            ExecuteRequest(
                artifact=self.artifact,
                input_governance=self.governance,
                profile=task,
            )
        )["result"]
        self.assertEqual(result["runtime_completion"]["status"], "FAIL")
        self.assertEqual(
            result["runtime_completion"]["blocking_codes"],
            ["FULL_IMAGE_MODEL_PATH_DISABLED"],
        )


if __name__ == "__main__":
    unittest.main()
