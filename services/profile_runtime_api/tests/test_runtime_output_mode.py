from __future__ import annotations

import json
import unittest
from pathlib import Path

from pydantic import ValidationError

from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import RepositoryBindings, RepositoryError
from profile_runtime_api.validation import OutputGates


class RuntimeOutputModeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.repository = RepositoryBindings(self.repo_root, max_prompt_chars=120_000)
        self.gates = OutputGates(self.repository)

    @staticmethod
    def ui_task(**changes: object) -> ProfileTask:
        payload: dict[str, object] = {
            "request_id": "mode-test-ui",
            "profile_code": "PERFIL-UI-ARCHITECT",
            "profile_slug": "ui_architect",
            "profile_source_paths": ["profiles/ui_architect/SKILL.md"],
            "input_literal": "Focused decision only.",
            "runtime_output_mode": "UI_FOCUSED_DECISION",
        }
        payload.update(changes)
        return ProfileTask.model_validate(payload)

    @staticmethod
    def focused_payload() -> dict[str, object]:
        return {
            "decision_subject": "horizontal table overflow cue",
            "selected_visual_type": "subtle horizontal scroll affordance at table edge",
            "base_color_or_surface": "existing neutral surface token",
            "size_or_coverage": "table viewport edge only",
            "density_limits": "one cue per overflowing table viewport",
            "depth_style": "no added elevation",
            "visual_weight": "secondary to table content and row actions",
            "position_behavior": "anchored to horizontal overflow edge",
            "relationship_to_main_element": "supports table navigation without replacing table semantics",
            "implementation_format": "CSS overflow cue and existing component token",
            "hard_exclusions": ["no new business rules", "no hidden row actions"],
            "short_generator_prompt": "not applicable; implement as CSS affordance",
            "status": "CANDIDATE_READ_ONLY",
        }

    def test_ui_focused_mode_is_typed_and_allowed(self) -> None:
        task = self.ui_task()
        self.assertEqual(task.runtime_output_mode, "UI_FOCUSED_DECISION")

    def test_ui_mode_on_non_ui_profile_fails_closed(self) -> None:
        with self.assertRaises(ValidationError):
            ProfileTask.model_validate(
                {
                    "request_id": "mode-test-quality",
                    "profile_code": "PERFIL-QUALITY-PACK",
                    "profile_slug": "quality_pack",
                    "profile_source_paths": ["profiles/quality_pack/SKILL.md"],
                    "input_literal": "Review evidence.",
                    "runtime_output_mode": "UI_FOCUSED_DECISION",
                }
            )

    def test_ui_focused_mode_binds_exact_single_schema(self) -> None:
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        self.assertEqual(binding.mode, "UI_FOCUSED_DECISION")
        self.assertEqual(
            binding.source_refs,
            ("profiles/ui_architect/schemas/ui_focused_decision.schema.json",),
        )
        self.assertEqual(binding.payload.get("title"), "UI Architect Focused Decision Spec")
        self.assertNotIn("anyOf", binding.payload)

    def test_ui_auto_preserves_aggregate_fallback(self) -> None:
        binding = self.repository.runtime_schema("ui_architect", "AUTO")
        self.assertEqual(binding.mode, "AUTO")
        self.assertEqual(len(binding.payload.get("anyOf", [])), 3)
        self.assertEqual(len(binding.source_refs), 3)

    def test_unsupported_repository_mode_fails_closed(self) -> None:
        with self.assertRaises(RepositoryError) as ctx:
            self.repository.runtime_schema("ui_architect", "NOT_A_MODE")
        self.assertEqual(ctx.exception.code, "RUNTIME_OUTPUT_MODE_UNSUPPORTED")

    def test_focused_mode_uses_schema_not_production_only_validator(self) -> None:
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, payload = self.gates.contract(
            profile_slug="ui_architect",
            raw_output=json.dumps(self.focused_payload()),
            schema=binding,
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=payload, contract_gate=gate
        )
        self.assertEqual(utility["status"], "PASS", utility)

    def test_focused_utility_rejects_selected_treatment_also_excluded(self) -> None:
        payload = self.focused_payload()
        payload["selected_visual_type"] = "horizontal overflow"
        payload["hard_exclusions"] = ["horizontal overflow", "no hidden row actions"]
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "FAIL", utility)
        self.assertIn("UI_FOCUSED_SELECTED_TREATMENT_EXCLUDED", utility["blocking_codes"])

    def test_focused_utility_rejects_generic_non_concrete_fields(self) -> None:
        payload = self.focused_payload()
        payload.update(
            {
                "size_or_coverage": "medium",
                "density_limits": "medium",
                "depth_style": "thin",
                "visual_weight": "medium",
                "relationship_to_main_element": "above",
                "implementation_format": "css",
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "FAIL", utility)
        self.assertIn("UI_FOCUSED_SIZE_OR_COVERAGE_NON_CONCRETE", utility["blocking_codes"])
        self.assertIn("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE", utility["blocking_codes"])
        self.assertIn("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE", utility["blocking_codes"])

    def test_focused_utility_rejects_observed_enum_false_positive(self) -> None:
        payload = self.focused_payload()
        payload.update(
            {
                "decision_subject": "UI decision",
                "selected_visual_type": "horizontal overflow",
                "base_color_or_surface": "wide operational table",
                "size_or_coverage": "horizontal overflow",
                "density_limits": "no more than one treatment per affected component",
                "depth_style": "subtle",
                "visual_weight": "discovery without hiding row actions",
                "relationship_to_main_element": "without adding business rules",
                "implementation_format": "JSON object",
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "FAIL", utility)
        self.assertIn("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE", utility["blocking_codes"])
        self.assertIn("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3", utility["blocking_codes"])

    def test_focused_utility_rejects_observed_cross_field_copy(self) -> None:
        payload = self.focused_payload()
        repeated = "1px accent border on the table header"
        payload.update(
            {
                "decision_subject": "horizontal overflow in operational table",
                "selected_visual_type": repeated,
                "size_or_coverage": repeated,
                "density_limits": repeated,
                "base_color_or_surface": "existing white table surface",
                "depth_style": "no added elevation; preserve existing table shadow token",
                "visual_weight": "secondary to table data and primary actions",
                "relationship_to_main_element": "supports table navigation without hiding row actions",
                "implementation_format": "CSS border token on the table header",
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "FAIL", utility)
        self.assertIn("UI_FOCUSED_CROSS_FIELD_DUPLICATION", utility["blocking_codes"])

    def test_focused_utility_rejects_numeric_only_density(self) -> None:
        payload = self.focused_payload()
        payload["density_limits"] = "100"
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "FAIL", utility)
        self.assertIn("UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY", utility["blocking_codes"])

    def test_focused_utility_accepts_concrete_spanish_fields(self) -> None:
        payload = self.focused_payload()
        payload.update(
            {
                "decision_subject": "estado del método de pago seleccionado",
                "selected_visual_type": "borde de acento de 2px con ícono de check en la tarjeta seleccionada",
                "base_color_or_surface": "superficie blanca existente con token de color de acento",
                "size_or_coverage": "solo el borde de la tarjeta seleccionada y el área del ícono",
                "density_limits": "un borde y un ícono por tarjeta de pago seleccionada",
                "depth_style": "sin sombra ni elevación adicional",
                "visual_weight": "secundario frente al monto y al CTA primario",
                "relationship_to_main_element": "apoya el estado de la tarjeta sin competir con el CTA primario",
                "implementation_format": "token CSS de borde más componente de ícono existente en la tarjeta",
                "hard_exclusions": ["no nuevo CTA primario", "no cambios fuera del selector"],
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "PASS", utility)

    def test_focused_utility_accepts_compact_design_tokens_and_css_values(self) -> None:
        payload = self.focused_payload()
        payload.update(
            {
                "decision_subject": "search field selection treatment",
                "selected_visual_type": "check icon",
                "base_color_or_surface": "primary-600",
                "size_or_coverage": "button bounds",
                "density_limits": "1 icon",
                "depth_style": "0 1px 2px rgba(0,0,0,.08)",
                "visual_weight": "font-weight 600",
                "relationship_to_main_element": "beside the search input",
                "implementation_format": "Tailwind overflow-x-auto utility",
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "PASS", utility)

    def test_focused_utility_accepts_compact_spanish_design_tokens(self) -> None:
        payload = self.focused_payload()
        payload.update(
            {
                "decision_subject": "estado del buscador activo",
                "selected_visual_type": "borde de acento con ícono",
                "base_color_or_surface": "primario-600",
                "size_or_coverage": "solo límites del botón",
                "density_limits": "1 ícono",
                "depth_style": "sombra 0 1px 2px rgba(0,0,0,.08)",
                "visual_weight": "peso tipográfico 600",
                "relationship_to_main_element": "junto al buscador",
                "implementation_format": "clase CSS .seleccionado en botón",
            }
        )
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, parsed = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload, ensure_ascii=False), schema=binding
        )
        self.assertEqual(gate["status"], "PASS", gate)
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )
        self.assertEqual(utility["status"], "PASS", utility)

    def test_auto_mode_does_not_weaken_existing_production_validator(self) -> None:
        binding = self.repository.runtime_schema("ui_architect", "AUTO")
        gate, _ = self.gates.contract(
            profile_slug="ui_architect",
            raw_output=json.dumps(self.focused_payload()),
            schema=binding,
        )
        self.assertEqual(gate["status"], "FAIL")
        self.assertIn("OUTPUT_MODE_INVALID", gate["blocking_codes"])

    def test_focused_schema_still_fails_closed_on_missing_required_field(self) -> None:
        payload = self.focused_payload()
        del payload["implementation_format"]
        binding = self.repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
        gate, _ = self.gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        self.assertEqual(gate["status"], "FAIL")
        self.assertIn("JSON_SCHEMA_VALIDATION_FAILED", gate["blocking_codes"])


if __name__ == "__main__":
    unittest.main()
