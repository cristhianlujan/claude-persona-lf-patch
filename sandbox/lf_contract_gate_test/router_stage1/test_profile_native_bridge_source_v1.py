#!/usr/bin/env python3
from pathlib import Path
import hashlib
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

    def test_channel_context_event_uses_operational_envelope(self):
        self.assertIn("'evidence_schema_version','operational-event/v2'", self.sql)
        self.assertIn("'acceptance_declared',false", self.sql)
        self.assertIn("'occurred_at',clock_timestamp()", self.sql)
        self.assertIn(
            "'purpose','Hydrate bounded channel-specific Product context for governed profile execution.'",
            self.sql,
        )

    def test_channel_budget_event_uses_identity_default(self):
        self.assertNotIn("lf_context_budget_events_v2_id_seq", self.sql)
        self.assertIn("RETURNING id INTO v_budget_event_id", self.sql)

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
        self.assertIn("LF_PRODUCT_CANONICAL_RULE_READ_V1", self.sql)
        self.assertIn("COMPACT_DIRECT_RULES_EFFECTIVE_AGGREGATE_LAZY", self.sql)
        self.assertIn("'direct_rule_count'", self.sql)
        self.assertIn("'effective_rule_count'", self.sql)
        self.assertIn("PROFILE_NATIVE_LOGIN_RULES_CANARY_CONTEXT_BUDGET_FAILED", self.sql)

    def test_canary_source_is_exact_and_content_bound(self):
        self.assertIn(
            "fc88aca0874f3bee7d4dbe29379e975989b26cb2",
            self.sql,
        )
        self.assertIn(
            "sha256:1ddca16b29e65e6748f61fdc31e02081ca3990c67b079be705dde3a6a3c58209",
            self.sql,
        )
        self.assertIn("profiles/product_director_lf/SKILL.md", self.sql)
        source = ROOT / "profiles" / "product_director_lf" / "SKILL.md"
        self.assertEqual(
            hashlib.sha256(source.read_bytes()).hexdigest(),
            "1ddca16b29e65e6748f61fdc31e02081ca3990c67b079be705dde3a6a3c58209",
        )

    def test_no_new_privileged_ci_transport_is_created(self):
        forbidden = (
            "pull_request_target",
            "LF_SUPABASE_DB_PASSWORD",
            "SUPABASE_SERVICE_ROLE_KEY",
            "supabase functions deploy",
        )
        for value in forbidden:
            self.assertNotIn(value, self.sql)


class ProfileNativeBridgeChannelNeutralCleanupV1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = list(
            MIGRATIONS.glob("*_lf_profile_native_bridge_channel_neutral_cleanup_v1.sql")
        )
        assert len(matches) == 1, matches
        cls.cleanup = matches[0].read_text(encoding="utf-8")
        cls.bridge = cls.cleanup.split(
            "CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1", 1
        )[1].split(
            "REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_begin_v1", 1
        )[0]
        cls.generic_gate2 = cls.cleanup.split(
            "CREATE OR REPLACE FUNCTION public.lf_router_profile_gate2_result_from_selection_v1", 1
        )[1].split(
            "REVOKE ALL ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1", 1
        )[0]
        cls.legacy_gate2 = cls.cleanup.split(
            "CREATE OR REPLACE FUNCTION public.lf_router_product_gate2_result_from_selection_v1", 1
        )[1].split(
            "REVOKE ALL ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1", 1
        )[0]

    def test_native_bridge_is_channel_neutral(self):
        self.assertIn(
            "v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')",
            self.bridge,
        )
        self.assertIn("public.lf_router_profile_after_selection_v1", self.bridge)
        self.assertIn(
            "public.lf_router_profile_gate2_result_from_selection_v1",
            self.bridge,
        )
        self.assertNotIn(
            "public.lf_router_product_profile_after_selection_v1",
            self.bridge,
        )
        self.assertNotIn(
            "public.lf_router_product_gate2_result_from_selection_v1",
            self.bridge,
        )
        self.assertNotIn("'PRODUCTO_PROFILE_SELECTION_REQUIRED'", self.bridge)
        self.assertNotIn("'PRODUCTO_GATE2_PERFIL'", self.bridge)

    def test_stage1_is_single_channel_business_scope_source(self):
        self.assertIn("p_stage1->>'negocio_codigo'", self.bridge)
        self.assertIn("p_stage1->'alcance'", self.bridge)
        self.assertIn("v_expected_route_step:=v_channel||'_PROFILE_SELECTION_REQUIRED'", self.bridge)
        self.assertIn("v_expected_gate2_step:=v_channel||'_GATE2_PERFIL'", self.bridge)
        self.assertNotIn("v_after_selection->>'canal_candidato'", self.bridge)
        self.assertNotIn("v_after_selection->>'negocio_codigo'", self.bridge)
        self.assertNotIn("v_after_selection->'alcance'", self.bridge)

    def test_generic_gate2_owns_logic_and_product_name_is_wrapper_only(self):
        self.assertIn("public.lf_router_semantic_resume_validate_v1", self.generic_gate2)
        self.assertIn(
            "DETERMINISTIC_FROM_VALIDATED_PROFILE_SELECTION",
            self.generic_gate2,
        )
        self.assertIn(
            "public.lf_router_profile_gate2_result_from_selection_v1",
            self.legacy_gate2,
        )
        self.assertNotIn(
            "public.lf_router_semantic_resume_validate_v1",
            self.legacy_gate2,
        )

    def test_legacy_product_continuations_delegate_to_common_implementation(self):
        self.assertIn(
            "RETURN public.lf_router_profile_after_selection_v1",
            self.cleanup,
        )
        self.assertIn(
            "RETURN public.lf_router_profile_after_selection_raw_v1",
            self.cleanup,
        )
        self.assertIn("NATIVE_BRIDGE_LEGACY_WRAPPER_CLEANUP_FAIL", self.cleanup)

    def test_srcr_programacion_native_postcheck_is_rollback_only(self):
        self.assertIn(
            "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            self.cleanup,
        )
        self.assertIn(
            '"canal_candidato":"PROGRAMACION"',
            self.cleanup.replace(" ", ""),
        )
        self.assertIn("NATIVE_EXECUTION_READY", self.cleanup)
        self.assertIn("NATIVE_BRIDGE_CHANNEL_NEUTRAL_ROLLBACK_SENTINEL", self.cleanup)
        self.assertIn("NATIVE_BRIDGE_CHANNEL_NEUTRAL_POSTCHECK_RESIDUE", self.cleanup)

    def test_execution_acl_stays_service_role_only(self):
        self.assertIn(
            "FROM PUBLIC,anon,authenticated,supabase_read_only_user",
            self.cleanup,
        )
        self.assertIn(
            "TO service_role",
            self.cleanup,
        )
        self.assertIn("NATIVE_BRIDGE_EXECUTION_ACL_REGRESSION", self.cleanup)


if __name__ == "__main__":
    unittest.main(verbosity=2)
