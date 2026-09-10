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
