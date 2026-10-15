"""PE10E v2 source-only qualification. Does not execute DB writes."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SQL = ROOT / "supabase/migrations/20261012235900_lf_profile_evolution_phase_boundary_v2_train.sql"
CONTRACT = ROOT / "skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json"

class TrainPhaseContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text(encoding="utf-8")
        cls.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    def test_positive_source_classified_and_one_added_migration(self):
        self.assertRegex(SQL.name,r"^\d{14}_lf_[a-z0-9_]+\.sql$")
        self.assertTrue(self.sql.startswith("-- PE10E phase-boundary"))
        self.assertTrue(self.sql.strip().endswith("commit;"))

    def test_positive_contract_and_governance_together(self):
        self.assertIn("'{action_specs_v1,PE10E_C4}'",self.sql)
        self.assertIn("'{phase_separation_v1}'",self.sql)
        self.assertIn("v1.3-phase-separation-candidate",self.sql)
        self.assertIn("LF-PE-PHASE-CONFLATION-20261012-001",self.sql)

    def test_negative_block_missing_native_executor(self):
        self.assertIn("'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'",self.sql)
        self.assertIn("'DECLARED_TEST_EXECUTION'",self.sql)
        self.assertIn("'cutover_eligible',true",self.sql)
        self.assertIn("'independent_assurance','PASS'",self.sql)

    def test_negative_no_unverified_admission(self):
        self.assertNotIn("UPDATE programacion.engineering_work_checkpoints",self.sql)
        self.assertNotIn("UPDATE public.lf_policy_versions",self.sql)
        self.assertNotIn("'ACTIVE',clock_timestamp()",self.sql)
        self.assertNotIn("status='DONE'",self.sql)

    def test_negative_old_source_cannot_be_applied_first(self):
        self.assertIn("version='20261013001500'",self.sql)
        self.assertIn("PE10E_V2_OLD_MIGRATION_ALREADY_APPLIED",self.sql)

    def test_positive_train_safe_source_refs(self):
        self.assertNotIn("20261012235900_lf_profile_evolution_phase_boundary_v2_train.sql",self.sql)
        self.assertNotIn("20261013001500_lf_profile_evolution_phase_boundary_v1.sql",self.sql)
        self.assertIn("skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json",self.sql)

    def test_negative_expert_gate_not_waived(self):
        self.assertTrue(self.contract["separation"]["v02_cutover_requires_expert_benchmark"])
        self.assertFalse(self.contract["separation"]["expert_checkpoint_is_not_applicable"])
        self.assertFalse(self.contract["first_evolution"]["expertise_certified"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
