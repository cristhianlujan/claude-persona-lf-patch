#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"


class ProfileNativeBridgeSourceV1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = list(MIGRATIONS.glob("*_lf_profile_native_execution_bridge_v1.sql"))
        assert len(matches) == 1, matches
        cls.sql = matches[0].read_text(encoding="utf-8")

    def test_bridge_is_service_role_only(self):
        self.assertIn("lf_profile_native_bridge_begin_v1", self.sql)
        self.assertIn("lf_profile_native_bridge_prepare_v1", self.sql)
        self.assertIn("lf_profile_native_bridge_record_output_v1", self.sql)
        self.assertIn("FROM PUBLIC,anon,authenticated,supabase_read_only_user", self.sql)
        self.assertIn("TO service_role", self.sql)
        self.assertIn("PROFILE_NATIVE_BRIDGE_READ_ONLY_EXECUTION_GRANT_FORBIDDEN", self.sql)

    def test_bridge_uses_existing_router_and_operation(self):
        for required in (
            "public.lf_router_route_v1",
            "public.lf_router_semantic_resume_validate_v1",
            "public.lf_router_profile_execution_after_gate2_v1",
            "public.lf_router_profile_execution_handoff_validate_v1",
            "public.lf_profile_execution_input_validate_v1",
            "public.lf_profile_execution_context_admission_v1",
            "public.lf_profile_execution_channel_context_v1",
            "public.lf_profile_execution_research_baseline_v1",
            "public.lf_record_profile_execution_step_v1",
        ):
            self.assertIn(required, self.sql)
        self.assertNotIn("CREATE TABLE", self.sql)

    def test_channel_context_trust_is_explicit(self):
        self.assertIn("PROFILE_NATIVE_BRIDGE_TRUST_V1_SOURCE_DRIFT", self.sql)
        self.assertIn("lf_profile_execution_channel_context_v1", self.sql)

    def test_producer_stops_before_independent_semantic_judge(self):
        self.assertIn("NATIVE_PRODUCER_VALIDATED", self.sql)
        self.assertIn("expected_clean_step_count',9", self.sql)
        self.assertIn("'next_step','semantic_judge'", self.sql)
        self.assertIn("'independent_semantic_judge_required',true", self.sql)
        self.assertIn("'producer_may_self_authorize',false", self.sql)
        self.assertIn("'terminal_authority_ready',false", self.sql)
        self.assertNotIn("PASS_INDEPENDENT_SEMANTIC", self.sql)

    def test_exact_login_rules_canary_is_prepared_by_train(self):
        self.assertIn("Dame las reglas en el login B2B", self.sql)
        self.assertIn("READ_PRODUCT_DEFINITION", self.sql)
        self.assertIn("B2B-AUTH-001", self.sql)
        self.assertIn("PERFIL-PRODUCT-DIRECTOR-LF", self.sql)
        self.assertIn("NOT_REQUIRED_CANONICAL_READ", self.sql)
        self.assertIn("PROFILE_NATIVE_LOGIN_RULES_CANARY_PREPARE_FAILED", self.sql)
        self.assertIn("PROFILE_NATIVE_LOGIN_RULES_CANARY_IG_NOT_SKIPPED", self.sql)
        self.assertIn("PROFILE_NATIVE_LOGIN_RULES_CANARY_STEP_COUNT", self.sql)
        self.assertIn("expected_clean_step_count',7", self.sql)

    def test_canary_source_is_exact_and_content_bound(self):
        self.assertIn(
            "fc88aca0874f3bee7d4dbe29379e975989b26cb2",
            self.sql,
        )
        self.assertIn(
            "sha256:14d57a7709da9dd88ae1e2c5f3c2e48df91093a2afa470e63422e205707fd573",
            self.sql,
        )
        self.assertIn("profiles/product_director_lf/SKILL.md", self.sql)

    def test_no_new_privileged_ci_transport_is_created(self):
        forbidden = (
            "pull_request_target",
            "LF_SUPABASE_DB_PASSWORD",
            "SUPABASE_SERVICE_ROLE_KEY",
            "supabase functions deploy",
        )
        for value in forbidden:
            self.assertNotIn(value, self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
