from __future__ import annotations

import unittest

from profile_runtime_api.hashing import sha256_text
from profile_runtime_api.models import CardSource, ProfileTask, RouterAdapterSource
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.runtime_authority import (
    RuntimeAuthorityError,
    resolve_typed_runtime_context,
)


class RuntimeAuthorityTest(unittest.TestCase):
    @staticmethod
    def card(ref: str = "CARD-DEMO-001", required_input_fields: list[str] | None = None) -> CardSource:
        content = "bounded card context"
        return CardSource(
            card_ref=ref,
            card_version="v1",
            source_ref=f"supabase://cards/{ref}",
            content_sha256=sha256_text(content),
            selected_sections=["rules"],
            required_input_fields=required_input_fields or [],
            budget_chars=200,
            content=content,
        )

    @staticmethod
    def adapter() -> RouterAdapterSource:
        return RouterAdapterSource(
            adapter_code="DEMO_ADAPTER",
            adapter_version="v1",
            assurance_revision="assurance-v1",
            activation_source="ROUTER",
            binding_ref="supabase://router/demo-adapter",
            target_ref="PERFIL-QUALITY-PACK",
            ref="adapters/demo/runtime/runtime_capsule.yaml",
            content="adapter capsule",
        )

    @classmethod
    def task(
        cls,
        *,
        cards: list[CardSource] | None = None,
        required_cards: list[str] | None = None,
        input_fields: dict | None = None,
    ) -> ProfileTask:
        return ProfileTask(
            request_id="RUN-S26-B-001",
            profile_code="PERFIL-QUALITY-PACK",
            profile_slug="quality_pack",
            profile_source_paths=["profiles/quality_pack/SKILL.md"],
            input_literal="Evaluate governed evidence.",
            input_fields=input_fields or {},
            lf_card_sources=cards or [],
            required_card_refs=required_cards or [],
            lf_adapter_sources=[cls.adapter()],
            required_adapter_codes=["DEMO_ADAPTER"],
        )

    @staticmethod
    def sources() -> list[dict[str, str]]:
        return [{"ref": "profiles/quality_pack/SKILL.md", "content": "quality authority"}]

    @staticmethod
    def schema(*refs: str, sha256: str = "f" * 64) -> SchemaBinding:
        return SchemaBinding(
            payload={"type": "object"},
            raw=b'{"type":"object"}\n',
            sha256=sha256,
            source_refs=refs or ("profiles/quality_pack/schemas/runtime_output.schema.json",),
            mode="AUTO",
        )

    def resolve(self, task: ProfileTask, context: dict | None = None, schema: SchemaBinding | None = None):
        return resolve_typed_runtime_context(
            task,
            profile_sources=self.sources(),
            context_pack=context or {"schema": "queue/v1"},
            schema=schema or self.schema(),
        )

    @staticmethod
    def expect_code(code: str, fn) -> None:
        with unittest.TestCase().assertRaises(RuntimeAuthorityError) as ctx:
            fn()
        assert ctx.exception.code == code, (ctx.exception.code, code, ctx.exception.detail)

    def test_card_found_is_explicit_and_traceable(self) -> None:
        task = self.task(cards=[self.card()], required_cards=["CARD-DEMO-001"])
        typed = self.resolve(task)
        self.assertEqual(typed["classification"]["surface_code"], "PROFILE:quality_pack")
        self.assertEqual(typed["classification"]["task_code"], "EJECUCION_PERFIL_LF:AUTO")
        self.assertEqual(typed["card_resolution"]["status"], "RESOLVED")
        self.assertEqual(typed["card_resolution"]["selected_card_refs"], ["CARD-DEMO-001"])
        self.assertEqual(typed["authority_resolution"][0]["authority_type"], "PROFILE_SOURCE")
        self.assertEqual(typed["adapter_binding"][0]["adapter_code"], "DEMO_ADAPTER")
        self.assertEqual(
            typed["adapter_binding"][0]["content_sha256"], sha256_text("adapter capsule")
        )
        self.assertEqual(typed["adapter_binding"][0]["activation_source"], "ROUTER")
        self.assertFalse(typed["runtime_schema"]["schema_invention_allowed"])
        self.assertTrue(typed["provenance_reconstructible"])
        self.assertEqual(len(typed["typed_context_sha256"]), 64)
        self.assertEqual(len(typed["input"]["input_fields_sha256"]), 64)

    def test_card_required_input_present_is_bound(self) -> None:
        task = self.task(
            cards=[self.card(required_input_fields=["decision"])],
            required_cards=["CARD-DEMO-001"],
            input_fields={"decision": "CTA primario"},
        )
        typed = self.resolve(task)
        self.assertEqual(typed["input"]["input_fields"], {"decision": "CTA primario"})
        self.assertEqual(
            typed["card_resolution"]["cards"][0]["required_input_fields"],
            ["decision"],
        )

    def test_card_required_input_missing_blocks(self) -> None:
        task = self.task(
            cards=[self.card(required_input_fields=["decision"])],
            required_cards=["CARD-DEMO-001"],
        )
        self.expect_code("RUNTIME_CARD_REQUIRED_INPUT_MISSING", lambda: self.resolve(task))

    def test_no_card_uses_governed_fallback_without_schema_invention(self) -> None:
        typed = self.resolve(self.task())
        card = typed["card_resolution"]
        self.assertEqual(card["status"], "FALLBACK")
        self.assertEqual(card["mode"], "NO_CARD_GOVERNED")
        self.assertEqual(card["selected_card_refs"], [])
        self.assertFalse(card["schema_invention_allowed"])

    def test_multiple_card_candidates_without_selection_block(self) -> None:
        task = self.task(cards=[self.card("CARD-A"), self.card("CARD-B")])
        self.expect_code("RUNTIME_CARD_AMBIGUOUS", lambda: self.resolve(task))

    def test_single_unselected_card_also_blocks_silent_selection(self) -> None:
        task = self.task(cards=[self.card("CARD-A")])
        self.expect_code("RUNTIME_CARD_SELECTION_UNDECLARED", lambda: self.resolve(task))

    def test_missing_profile_authority_blocks(self) -> None:
        task = self.task()
        self.expect_code(
            "RUNTIME_AUTHORITY_MISSING",
            lambda: resolve_typed_runtime_context(
                task, profile_sources=[], context_pack={}, schema=self.schema()
            ),
        )

    def test_required_authority_missing_blocks(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-S26-B-001",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [],
            }
        }
        self.expect_code("RUNTIME_AUTHORITY_MISSING", lambda: self.resolve(self.task(), context))

    def test_incompatible_authorities_block(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-S26-B-001",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-A",
                        "source_ref": "supabase://authority/a",
                        "source_sha256": "1" * 64,
                        "run_id": "RUN-S26-B-001",
                    },
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-B",
                        "source_ref": "supabase://authority/b",
                        "source_sha256": "2" * 64,
                        "run_id": "RUN-S26-B-001",
                    },
                ],
            }
        }
        self.expect_code("RUNTIME_AUTHORITY_INCOMPATIBLE", lambda: self.resolve(self.task(), context))

    def test_invalid_authority_digest_blocks_before_claiming_reconstructible(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-S26-B-001",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-BAD-SHA",
                        "source_ref": "supabase://authority/bad",
                        "source_sha256": "z" * 64,
                        "run_id": "RUN-S26-B-001",
                    }
                ],
            }
        }
        self.expect_code("RUNTIME_AUTHORITY_PROVENANCE_INVALID", lambda: self.resolve(self.task(), context))

    def test_cross_run_reference_requires_explicit_declaration(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-S26-B-001",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-OTHER",
                        "source_ref": "supabase://authority/other",
                        "source_sha256": "3" * 64,
                        "run_id": "RUN-OTHER",
                    }
                ],
            }
        }
        self.expect_code("RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED", lambda: self.resolve(self.task(), context))

    def test_missing_required_adapter_blocks_even_after_model_construction(self) -> None:
        task = self.task().model_copy(update={"required_adapter_codes": ["MISSING_ADAPTER"]})
        self.expect_code("RUNTIME_ADAPTER_MISSING", lambda: self.resolve(task))

    def test_ambiguous_runtime_schema_blocks(self) -> None:
        schema = self.schema("profiles/p/schemas/a.schema.json", "profiles/p/schemas/b.schema.json")
        self.expect_code("RUNTIME_SCHEMA_AMBIGUOUS", lambda: self.resolve(self.task(), schema=schema))

    def test_invalid_runtime_schema_digest_blocks_provenance(self) -> None:
        schema = self.schema(sha256="z" * 64)
        self.expect_code(
            "RUNTIME_PROVENANCE_NOT_RECONSTRUCTIBLE",
            lambda: self.resolve(self.task(), schema=schema),
        )

    def test_input_governance_authority_readback_is_bound(self) -> None:
        context = {
            "input_governance": {
                "receipt_ref": "supabase://input-governance/run-77",
                "context_sha256": "7" * 64,
                "current": True,
                "ready": True,
                "status": "PASS",
            }
        }
        typed = self.resolve(self.task(), context)
        types = [item["authority_type"] for item in typed["authority_resolution"]]
        self.assertEqual(types, ["INPUT_GOVERNANCE", "PROFILE_SOURCE"])

    def test_invalid_input_governance_digest_blocks(self) -> None:
        context = {
            "input_governance": {
                "receipt_ref": "supabase://input-governance/run-bad",
                "context_sha256": "z" * 64,
                "current": True,
                "ready": True,
                "status": "PASS",
            }
        }
        self.expect_code(
            "RUNTIME_INPUT_GOVERNANCE_PROVENANCE_MISSING",
            lambda: self.resolve(self.task(), context),
        )


if __name__ == "__main__":
    unittest.main()
