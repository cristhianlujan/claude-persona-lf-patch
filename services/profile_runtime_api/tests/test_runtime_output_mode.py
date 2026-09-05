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
        self.assertEqual(gate["schema_mode"], "UI_FOCUSED_DECISION")
        utility = self.gates.semantic_utility(
            profile_slug="ui_architect", payload=payload, contract_gate=gate
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
