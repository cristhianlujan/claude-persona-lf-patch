"""Static contract guards for a candidate IG migration; NOT SQL runtime execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]
MIGRATION = ROOT / "supabase/migrations/20261107194500_lf_ig_semantic_family_remediation_detail_v1.sql"
CONTRACT = ROOT / "docs/input-governance/IG_SEMANTIC_FAMILY_REMEDIATION_DETAIL_CONTRACT_V1.md"


class SemanticFamilyRemediationContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.doc = CONTRACT.read_text(encoding="utf-8")

    def test_existing_scope_authority_not_replaced(self):
        self.assertIn("fn_input_validator_semantic_scope_v1(p_run_id)", self.sql)
        self.assertIn("fn_input_governance_validator_handoff_assert_v1", self.sql)
        self.assertIn("source_observed_sha256", self.sql)
        self.assertIn("ig_semantic_source_snapshot_v1", self.sql)

    def test_no_family_allowlist_or_silent_drop(self):
        self.assertNotIn("f NOT IN ('RATE_LIMIT','SESSION')", self.sql)
        self.assertNotIn("IG_SEMANTIC_PACKET_UNSUPPORTED_FAMILY_PILOT", self.sql)
        self.assertIn("FAMILY_SOURCE_RESOLVER_NOT_MATERIALIZED", self.sql)
        self.assertIn("TARGETED_SOURCE_RESEARCH_AND_NATIVE_CURATOR_REBIND", self.sql)

    def test_repair_not_a_false_positive_or_n_a(self):
        self.assertIn("THEN 'REMEDIATION_REQUIRED'", self.sql)
        self.assertIn("'semantic_verdict','NOT_TESTED'", self.sql)
        self.assertIn("'semantic_pass_authorized',false", self.sql)
        self.assertIn("'semantic_quality_evaluated',false", self.sql)
        self.assertIn("'promotion_authorized',false", self.sql)
        self.assertNotIn("'semantic_pass_authorized',true", self.sql)

    def test_source_integrity_includes_unresolved(self):
        self.assertIn("jsonb_array_length(v_missing_pins)=0", self.sql)
        self.assertIn("AND jsonb_array_length(v_unresolved_families)=0", self.sql)
        self.assertIn("SOURCE_SNAPSHOT_PIN_REQUIRED", self.sql)
        self.assertIn("SOURCE_VOLUME_REQUIRES_PAGINATED_READBACK", self.sql)

    def test_full_families_keep_per_obligation_detail(self):
        for marker in (
            "'family_evidence',v_family_evidence",
            "'detail_manifest',v_detail_manifest",
            "'negative_requirements',a.negative_requirements",
            "'test_obligations',a.test_obligations",
            "'subject_coverage',a.subject_coverage",
            "'threat_coverage',a.threat_coverage",
            "'curator_evidence',a.curator_evidence",
            "'validator_findings',a.validator_findings",
            "'source_refs',a.source_refs",
            "REFERENCE_PLUS_JIT",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)

    def test_profile_requires_actual_readback_not_merely_summary(self):
        for marker in (
            "detail_readback_required_before_profile_opinion",
            "Un hash por sí solo",
            "detail_read_status",
            "no produce",
            "Input Governance",
        ):
            with self.subTest(marker=marker):
                self.assertTrue(marker in self.sql or marker in self.doc)

    def test_restricted_native_wrapper_stays_separate(self):
        self.assertNotIn(
            "CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_packet_v1",
            self.sql,
        )
        self.assertIn(
            "REVOKE ALL ON FUNCTION programacion.fn_input_governance_semantic_packet_core_v1",
            self.sql,
        )
        for role in ("PUBLIC", "anon", "authenticated", "service_role"):
            self.assertIn(role, self.sql)
        self.assertIn("IG_SEMANTIC_PACKET_FAMILY_SOURCE_DRIFT", self.sql)

    def test_draft_does_not_change_router_or_record_fake_judge(self):
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_router", self.sql)
        self.assertNotIn("UPDATE programacion.input_readiness_runs", self.sql)
        self.assertNotIn("INSERT INTO programacion.input_gap_proposals", self.sql)
        self.assertIn("semantic_judge_executed',false", self.sql)
        self.assertIn("semantic_independence_credited',false", self.sql)


if __name__ == "__main__":
    unittest.main()
