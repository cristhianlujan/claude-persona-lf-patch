from __future__ import annotations

import unittest
from pathlib import Path

from pydantic import ValidationError

from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import RepositoryBindings, RepositoryError


class RuntimeOutputModeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.repository = RepositoryBindings(self.repo_root, max_prompt_chars=120_000)

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


if __name__ == "__main__":
    unittest.main()
