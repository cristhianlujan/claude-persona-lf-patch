"""Static admission tests for IG M10.0 replacement candidate.

These checks NEVER execute SQL or claim DB proof. The actual five negative
verifier assertions run only when this exact migration is admitted by Train.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "supabase/migrations/20261013021000_lf_ig_m100_sandbox_admission_coherent_v2.sql"
PREMERGED = ROOT / "supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql"


class CandidateContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SOURCE.read_text(encoding="utf-8")

    def test_retirement_boundary_explicit(self):
        self.assertIn("NOT TO BE LABELED ready-to-merge UNTIL", self.sql)
        self.assertIn("dbe466b827f10c257dba6449d65d6750f2328057", self.sql)
        retirement = ROOT / "docs/ig/M100_RETIRED_UNAPPLIED_SOURCE_BOUNDARY_20261012.md"
        self.assertTrue(
            PREMERGED.exists() or retirement.exists(),
            "before retirement the source exists; after retirement the audit record exists",
        )
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


if __name__ == "__main__":
    unittest.main()
