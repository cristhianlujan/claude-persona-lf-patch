from __future__ import annotations

import base64
import unittest

from pydantic import ValidationError

from profile_runtime_api.hashing import canonical_json_sha256, sha256_bytes
from profile_runtime_api.models import Artifact, InputGovernanceReceipt, ProfileTask


class ModelGovernanceTest(unittest.TestCase):
    def test_known_profile_slug_is_bound_to_canonical_profile_code(self) -> None:
        with self.assertRaises(ValidationError):
            ProfileTask(
                request_id="bad-binding",
                profile_code="PERFIL-UI-ARCHITECT",
                profile_slug="quality_pack",
                profile_source_paths=["profiles/quality_pack/SKILL.md"],
                input_literal="Evaluate current evidence.",
            )

    def test_governance_requires_current_ready_and_exact_context_hash(self) -> None:
        context = {"screen": "B2B-CARGA-001", "scope": ["read"]}
        valid = {
            "receipt_ref": "receipt://current/1",
            "current": True,
            "ready": True,
            "context_sha256": canonical_json_sha256(context),
            "context": context,
            "status": "READY",
        }
        self.assertEqual(InputGovernanceReceipt.model_validate(valid).context, context)
        for change in (
            {"current": False},
            {"ready": False},
            {"context_sha256": "0" * 64},
        ):
            with self.assertRaises(ValidationError):
                InputGovernanceReceipt.model_validate(valid | change)

    def test_canonical_governance_receipt_is_source_bound(self) -> None:
        context = {"screen": "B2B-CARGA-001", "scope": ["read"]}
        payload = {
            "receipt_ref": "programacion.input_readiness_runs/221",
            "current": True,
            "ready": True,
            "context_sha256": canonical_json_sha256(context),
            "context": context,
            "status": "READY",
            "canonical_receipt": {
                "run_id": 221,
                "governance_agent_used": "INPUT_GOVERNANCE_AGENT",
                "governance_version": "5.12",
                "consumer": "CONTEXT_PACK",
                "sections_consumed": ["applicability_readiness", "source_authority_provenance"],
                "source_refs": ["programacion.input_readiness_runs/221"],
                "source_snapshot_sha256": "b" * 64,
                "contract_snapshot_sha256": "5" * 64,
                "currentness": "LIVE_CURRENT",
                "decision": "PASS",
                "agent_output_sha256": "a" * 64,
            },
        }
        receipt = InputGovernanceReceipt.model_validate(payload)
        self.assertEqual(receipt.canonical_receipt.consumer, "CONTEXT_PACK")
        with self.assertRaises(ValidationError):
            InputGovernanceReceipt.model_validate(
                payload
                | {
                    "canonical_receipt": payload["canonical_receipt"]
                    | {"consumer": "STORY_CREATOR"}
                }
            )

    def test_required_card_and_adapter_sources_fail_closed(self) -> None:
        card_content = "# Decision product experience\nOnly selected governed sections."
        base = {
            "request_id": "req-1",
            "profile_code": "PERFIL-UI-ARCHITECT",
            "profile_slug": "ui_architect",
            "profile_source_paths": ["profiles/ui_architect/SKILL.md"],
            "input_literal": "Evaluate current evidence.",
            "required_card_refs": ["CARD-DECISION-PRODUCT-EXPERIENCE"],
            "lf_card_sources": [
                {
                    "card_ref": "CARD-DECISION-PRODUCT-EXPERIENCE",
                    "card_version": "v1",
                    "source_ref": "cards/marketplace_lf/decision_product_experience/CARD.md",
                    "content_sha256": sha256_bytes(card_content.encode("utf-8")),
                    "selected_sections": ["decision_contract"],
                    "budget_chars": len(card_content),
                    "content": card_content,
                }
            ],
            "required_adapter_codes": ["ADAPTER_LF_SHELL_PROFILE"],
            "lf_adapter_sources": [
                {
                    "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
                    "adapter_version": "v0.1",
                    "assurance_revision": "v0.1",
                    "activation_source": "ROUTER",
                    "binding_ref": "public.v_lf_router_adapter_bindings:binding-1",
                    "target_ref": "PERFIL-UI-ARCHITECT",
                    "ref": "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml",
                    "content": "shell_locked: true",
                }
            ],
        }
        self.assertEqual(ProfileTask.model_validate(base).required_card_refs[0], "CARD-DECISION-PRODUCT-EXPERIENCE")
        with self.assertRaises(ValidationError):
            ProfileTask.model_validate(base | {"lf_card_sources": []})
        with self.assertRaises(ValidationError):
            ProfileTask.model_validate(
                base
                | {
                    "lf_card_sources": [
                        base["lf_card_sources"][0] | {"content_sha256": "0" * 64}
                    ]
                }
            )
        with self.assertRaises(ValidationError):
            ProfileTask.model_validate(
                base
                | {
                    "lf_adapter_sources": [
                        base["lf_adapter_sources"][0] | {"adapter_version": None}
                    ]
                }
            )

    def test_attached_image_bytes_are_bound_to_declared_sha(self) -> None:
        raw = b"not-a-real-png-but-model-binding-does-not-decode-it"
        payload = {
            "screen_code": "B2B-CARGA-001",
            "filename": "candidate.png",
            "image_sha256": sha256_bytes(raw),
            "width_px": 1600,
            "height_px": 1000,
            "image_base64": base64.b64encode(raw).decode("ascii"),
            "image_media_type": "image/png",
        }
        self.assertEqual(Artifact.model_validate(payload).image_bytes(), raw)
        with self.assertRaises(ValidationError):
            Artifact.model_validate(payload | {"image_sha256": "f" * 64})


if __name__ == "__main__":
    unittest.main()
