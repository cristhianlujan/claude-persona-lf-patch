"""Static admission tests for IG M10.0 replacement candidate.

These checks NEVER execute SQL or claim DB proof. The actual five negative
verifier assertions run only when this exact migration is admitted by Train.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
SOURCE = next(iter(sorted((ROOT / 'supabase/migrations').glob('*_lf_ig_m100_sandbox_admission_coherent_v2.sql'))), None)
PREMERGED = ROOT / "supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql"


class CandidateContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert SOURCE is not None, 'Train migration source missing'
        cls.sql = SOURCE.read_text(encoding="utf-8")

    def test_prior_unapplied_source_is_separate_nonblocking_debt(self):
        self.assertIn("Its clean-up is NOT a prerequisite", self.sql)
        self.assertNotIn("NOT TO BE LABELED ready-to-merge UNTIL", self.sql)
        self.assertTrue(PREMERGED.exists(), "historical blob must stay in Git as debt")
        self.assertIn("dbe466b827f10c257dba6449d65d6750f2328057", self.sql)
        self.assertIn("m10_0_historical_migration_debt_v1", self.sql)
        self.assertIn("DEBT_RECONCILIATION_SEPARATE", self.sql)
        self.assertIn("not_engineering_checkpoint_dependency',true", self.sql)
        self.assertIn("IG_M100_V2_LEGACY_MIGRATION_NOT_UNAPPLIED", self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION", self.sql)

    def test_unit_work_and_governance_repaired_together(self):
        for required in (
            "UPDATE programacion.engineering_plan_units",
            "UPDATE programacion.engineering_work_items",
            "UPDATE programacion.engineering_work_checkpoints",
            "m10_0_operational_admission_v2",
            "m10_0_contract_governance_v4",
            "m10_0_engineering_admission_v2",
            "m10_0_original_work_contract_v1",
            "m10_0_original_governance_v3",
            "human_approval_required_at_CP5',false",
            "BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY",
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.sql)

    def test_genuine_receipt_guards_and_five_adversarial_cases(self):
        self.assertEqual(
            self.sql.count("EXCEPTION WHEN SQLSTATE 'P0001' THEN"), 5
        )
        self.assertGreaterEqual(
            self.sql.count("programacion.fn_assert_provenance_receipt("), 7
        )
        for required in (
            "v_wrong_head",
            "v_wrong_bundle",
            "v_missing_ready",
            "v_forged_authority",
            "v_wrong_ready_subject",
            "v_components_ok",
            "v_positive",
            "'negative_test_count',5",
        ):
            self.assertIn(required, self.sql)

    def test_no_approval_mutation_or_ledger_shortcut(self):
        for forbidden in (
            "INSERT INTO programacion.human_decisions",
            "UPDATE programacion.human_decisions",
            "INSERT INTO programacion.promotions",
            "UPDATE programacion.promotions",
            "INSERT INTO supabase_migrations.schema_migrations",
            "CREATE OR REPLACE FUNCTION",
            "GRANT EXECUTE",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.sql.upper() if forbidden.isupper() else self.sql)
        self.assertNotIn("APPROVE' INTO", self.sql)
        self.assertIn("production_activation',false", self.sql)

    def test_jsonb_parent_is_created_before_nested_child(self):
        parent = self.sql.index(
            "v_meta:=jsonb_set(v_meta,'{m10_0_original_specs_v1}','{}'::jsonb,true)"
        )
        child = self.sql.index(
            "v_meta:=jsonb_set(v_meta,ARRAY['m10_0_original_specs_v1',v_cp]"
        )
        self.assertLess(parent, child)


    def test_cp7_legacy_missing_spec_is_materialized_from_canonical_source(self):
        self.assertIn("IF v_spec IS NULL AND v_cp='AUTHORITY_READBACK'", self.sql)
        self.assertIn("IG_M100_V2_CP7_CANONICAL_SOURCE_ABSENT", self.sql)
        self.assertIn("coalesce(v_spec,'null'::jsonb)", self.sql)
        self.assertIn("'ENGINEERING_ACTION_SPEC_V3'", self.sql)
        self.assertIn("'source_pack_missing_typed','[]'::jsonb", self.sql)

    def test_existing_pre_human_gates_reused_not_rebuilt(self):
        for capability in (
            "SAFE_CHANGE_ADMISSION",
            "HUMAN_ESCALATION_ADMISSION",
            "TARGETED_EVIDENCE_ACQUISITION",
        ):
            with self.subTest(capability=capability):
                self.assertIn(capability, self.sql)
        self.assertIn("public.lf_capability_current", self.sql)
        self.assertIn("public.lf_capability_version_registry", self.sql)
        self.assertIn("v_route_count IS DISTINCT FROM 3", self.sql)
        self.assertIn("private.lf_human_escalation_policies_v1", self.sql)
        self.assertIn("'IG_LIVE_CANONICAL_CLASSIFIER_REQUIRED'", self.sql)
        self.assertIn("private.fn_lf_ig_human_decision_live_disposition_v1", self.sql)
        self.assertIn("private.fn_lf_human_decision_open_ig_v3", self.sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION", self.sql)

    def test_human_escalation_only_on_admitted_policy_and_exhaustion(self):
        for state in (
            "NO_HUMAN_REQUIRED",
            "AUTO_RESOLVE_FIRST",
            "AUTO_EXECUTION_ELIGIBLE",
            "ACQUIRE_EVIDENCE",
            "EVIDENCE_REQUIRED",
        ):
            with self.subTest(state=state):
                self.assertIn(state, self.sql)
        self.assertIn("'HUMAN_ELIGIBLE'", self.sql)
        self.assertIn("'only_human_eligible_routes_to_queue',true", self.sql)
        self.assertIn("'evidence_exhaustion_requires_proof',true", self.sql)
        self.assertIn("'blocked_and_unknown_not_approval',true", self.sql)
        self.assertIn("'recommended_is_not_permission',true", self.sql)

    def test_no_human_approval_required_to_close_technical_cp5(self):
        self.assertIn("'human_approval_required_for_CP5',false", self.sql)
        self.assertIn("'technical_checkpoint_CP5_human_approval_required',false", self.sql)
        self.assertIn("'cutover_human_receipt_not_replaced_by_safe_change',true", self.sql)
        self.assertIn("'operational_cutover_authority_separate',true", self.sql)
        self.assertIn("'m10_0_original_exit_criterion_v2'", self.sql)
        self.assertIn("v_meta:=jsonb_set(v_meta,'{exit_criterion_v2}'", self.sql)
        self.assertIn("BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY", self.sql)

    def test_checkpoint_assertions_verify_actual_router_contract(self):
        self.assertIn("'prehuman_gate_bound',true", self.sql)
        self.assertIn("'only_eligible_human',true", self.sql)
        self.assertIn("AS prehuman_gate_bound", self.sql)
        self.assertIn("AS only_eligible_human", self.sql)
        self.assertIn("IG_M100_V2_PREHUMAN_CAPABILITY_DRIFT", self.sql)
        self.assertIn("IG_M100_V2_IG_ESCALATION_POLICY_NOT_ACTIVE", self.sql)


if __name__ == "__main__":
    unittest.main()
