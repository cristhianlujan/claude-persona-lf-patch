from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.engine import (
    ProfileRuntimeEngine,
    _deterministic_ui_outcome,
    _ui_layout_strategy_from_literal,
)
from profile_runtime_api.llama import (
    LlamaTransportError,
    PersistentLlamaServerAdapter,
)
from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.settings import Settings


class NeverCalledClient:
    def health(self):
        raise AssertionError("health must not run after pre-inference budget rejection")

    def chat(self, **_kwargs):
        raise AssertionError("model must not run after pre-inference budget rejection")


class S26W2RepairTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo_root = Path(__file__).resolve().parents[3]
        self.settings = Settings(
            repo_root=self.repo_root,
            state_dir=Path(self.temp.name),
            api_token="test-token",
            source_sha="9" * 40,
        )
        self.engine = ProfileRuntimeEngine(self.settings)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def acceptance() -> dict:
        return {
            "task_mode": "CREATE_NEW",
            "implementation_readiness": "STRUCTURED_SPEC_READY_FOR_NEXT_AGENT",
            "minimum_component_count": 9,
            "minimum_hierarchy_depth_edges": 3,
            "minimum_risk_control_count": 4,
            "minimum_state_map_coverage_ratio": 1.0,
            "minimum_variant_guard_coverage_ratio": 1.0,
            "required_component_ids": [
                "header_search", "category_navigation", "featured_services", "service_cards",
                "service_card_template", "service_title", "service_provider", "service_price", "service_cta",
            ],
            "required_design_intents": ["clear", "professional", "easy_to_navigate"],
            "required_responsive_modes": ["desktop", "mobile"],
            "required_sections": ["header", "categories", "featured_services", "service_cards"],
            "required_service_leaf_components": ["service_title", "service_provider", "service_price", "service_cta"],
            "required_state_component_ids": [
                "header_search", "category_navigation", "featured_services", "service_cards", "service_cta",
            ],
            "required_source_bindings": {
                "category_navigation.items": "DATA_BOUND",
                "featured_services.items": "DATA_BOUND",
                "service_card_template.fields": "title|provider|price|call_to_action",
                "service_card_template.values": "DATA_BOUND",
                "service_cards.items": "DATA_BOUND",
                "service_cta.destination": "UNRESOLVED_UNTIL_SOURCE",
                "service_cta.label": "DATA_BOUND:call_to_action",
                "service_price.format": "SOURCE_DEFINED",
                "service_price.value": "DATA_BOUND:price",
                "service_provider.value": "DATA_BOUND:provider",
                "service_title.value": "DATA_BOUND:title",
            },
        }

    def task(self, literal: str) -> ProfileTask:
        return ProfileTask(
            request_id="S26-W2-REPAIR-TEST",
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_source_paths=["profiles/ui_architect/SKILL.md"],
            input_literal=literal,
            input_fields={
                "output_contract_version": "UI_PRODUCTION_SPEC_V6",
                "execution_mode": "SANDBOX",
                "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
                "gate_f_acceptance": self.acceptance(),
            },
            runtime_output_mode="UI_PRODUCTION_SPEC",
        )

    def test_explicit_literal_maps_to_bounded_layout_strategy(self) -> None:
        self.assertEqual(
            _ui_layout_strategy_from_literal("Tarjetas densas en tres columnas"),
            "DENSE_GRID_STACK",
        )
        self.assertEqual(
            _ui_layout_strategy_from_literal("Prioridad mobile, mobile-first"),
            "MOBILE_PRIORITY_STACK",
        )
        self.assertIsNone(_ui_layout_strategy_from_literal("Marketplace de servicios profesional"))

    def test_explicit_dense_layout_overrides_model_standard_choice(self) -> None:
        raw = json.dumps({"v": 5, "d": {"l": "STANDARD_GRID_STACK"}})
        final_raw, receipt = self.engine._materialize_runtime_output(
            task=self.task("Diseña tarjetas densas en tres columnas para desktop."),
            model_raw_output=raw,
            governed_receipt={"runtime_typed_context_sha256": "c" * 64},
        )
        final = json.loads(final_raw)
        self.assertEqual(receipt["semantic_transport"], "UICT5")
        self.assertIn("compact multi-column grid", final["deliverable_created"]["layout_grid"]["desktop"])
        self.assertEqual(final["score"]["total"], 20)
        self.assertEqual(final["self_verdict"], "PASS_TO_QUALITY_PACK_CANDIDATE")

    def test_layout_flow_hierarchy_contradiction_blocks_strict_uict5_acceptance(self) -> None:
        raw = json.dumps({"v": 5, "d": {"l": "STANDARD_GRID_STACK"}})
        final_raw, _ = self.engine._materialize_runtime_output(
            task=self.task("Diseña un marketplace de servicios profesional."),
            model_raw_output=raw,
            governed_receipt={"runtime_typed_context_sha256": "c" * 64},
        )
        final = json.loads(final_raw)
        deliverable = final["deliverable_created"]
        deliverable["layout_grid"]["flow"].append("service_title")
        boundary = self.engine.repository.load_ui_composer_boundary()
        composer = boundary.build_composer_payload(deliverable)
        outcome = _deterministic_ui_outcome(
            deliverable=deliverable,
            acceptance=self.acceptance(),
            composer_payload=composer,
            strict_layout_coherence=True,
        )
        self.assertEqual(outcome["score"]["layout_precision"], 0)
        self.assertEqual(outcome["self_verdict"], "BLOCKED")

    def test_large_ui_literal_fails_before_model_or_health_call(self) -> None:
        binding = SchemaBinding(
            payload={"type": "object"},
            raw=b"{}",
            sha256="a" * 64,
            source_refs=("schema.json",),
            mode="UI_PRODUCTION_SPEC",
        )
        adapter = PersistentLlamaServerAdapter(
            settings=self.settings,
            client=NeverCalledClient(),  # type: ignore[arg-type]
            schema=binding,
            structural_context={},
            image_bytes=None,
            image_media_type=None,
        )
        with self.assertRaises(LlamaTransportError) as ctx:
            adapter.execute({"input_literal": "x" * 10001})
        self.assertEqual(ctx.exception.code, "LLAMA_UI_INPUT_TOKEN_PROXY_BUDGET_EXCEEDED")


if __name__ == "__main__":
    unittest.main()
