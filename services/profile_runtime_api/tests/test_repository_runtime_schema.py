from __future__ import annotations

import unittest
from pathlib import Path

from profile_runtime_api.repository import RepositoryBindings, RepositoryError


class RepositoryRuntimeSchemaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(__file__).resolve().parents[3]
        self.bindings = RepositoryBindings(self.repo, max_prompt_chars=100_000)

    def test_product_director_auto_ambiguity_fails_before_schema_synthesis(self) -> None:
        with self.assertRaises(RepositoryError) as raised:
            self.bindings.runtime_schema("product_director_lf", "AUTO")
        self.assertEqual(raised.exception.code, "PROFILE_RUNTIME_SCHEMA_AMBIGUOUS")

    def test_ui_architect_auto_ambiguity_fails_before_schema_synthesis(self) -> None:
        with self.assertRaises(RepositoryError) as raised:
            self.bindings.runtime_schema("ui_architect", "AUTO")
        self.assertEqual(raised.exception.code, "PROFILE_RUNTIME_SCHEMA_AMBIGUOUS")

    def test_quality_explicit_runtime_schema_remains_byte_bound(self) -> None:
        schema = self.bindings.runtime_schema("quality_pack", "AUTO")
        self.assertEqual(len(schema.source_refs), 1)
        self.assertEqual(
            schema.source_refs[0],
            "profiles/quality_pack/schemas/runtime_output.schema.json",
        )
        self.assertEqual(len(schema.sha256), 64)
        self.assertEqual(schema.raw, (self.repo / schema.source_refs[0]).read_bytes())


if __name__ == "__main__":
    unittest.main()
