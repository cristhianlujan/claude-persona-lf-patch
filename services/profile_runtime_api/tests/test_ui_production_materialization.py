from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.llama import LlamaTransportError
from profile_runtime_api.models import ProfileTask
from profile_runtime_api.settings import Settings


class UIProductionMaterializationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo_root = Path(__file__).resolve().parents[3]
        self.settings = Settings(
            repo_root=self.repo_root, state_dir=Path(self.temp.name), api_token="test-token",
            source_sha="f" * 40,
        )
        self.engine = ProfileRuntimeEngine(self.settings)
        self.task = ProfileTask(
            request_id="S26-MAT-001", profile_code="PERFIL-UI-ARCHITECT", profile_slug="ui_architect",
            profile_source_paths=["profiles/ui_architect/SKILL.md"],
            input_literal="Create a compact production UI specification.",
            input_fields={
                "output_contract_version": "UI_PRODUCTION_SPEC_V6",
                "execution_mode": "SANDBOX",
                "policy_snapshot_sha256": "a" * 64,
                "bootstrap_context_sha256": "b" * 64,
            },
            runtime_output_mode="UI_PRODUCTION_SPEC",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def candidate() -> dict:
        node = {
            "zone_id": "main", "component_id": "service_card", "component_type": "card",
            "role": "Render a source-bound service card.", "content": {"value": "DATA_BOUND"},
            "visual_priority": "HIGH", "color_tokens": ["surface_default"],
            "typography": "body", "spacing": "compact", "state": "bound",
            "allowed_variants": ["default"], "blocked_variants": ["invented_data"],
        }
        deliverable = {
            "screen_definition": {"task_mode": "CREATE_NEW"},
            "component_tree": [node],
            "layout_grid": {"flow": ["service_card"]},
            "visual_hierarchy": [{"parent_id": "screen", "child_ids": ["service_card"]}],
            "state_map": {"service_card": {"default": "bound"}},
            "token_map": {"surface": ["surface_default"]},
            "spacing_typography": {"spacing": "compact", "typography": "body"},
            "density_rules": ["One card template per source-bound service record."],
            "risk_controls": ["Do not invent service data."],
            "prompt_constraints": ["Keep the output implementation-ready."],
        }
        score = {
            "layout_precision": 0, "visual_hierarchy": 0, "lf_system_fidelity": 0,
            "state_mapping": 0, "handoff_quality": 0, "total": 0,
            "evidence_by_criterion": {
                key: {"refs": ["component_tree"], "summary": "Evidence is present in the component tree."}
                for key in ["layout_precision", "visual_hierarchy", "lf_system_fidelity", "state_mapping", "handoff_quality"]
            },
        }
        return {
            "worker": "ui_architect", "output_type": "PRODUCTION_UI_SPEC",
            "deliverable_created": deliverable, "score": score,
            "handoff_to_next": {"recipient": "composer", "payload_ref": "composer_payload", "status": "READY"},
            "self_verdict": "BLOCKED",
        }

    @staticmethod
    def compact_candidate() -> dict:
        return {
            "w": "ui_architect",
            "o": "PRODUCTION_UI_SPEC",
            "d": {
                "s": ["CREATE_NEW", "marketplace", "source services", "services", "READY", "clear"],
                "c": [[
                    "main", "service_card", "card", "source service", [["value", "DATA_BOUND"]],
                    "HIGH", "surface_default", "body", "compact", "bound", "default", "invented_data",
                ]],
                "l": ["service_card", "responsive grid", "single column"],
                "h": ["screen", "service_card"],
                "m": [["service_card", "default", "bound"]],
                "t": ["surface_default", "text_primary", "action_primary", "border_subtle", "SEMANTIC_ROLE_ONLY"],
                "p": ["compact", "body", "RELATIVE_GUIDANCE"],
                "y": ["one source card per record"],
                "r": ["do not invent service data"],
                "q": ["keep implementation ready"],
            },
            "x": [0, 0, 0, 0, 0],
            "n": ["composer", "READY"],
            "v": "BLOCKED",
        }

    @staticmethod
    def gate_f_acceptance() -> dict:
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

    @classmethod
    def semantic_candidate(cls) -> dict:
        return {
            "d": {
                "u": "Present a clear service marketplace with source-bound discovery and service actions.",
                "z": [0, 1, 2, 3, 3, 3, 3, 3, 3],
                "t": [0, 1, 2, 3, 4, 5, 5, 6, 7],
                "p": [2, 1, 2, 2, 1, 1, 1, 1, 2],
                "h": [3, 4, 8],
                "m": [
                    ["default", "search ready"],
                    ["selected", "category selected"],
                    ["default", "featured services bound"],
                    ["default", "service collection bound"],
                    ["enabled", "destination unresolved until source"],
                ],
                "l": ["responsive multi-column service grid", "single-column stacked service flow"],
                "k": ["surface_default", "text_primary", "action_primary", "border_subtle"],
                "a": ["body", "heading", "compact", "regular"],
                "y": ["Keep one reusable service-card template and avoid repeated metadata."],
            }
        }

    def gate_f_task(self) -> ProfileTask:
        return ProfileTask(
            request_id="S26-MAT-GATE-F-001",
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_source_paths=["profiles/ui_architect/SKILL.md"],
            input_literal="Create the governed service marketplace production UI specification.",
            input_fields={
                "output_contract_version": "UI_PRODUCTION_SPEC_V6",
                "execution_mode": "SANDBOX",
                "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
                "policy_snapshot_sha256": "a" * 64,
                "bootstrap_context_sha256": "b" * 64,
                "gate_f_acceptance": self.gate_f_acceptance(),
            },
            runtime_output_mode="UI_PRODUCTION_SPEC",
        )

    def test_semantic_transport_materializes_known_structure_score_handoff_and_verdict(self) -> None:
        raw = json.dumps(self.semantic_candidate(), ensure_ascii=False, separators=(",", ":"))
        final_raw, receipt = self.engine._materialize_runtime_output(
            task=self.gate_f_task(), model_raw_output=raw,
            governed_receipt={"runtime_typed_context_sha256": "c" * 64},
        )
        final = json.loads(final_raw)
        deliverable = final["deliverable_created"]
        self.assertEqual(receipt["semantic_transport"], "UICT2")
        self.assertTrue(receipt["transport_decoded"])
        self.assertEqual(final["worker"], "ui_architect")
        self.assertEqual(final["output_type"], "PRODUCTION_UI_SPEC")
        self.assertEqual(
            [row["component_id"] for row in deliverable["component_tree"]],
            self.gate_f_acceptance()["required_component_ids"],
        )
        self.assertEqual(deliverable["component_tree"][1]["content"]["items"], "DATA_BOUND")
        self.assertEqual(
            deliverable["component_tree"][4]["content"]["fields"],
            ["title", "provider", "price", "call_to_action"],
        )
        self.assertEqual(final["score"]["total"], 20)
        self.assertEqual(final["self_verdict"], "PASS_TO_QUALITY_PACK_CANDIDATE")
        self.assertEqual(final["handoff_to_next"]["payload_ref"], "composer_payload")
        self.assertTrue(all(receipt["deterministic_acceptance"].values()))
        self.assertEqual(receipt["model_generated_root_keys"], [])
        self.assertEqual(receipt["model_transport_root_keys"], ["d"])
        self.assertIn("source_bindings", receipt["deterministic_derivations"])
        self.assertIn("score", receipt["deterministic_derivations"])
        risks = " ".join(deliverable["risk_controls"])
        self.assertIn("service_cta.destination", risks)
        self.assertIn("service_price.format", risks)
        self.assertEqual(final["composer_payload"]["component_tree"], deliverable["component_tree"])

    def test_semantic_transport_does_not_accept_missing_authority_for_known_skeleton(self) -> None:
        task = self.gate_f_task()
        task.input_fields["gate_f_acceptance"] = {"task_mode": "CREATE_NEW"}
        with self.assertRaises(LlamaTransportError) as ctx:
            self.engine._materialize_runtime_output(
                task=task,
                model_raw_output=json.dumps(self.semantic_candidate()),
                governed_receipt={"runtime_typed_context_sha256": "c" * 64},
            )
        self.assertEqual(ctx.exception.code, "UI_PRODUCTION_SEMANTIC_TRANSPORT_ACCEPTANCE_INCOMPLETE")

    def test_compact_transport_decodes_before_deterministic_projection(self) -> None:
        compact = self.compact_candidate()
        raw = json.dumps(compact, ensure_ascii=False, separators=(",", ":"))
        final_raw, receipt = self.engine._materialize_runtime_output(
            task=self.task, model_raw_output=raw,
            governed_receipt={"runtime_typed_context_sha256": "c" * 64},
        )
        final = json.loads(final_raw)
        self.assertTrue(receipt["transport_decoded"])
        self.assertEqual(receipt["semantic_transport"], "UICT1")
        self.assertEqual(final["deliverable_created"]["component_tree"][0]["component_id"], "service_card")
        self.assertEqual(final["score"]["total"], 0)
        self.assertEqual(final["handoff_to_next"]["payload_ref"], "composer_payload")
        self.assertEqual(final["composer_payload"]["component_tree"], final["deliverable_created"]["component_tree"])

    def test_compact_transport_blocks_internal_content_key_before_composer(self) -> None:
        compact = self.compact_candidate()
        compact["d"]["c"][0][4] = [["score", "leak"]]
        with self.assertRaises(LlamaTransportError) as ctx:
            self.engine._materialize_runtime_output(
                task=self.task, model_raw_output=json.dumps(compact),
                governed_receipt={"runtime_typed_context_sha256": "c" * 64},
            )
        self.assertEqual(ctx.exception.code, "UI_PRODUCTION_TRANSPORT_INTERNAL_KEY_FORBIDDEN")

    def test_runtime_adds_only_deterministic_projection_fields(self) -> None:
        candidate = self.candidate()
        raw = json.dumps(candidate, ensure_ascii=False, separators=(",", ":"))
        final_raw, receipt = self.engine._materialize_runtime_output(
            task=self.task, model_raw_output=raw,
            governed_receipt={"runtime_typed_context_sha256": "c" * 64},
        )
        final = json.loads(final_raw)
        self.assertEqual(final["output_contract_version"], "UI_PRODUCTION_SPEC_V6")
        self.assertEqual(final["governance_envelope"]["schema"], "LF_UI_GOVERNANCE_ENVELOPE_V1")
        self.assertEqual(final["governance_envelope"]["render_policy"], "NON_RENDER")
        self.assertEqual(final["composer_payload"]["component_tree"], candidate["deliverable_created"]["component_tree"] )
        self.assertEqual(receipt["mode"], "UI_PRODUCTION_DETERMINISTIC_PROJECTION_V1")
        self.assertFalse(receipt["semantic_payload_mutated"])
        self.assertEqual(receipt["deterministic_fields_added"], ["composer_payload", "governance_envelope", "output_contract_version"])
        self.assertLess(len(raw), len(final_raw))

    def test_conflicting_model_generated_projection_fails_closed(self) -> None:
        candidate = self.candidate()
        candidate["composer_payload"] = {"invented": True}
        with self.assertRaises(LlamaTransportError) as ctx:
            self.engine._materialize_runtime_output(
                task=self.task, model_raw_output=json.dumps(candidate),
                governed_receipt={"runtime_typed_context_sha256": "c" * 64},
            )
        self.assertEqual(ctx.exception.code, "UI_PRODUCTION_DETERMINISTIC_FIELD_CONFLICT")


if __name__ == "__main__":
    unittest.main()
