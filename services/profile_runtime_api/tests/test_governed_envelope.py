from __future__ import annotations

import copy
import hashlib
import unittest

from scripts.hetzner_queue_worker import _validate_envelope


REQUEST_ID = "11111111-1111-4111-8111-111111111111"
CARD_CONTENT = "Selected decision product experience section."
CARD_SHA = hashlib.sha256(CARD_CONTENT.encode("utf-8")).hexdigest()


def governed_envelope() -> dict:
    return {
        "artifact": {
            "screen_code": "B2B-CARGA-001",
            "filename": "candidate.png",
            "image_sha256": "e" * 64,
            "width_px": 1600,
            "height_px": 1000,
            "observations": [{"text": "Historial", "bbox": [10, 10, 100, 20]}],
        },
        "input_governance": {
            "receipt_ref": "programacion.input_readiness_runs/221",
            "current": True,
            "ready": True,
            "context_sha256": "c" * 64,
            "context": {"screen": "B2B-CARGA-001"},
            "status": "READY",
            "canonical_receipt": {
                "run_id": 221,
                "governance_agent_used": "INPUT_GOVERNANCE_AGENT",
                "governance_version": "5.12",
                "consumer": "CONTEXT_PACK",
                "sections_consumed": ["applicability_readiness"],
                "source_refs": ["programacion.input_readiness_runs/221"],
                "source_snapshot_sha256": "b" * 64,
                "contract_snapshot_sha256": "5" * 64,
                "currentness": "LIVE_CURRENT",
                "decision": "PASS",
            },
        },
        "profile": {
            "request_id": REQUEST_ID,
            "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": "PERFIL-UI-ARCHITECT",
            "profile_slug": "ui_architect",
            "profile_source_paths": ["profiles/ui_architect/SKILL.md"],
            "input_literal": "Evaluate the exact artifact.",
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
            "required_card_refs": ["CARD-DECISION-PRODUCT-EXPERIENCE"],
            "lf_card_sources": [
                {
                    "card_ref": "CARD-DECISION-PRODUCT-EXPERIENCE",
                    "card_version": "v1",
                    "source_ref": "cards/marketplace_lf/decision_product_experience/CARD.md",
                    "content_sha256": CARD_SHA,
                    "selected_sections": ["decision_contract"],
                    "budget_chars": len(CARD_CONTENT),
                    "content": CARD_CONTENT,
                }
            ],
            "send_image_to_model": False,
        },
    }


class GovernedEnvelopeTest(unittest.TestCase):
    def test_valid_golden_family_envelope_passes_worker_preflight(self) -> None:
        payload = governed_envelope()
        self.assertIs(_validate_envelope(REQUEST_ID, payload), payload)

    def test_missing_canonical_input_governance_blocks(self) -> None:
        payload = governed_envelope()
        del payload["input_governance"]["canonical_receipt"]
        with self.assertRaisesRegex(RuntimeError, "CANONICAL_RECEIPT_MISSING"):
            _validate_envelope(REQUEST_ID, payload)

    def test_wrong_consumer_blocks(self) -> None:
        payload = governed_envelope()
        payload["input_governance"]["canonical_receipt"]["consumer"] = "STORY_CREATOR"
        with self.assertRaisesRegex(RuntimeError, "CONSUMER_MISMATCH"):
            _validate_envelope(REQUEST_ID, payload)

    def test_required_card_missing_blocks(self) -> None:
        payload = governed_envelope()
        payload["profile"]["lf_card_sources"] = []
        with self.assertRaisesRegex(RuntimeError, "REQUIRED_CARD_MISSING"):
            _validate_envelope(REQUEST_ID, payload)

    def test_tampered_card_hash_blocks(self) -> None:
        payload = governed_envelope()
        payload["profile"]["lf_card_sources"][0]["content_sha256"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError, "CARD_CONTENT_SHA256_MISMATCH"):
            _validate_envelope(REQUEST_ID, payload)

    def test_required_adapter_missing_blocks(self) -> None:
        payload = governed_envelope()
        payload["profile"]["lf_adapter_sources"] = []
        with self.assertRaisesRegex(RuntimeError, "REQUIRED_ADAPTER_MISSING"):
            _validate_envelope(REQUEST_ID, payload)

    def test_adapter_target_mismatch_blocks(self) -> None:
        payload = governed_envelope()
        payload["profile"]["lf_adapter_sources"][0]["target_ref"] = "PERFIL-QUALITY-PACK"
        with self.assertRaisesRegex(RuntimeError, "ADAPTER_TARGET_MISMATCH"):
            _validate_envelope(REQUEST_ID, payload)

    def test_request_id_mismatch_blocks(self) -> None:
        payload = governed_envelope()
        with self.assertRaisesRegex(RuntimeError, "REQUEST_ID_ENVELOPE_MISMATCH"):
            _validate_envelope("22222222-2222-4222-8222-222222222222", payload)

    def test_stale_governance_blocks(self) -> None:
        payload = governed_envelope()
        payload["input_governance"]["canonical_receipt"]["currentness"] = "STALE"
        with self.assertRaisesRegex(RuntimeError, "CANONICAL_NOT_CURRENT_PASS"):
            _validate_envelope(REQUEST_ID, payload)


if __name__ == "__main__":
    unittest.main()
