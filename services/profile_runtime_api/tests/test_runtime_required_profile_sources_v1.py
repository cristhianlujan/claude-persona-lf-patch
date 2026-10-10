from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.repository import RepositoryBindings, RepositoryError


SLUG = "required_source_test"
PROFILE_ROOT = "profiles/" + SLUG
SKILL = PROFILE_ROOT + "/SKILL.md"
MANIFEST = PROFILE_ROOT + "/contracts/analysis_source_binding.json"
EXTRA = PROFILE_ROOT + "/extra.md"


class RequiredProfileSourcesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        root = self.root / PROFILE_ROOT
        (root / "contracts").mkdir(parents=True)
        (root / "schemas").mkdir()
        (root / "validators").mkdir()
        (root / "schemas/runtime_output.schema.json").write_text('{"type":"object"}')
        (root / "validators/gate.py").write_text("def validate(payload): return []\n")
        (root / "validators/semantic.py").write_text("def evaluate(payload, gate): return {}\n")
        (root / "SKILL.md").write_text("# Profile\n\n## Purpose\nResolve material evidence.\n")
        (root / "contracts/analysis_source_binding.json").write_text('{"current":false}\n')
        (root / "extra.md").write_text("# Extra source\n")
        self.binding = {
            "schema": "LF_PROFILE_RUNTIME_BINDING_V1",
            "profile_slug": SLUG,
            "profile_code": "PROFILE-REQUIRED-SOURCE-TEST",
            "runtime_schema": {"default": "schemas/runtime_output.schema.json", "output_modes": {}},
            "canonical_validator": {"path": "validators/gate.py", "callable": "validate"},
            "semantic_utility": {"path": "validators/semantic.py", "callable": "evaluate"},
            "governance": {
                "source_first_required": True, "schema_invention_allowed": False,
                "fail_closed": True, "exact_head_evidence_required": True,
                "post_update_baseline_required": True,
            },
            "model_context": {
                "full_source_to_model": False,
                "required_source_refs": [SKILL, MANIFEST],
                "allow_additional_sources": True,
                "source_projection": {
                    "mode": "MARKDOWN_SECTIONS", "include_sections": ["Purpose"],
                    "max_chars": 12000,
                },
            },
        }
        self.write_binding()
        self.repo = RepositoryBindings(self.root, max_prompt_chars=50000)

    def write_binding(self):
        (self.root / PROFILE_ROOT / "contracts/runtime_binding.json").write_text(
            json.dumps(self.binding), encoding="utf-8"
        )

    def from_paths(self, paths):
        return self.repo.profile_sources(SLUG, paths)

    def test_required_both_pass(self):
        sources = self.from_paths([SKILL, MANIFEST])
        self.assertEqual(len(self.repo.profile_model_sources(SLUG, sources)), 2)

    def test_missing_required_is_rejected(self):
        sources = self.from_paths([SKILL])
        with self.assertRaisesRegex(RepositoryError, "PROFILE_RUNTIME_REQUIRED_SOURCE_MISSING"):
            self.repo.profile_model_sources(SLUG, sources)

    def test_additional_allowed_if_declared(self):
        sources = self.from_paths([SKILL, MANIFEST, EXTRA])
        self.assertEqual(len(self.repo.profile_model_sources(SLUG, sources)), 3)

    def test_additional_forbidden(self):
        self.binding["model_context"]["allow_additional_sources"] = False
        self.write_binding()
        sources = self.from_paths([SKILL, MANIFEST, EXTRA])
        with self.assertRaisesRegex(RepositoryError, "PROFILE_RUNTIME_ADDITIONAL_SOURCE_FORBIDDEN"):
            self.repo.profile_model_sources(SLUG, sources)

    def test_undeclared_allow_extra_fails_closed(self):
        self.binding["model_context"].pop("allow_additional_sources")
        self.write_binding()
        sources = self.from_paths([SKILL, MANIFEST])
        with self.assertRaisesRegex(RepositoryError, "PROFILE_RUNTIME_ADDITIONAL_SOURCE_POLICY_INVALID"):
            self.repo.profile_model_sources(SLUG, sources)

    def test_missing_required_list_fails_closed(self):
        self.binding["model_context"].pop("required_source_refs")
        self.write_binding()
        sources = self.from_paths([SKILL])
        with self.assertRaisesRegex(RepositoryError, "PROFILE_RUNTIME_REQUIRED_SOURCE_CONTRACT_INVALID"):
            self.repo.profile_model_sources(SLUG, sources)

    def test_duplicate_required_fails_closed(self):
        self.binding["model_context"]["required_source_refs"] = [SKILL, SKILL]
        self.write_binding()
        sources = self.from_paths([SKILL])
        with self.assertRaisesRegex(RepositoryError, "PROFILE_RUNTIME_REQUIRED_SOURCE_CONTRACT_INVALID"):
            self.repo.profile_model_sources(SLUG, sources)

    def test_profiles_without_model_context_unchanged(self):
        self.binding.pop("model_context")
        self.write_binding()
        sources = self.from_paths([SKILL])
        self.assertEqual(self.repo.profile_model_sources(SLUG, sources), sources)


if __name__ == "__main__":
    unittest.main()
