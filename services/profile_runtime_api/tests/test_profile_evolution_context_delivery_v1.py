"""Verify candidate guidance reaches model sources only when explicitly selected."""
from __future__ import annotations

import unittest
from pathlib import Path

from profile_runtime_api.repository import RepositoryBindings, RepositoryError

ROOT = Path(__file__).resolve().parents[3]
PROFILES = ("programming_analysis_lf", "systemic_root_cause_repair_lf")
HEADING = "Profile Evolution first candidate — domain specialization (DRAFT)"


class EvolutionContextDeliveryTests(unittest.TestCase):
    def test_explicit_source_changes_projected_method_without_affecting_default(self):
        repo = RepositoryBindings(ROOT, max_prompt_chars=100000)
        for slug in PROFILES:
            with self.subTest(profile=slug):
                binding = repo.runtime_binding(slug)
                self.assertIsNotNone(binding)
                required = binding.model_context["required_source_refs"]
                candidate = f"profiles/{slug}/contracts/profile_evolution_first_candidate_v1.md"
                base = repo.profile_model_sources(slug, repo.profile_sources(slug, required))
                evolved = repo.profile_model_sources(slug, repo.profile_sources(slug, required + [candidate]))
                base_skill = next(s["content"] for s in base if s["ref"].endswith("/SKILL.md"))
                evolved_skill = next(s["content"] for s in evolved if s["ref"].endswith("/SKILL.md"))
                self.assertNotIn(HEADING, base_skill)
                self.assertIn(HEADING, evolved_skill)
                self.assertNotEqual(base_skill, evolved_skill)
                self.assertTrue(any(s["ref"] == candidate for s in evolved))

    def test_missing_candidate_source_is_not_silently_substituted(self):
        repo = RepositoryBindings(ROOT, max_prompt_chars=100000)
        for slug in PROFILES:
            with self.subTest(profile=slug):
                binding = repo.runtime_binding(slug)
                required = binding.model_context["required_source_refs"]
                candidate = f"profiles/{slug}/contracts/profile_evolution_first_candidate_v1.md"
                with self.assertRaisesRegex(RepositoryError, "PROFILE_SOURCE_MISSING"):
                    repo.profile_sources(slug, required + [candidate + ".missing"])


if __name__ == "__main__":
    unittest.main()
