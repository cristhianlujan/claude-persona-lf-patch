from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "services/profile_runtime_api/scripts/runtime_envelope_materializer.py"
spec = importlib.util.spec_from_file_location("runtime_envelope_materializer", MODULE_PATH)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def router_advisory() -> dict:
    return {
        "applicable": True,
        "status": "ADVISORY_READ_ONLY",
        "blocking_code": None,
        "decision": "ADVISORY",
        "continuation_allowed": True,
        "subject_mode": "NON_CANONICAL_ARTIFACT",
        "required_by_adapters": ["ADAPTER_LF_SHELL_PROFILE"],
        "required_artifact_binding": ["artifact_ref", "artifact_sha256", "dimensions"],
        "constraints": {
            "operation_must_equal": "EJECUCION_PERFIL_LF",
            "read_only": True,
            "no_write": True,
            "no_promotion": True,
            "canonical_registration_required": False,
            "artifact_binding_required_before_profile_execution": True,
        },
        "resume_via": "EJECUCION_PERFIL_LF/input_validate",
    }


def envelope() -> dict:
    return {
        "artifact_set": {
            "schema": "NON_CANONICAL_ARTIFACT_SET_V1",
            "subject_mode": "NON_CANONICAL_ARTIFACT",
            "artifacts": [
                {
                    "artifact_ref": "drive:a",
                    "artifact": {
                        "screen_code": "NONCANONICAL_ARTIFACT_1",
                        "filename": "a.png",
                        "image_sha256": "a" * 64,
                        "width_px": 1600,
                        "height_px": 1000,
                        "observations": [{"id": 1, "text": "Nueva carga", "bbox": [280, 135, 180, 42], "conf": 99}],
                    },
                }
            ],
        },
        "input_governance": router_advisory(),
        "profile": {
            "request_id": "req-1",
            "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": "PERFIL-UI-ARCHITECT",
            "profile_slug": "ui_architect",
            "profile_source_paths": ["profiles/ui_architect/SKILL.md"],
            "input_literal": "Compare read-only artifacts.",
            "runtime_output_mode": "UI_FOCUSED_DECISION",
            "required_adapter_codes": ["ADAPTER_LF_SHELL_PROFILE"],
            "send_image_to_model": False,
        },
    }


def adapters() -> list[dict]:
    return [
        {
            "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
            "adapter_version": "v0.1",
            "assurance_revision": "v2",
            "activation_source": "ROUTER",
            "binding_ref": "public.v_lf_router_adapter_bindings:x:PERFIL-UI-ARCHITECT",
            "target_ref": "PERFIL-UI-ARCHITECT",
            "ref": "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml",
            "content": "shell: governed",
        }
    ]


class RuntimeEnvelopeMaterializerTests(unittest.TestCase):
    def test_router_advisory_is_materialized_without_upgrading_semantics(self) -> None:
        raw = envelope()
        result = module.materialize_router_advisory_envelope(
            "req-1", raw, live_adapter_sources=adapters()
        )
        gov = result["input_governance"]
        self.assertTrue(gov["current"])
        self.assertTrue(gov["ready"])
        self.assertEqual(gov["status"], "ADVISORY_READ_ONLY")
        self.assertEqual(gov["decision"], "ADVISORY")
        self.assertIsNone(gov["canonical_receipt"])
        self.assertEqual(gov["context"], raw["input_governance"])
        self.assertEqual(gov["context_sha256"], module.canonical_json_sha256(gov["context"]))
        self.assertTrue(gov["constraints"]["read_only"])
        self.assertTrue(gov["constraints"]["no_write"])
        self.assertTrue(gov["constraints"]["no_promotion"])
        profile = result["profile"]
        self.assertEqual(profile["required_adapter_codes"], ["ADAPTER_LF_SHELL_PROFILE"])
        self.assertEqual(profile["lf_adapter_sources"], adapters())
        self.assertEqual(profile["lf_card_sources"], [])
        self.assertFalse(profile["send_image_to_model"])

    def test_blocked_router_decision_cannot_be_materialized(self) -> None:
        raw = envelope()
        raw["input_governance"]["continuation_allowed"] = False
        with self.assertRaisesRegex(RuntimeError, "CONTINUATION_NOT_ALLOWED"):
            module.materialize_router_advisory_envelope(
                "req-1", raw, live_adapter_sources=adapters()
            )

    def test_write_capability_cannot_be_smuggled_into_advisory(self) -> None:
        raw = envelope()
        raw["input_governance"]["constraints"]["no_write"] = False
        with self.assertRaisesRegex(RuntimeError, "CONSTRAINTS_INVALID"):
            module.materialize_router_advisory_envelope(
                "req-1", raw, live_adapter_sources=adapters()
            )

    def test_legacy_artifact_plus_related_shape_fails_closed(self) -> None:
        raw = envelope()
        raw["artifact"] = raw.pop("artifact_set")["artifacts"][0]["artifact"]
        raw["related_artifacts"] = []
        with self.assertRaisesRegex(RuntimeError, "ARTIFACT_SET_REQUIRED"):
            module.materialize_router_advisory_envelope(
                "req-1", raw, live_adapter_sources=adapters()
            )

    def test_missing_live_adapter_binding_fails_closed(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "ADAPTER_MATERIALIZATION_MISSING"):
            module.materialize_router_advisory_envelope(
                "req-1", envelope(), live_adapter_sources=[]
            )

    def test_already_materialized_receipt_is_not_reinterpreted(self) -> None:
        raw = envelope()
        context = raw["input_governance"]
        raw["input_governance"] = {
            "receipt_ref": "router://already/materialized",
            "current": True,
            "ready": True,
            "context": context,
            "context_sha256": module.canonical_json_sha256(context),
            "status": "ADVISORY_READ_ONLY",
            "decision": "ADVISORY",
            "subject_mode": "NON_CANONICAL_ARTIFACT",
            "canonical_receipt": None,
            "required_artifact_binding": context["required_artifact_binding"],
            "constraints": context["constraints"],
        }
        result = module.materialize_router_advisory_envelope(
            "req-1", raw, live_adapter_sources=[]
        )
        self.assertEqual(result, raw)


if __name__ == "__main__":
    unittest.main()
