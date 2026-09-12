from __future__ import annotations

import unittest

from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.runtime_authority import RuntimeAuthorityError, resolve_typed_runtime_context


class RuntimeAuthorityAdversarialTest(unittest.TestCase):
    @staticmethod
    def task() -> ProfileTask:
        return ProfileTask(
            request_id="RUN-S26-B-CURRENT",
            profile_code="PERFIL-QUALITY-PACK",
            profile_slug="quality_pack",
            profile_source_paths=["profiles/quality_pack/SKILL.md"],
            input_literal="Evaluate governed evidence.",
        )

    @staticmethod
    def schema() -> SchemaBinding:
        return SchemaBinding(
            payload={"type": "object"},
            raw=b'{"type":"object"}\n',
            sha256="f" * 64,
            source_refs=("profiles/quality_pack/schemas/runtime_output.schema.json",),
            mode="AUTO",
        )

    @staticmethod
    def sources() -> list[dict[str, str]]:
        return [{"ref": "profiles/quality_pack/SKILL.md", "content": "quality authority"}]

    def test_context_cannot_redefine_current_run_to_hide_cross_run_source(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-ATTACKER-CHOSEN",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-OTHER-RUN",
                        "source_ref": "supabase://authority/other-run",
                        "source_sha256": "3" * 64,
                        "run_id": "RUN-ATTACKER-CHOSEN",
                    }
                ],
            }
        }
        with self.assertRaises(RuntimeAuthorityError) as raised:
            resolve_typed_runtime_context(
                self.task(),
                profile_sources=self.sources(),
                context_pack=context,
                schema=self.schema(),
            )
        self.assertEqual(raised.exception.code, "RUNTIME_AUTHORITY_CURRENT_RUN_MISMATCH")

    def test_explicit_cross_run_source_remains_allowed_when_declared(self) -> None:
        context = {
            "runtime_authority_contract": {
                "current_run_id": "RUN-S26-B-CURRENT",
                "required_authority_types": ["PRODUCT_AUTHORITY"],
                "authority_sources": [
                    {
                        "authority_type": "PRODUCT_AUTHORITY",
                        "authority_id": "AUTH-HISTORICAL",
                        "source_ref": "supabase://authority/historical",
                        "source_sha256": "4" * 64,
                        "run_id": "RUN-HISTORICAL",
                        "cross_run_declared": True,
                    }
                ],
            }
        }
        typed = resolve_typed_runtime_context(
            self.task(),
            profile_sources=self.sources(),
            context_pack=context,
            schema=self.schema(),
        )
        product = next(
            item for item in typed["authority_resolution"] if item["authority_type"] == "PRODUCT_AUTHORITY"
        )
        self.assertEqual(product["run_id"], "RUN-HISTORICAL")
        self.assertTrue(product["cross_run_declared"])
        self.assertEqual(typed["current_run_id"], "RUN-S26-B-CURRENT")


if __name__ == "__main__":
    unittest.main()
