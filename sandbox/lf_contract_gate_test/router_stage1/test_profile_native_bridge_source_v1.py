#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"
WORKFLOW = ROOT / ".github" / "workflows" / "lf-profile-native-execution-bridge.yml"


class ProfileNativeBridgeSourceV1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = list(MIGRATIONS.glob("*_lf_profile_native_execution_bridge_v1.sql"))
        assert len(matches) == 1, matches
        cls.sql = matches[0].read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

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

    def test_input_governance_is_not_forced_for_canonical_read(self):
        self.assertIn("input_validate", self.sql)
        self.assertIn("router_reentry_required", self.sql)
        self.assertIn("NATIVE_MODEL_INPUT_READY", self.sql)
        self.assertIn("expected_clean_step_count',7", self.sql)

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

    def test_pull_request_target_never_checks_out_head(self):
        self.assertIn("pull_request_target:", self.workflow)
        self.assertIn("ref: refs/heads/main", self.workflow)
        self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", self.workflow)
        self.assertIn("github.event.pull_request.user.login == github.repository_owner", self.workflow)
        self.assertNotIn("ref: ${{ github.event.pull_request.head.sha }}", self.workflow)
        self.assertNotIn("actions/checkout@v4\n        with:\n          ref: ${{", self.workflow)

    def test_untrusted_pr_is_data_only_and_path_bounded(self):
        self.assertIn("sandbox\\/lf_profile_native_requests", self.workflow)
        self.assertIn("PROFILE_NATIVE_BRIDGE_UNTRUSTED_PATH", self.workflow)
        self.assertIn("Fetch untrusted payload as data only", self.workflow)
        self.assertIn("gh api", self.workflow)
        self.assertIn("PROFILE_NATIVE_BRIDGE_LITERAL_NOT_ALLOWED_V1", self.workflow)
        self.assertIn("Dame las reglas en el login B2B", self.workflow)

    def test_workflow_uses_existing_db_secret_and_real_validator(self):
        self.assertIn("LF_SUPABASE_DB_PASSWORD", self.workflow)
        self.assertIn("environment: lf-merge-train", self.workflow)
        self.assertIn(
            "profiles/product_director_lf/validators/validate_product_director_output.py",
            self.workflow,
        )
        self.assertIn("PASS_PROFILE_NATIVE_BRIDGE_PRODUCT_VALIDATOR", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
