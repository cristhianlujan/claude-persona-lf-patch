from __future__ import annotations

import unittest

from pydantic import ValidationError

from profile_runtime_api.engine import _governed_context
from profile_runtime_api.models import CardSource, ProfileTask, RouterAdapterSource


class GovernedContextReceiptTest(unittest.TestCase):
    def card(self) -> CardSource:
        return CardSource(
            card_ref="decision_product_experience",
            card_version="v1",
            source_ref="supabase://lf_cards/decision_product_experience@v1",
            content_sha256="94496ae59f9b288c3c2739c9653edd688aa8efb47e94191dc6efe7785a2bc222",
            selected_sections=["decision_rules", "evidence_requirements"],
            budget_chars=200,
            content="Use bounded product-experience guidance.",
        )

    def adapter(self, *, version: str | None = "2026-08-27") -> RouterAdapterSource:
        return RouterAdapterSource(
            adapter_code="ADAPTER-LF-SHELL-PROFILE-20260827",
            adapter_version=version,
            assurance_revision="assurance-2026-09-04",
            activation_source="ROUTER",
            binding_ref="supabase://v_lf_router_adapter_bindings/ADAPTER-LF-SHELL-PROFILE-20260827",
            target_ref="PERFIL-UI-ARCHITECT",
            ref="repo://adapters/lf-shell-profile.md",
            content="Adapter content",
        )

    def task(self, request_id: str = "req-golden-family-1") -> ProfileTask:
        return ProfileTask(
            request_id=request_id,
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_source_paths=["profiles/ui_architect/SKILL.md"],
            input_literal="Evaluate the governed Golden Family candidate.",
            lf_card_sources=[self.card()],
            required_card_refs=["decision_product_experience"],
            lf_adapter_sources=[self.adapter()],
            required_adapter_codes=["ADAPTER-LF-SHELL-PROFILE-20260827"],
        )

    def test_receipt_binds_cards_adapters_request_and_structural_fingerprint(self) -> None:
        task = self.task()
        prepared_pack = {"schema": "test-pack/v1", "pack_sha256": "b" * 64}

        governed_pack, receipt = _governed_context(task, prepared_pack)

        self.assertEqual(receipt["schema"], "lf-governed-context-receipt/v1")
        self.assertEqual(receipt["request_id"], task.request_id)
        self.assertEqual(receipt["profile_code"], "PERFIL-UI-ARCHITECT")
        self.assertEqual(receipt["card_receipts"][0]["card_ref"], "decision_product_experience")
        self.assertEqual(receipt["card_receipts"][0]["card_version"], "v1")
        self.assertEqual(receipt["card_receipts"][0]["request_id"], task.request_id)
        self.assertEqual(receipt["card_receipts"][0]["selected_sections"], ["decision_rules", "evidence_requirements"])
        self.assertEqual(receipt["card_receipts"][0]["budget_chars"], 200)
        self.assertEqual(receipt["adapter_receipts"][0]["adapter_code"], "ADAPTER-LF-SHELL-PROFILE-20260827")
        self.assertEqual(receipt["adapter_receipts"][0]["adapter_version"], "2026-08-27")
        self.assertEqual(receipt["adapter_receipts"][0]["target_ref"], "PERFIL-UI-ARCHITECT")
        self.assertEqual(receipt["adapter_receipts"][0]["request_id"], task.request_id)
        self.assertEqual(len(receipt["context_fingerprint"]), 64)
        self.assertEqual(governed_pack["lf_card_receipts"], receipt["card_receipts"])
        self.assertEqual(governed_pack["lf_adapter_receipts"], receipt["adapter_receipts"])

    def test_context_fingerprint_changes_with_request_identity(self) -> None:
        prepared_pack = {"schema": "test-pack/v1", "pack_sha256": "b" * 64}
        _, first = _governed_context(self.task("req-golden-family-1"), prepared_pack)
        _, second = _governed_context(self.task("req-golden-family-2"), prepared_pack)

        self.assertNotEqual(first["context_fingerprint"], second["context_fingerprint"])

    def test_required_adapter_rejects_missing_version(self) -> None:
        with self.assertRaisesRegex(ValidationError, "LF_ADAPTER_REQUIRED_VERSION_MISSING"):
            ProfileTask(
                request_id="req-missing-adapter-version",
                profile_code="PERFIL-UI-ARCHITECT",
                profile_slug="ui_architect",
                profile_source_paths=["profiles/ui_architect/SKILL.md"],
                input_literal="Evaluate governed context.",
                lf_adapter_sources=[self.adapter(version=None)],
                required_adapter_codes=["ADAPTER-LF-SHELL-PROFILE-20260827"],
            )

    def test_card_rejects_content_hash_mismatch(self) -> None:
        with self.assertRaisesRegex(ValidationError, "LF_CARD_CONTENT_SHA256_MISMATCH"):
            CardSource(
                card_ref="decision_product_experience",
                card_version="v1",
                source_ref="supabase://lf_cards/decision_product_experience@v1",
                content_sha256="0" * 64,
                selected_sections=["decision_rules"],
                budget_chars=200,
                content="Use bounded product-experience guidance.",
            )


if __name__ == "__main__":
    unittest.main()
