"""PE10E phase-1 acceptance scope regression; source-only, no DB mutation."""
from pathlib import Path
import json
import re
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261012235901_lf_profile_phase1_acceptance_separate_expert_v1.sql"
CONTRACT=ROOT/"skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json"

class PhaseOneScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql=MIGRATION.read_text(encoding="utf-8")
        cls.c=json.loads(CONTRACT.read_text(encoding="utf-8"))

    def test_positive_nine_merge_receipts_distinct(self):
        pairs=re.findall(r"jsonb_build_object\('profile','([^']+)','pr',(\d+),'merge_sha','([a-f0-9]{40})'\)",self.sql)
        self.assertEqual(len(pairs),9)
        self.assertEqual(len(set(v[0] for v in pairs)),9)
        self.assertEqual(len(set(v[1] for v in pairs)),9)

    def test_positive_genuine_first_evolution_acceptance(self):
        self.assertIn("PROFILE_EVOLUTION_FIRST_RELEASE_ACCEPTANCE_V1",self.sql)
        self.assertIn("PE10E_C3B",self.sql)
        self.assertIn("'DONE'",self.sql)
        self.assertIn("fn_engineering_checkpoint_transition_v1",self.sql)
        self.assertIn("CODE_ONLY_ACCEPTED",self.sql)

    def test_negative_expert_checkpoint_unmodified_and_pending(self):
        self.assertIn("checkpoint_code='PE10E_C4'",self.sql)
        self.assertIn("status='PENDING' AND sequence_no=5",self.sql)
        self.assertIn("BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING",self.sql)
        self.assertNotIn(",'PE10E_C4','DONE'",self.sql)

    def test_negative_no_cutover_or_production(self):
        self.assertIn("cutover_gate_preserved",self.sql)
        self.assertIn("'runtime_activated',false",self.sql)
        self.assertNotIn("UPDATE public.lf_policy_versions",self.sql)
        self.assertNotIn("UPDATE public.lf_operation_registry",self.sql)
        self.assertNotIn("ALTER TABLE",self.sql)

    def test_negative_independent_assurance_stays_open(self):
        self.assertIn("PE10_C3",self.sql)
        self.assertIn("status='IN_PROGRESS'",self.sql)
        self.assertIn("'independent_assurance','NOT_EXECUTED'",self.sql)
        self.assertTrue(self.c["separation"]["v02_cutover_requires_expert_benchmark"])
        self.assertFalse(self.c["first_evolution"]["expertise_certified"])

    def test_positive_metadata_and_ekb(self):
        self.assertIn("first_evolution_acceptance_v2",self.sql)
        self.assertIn("LF-PE-FIRST-RELEASE-ACCEPTANCE-20261012-001",self.sql)
        self.assertIn("ON_FAIL",self.sql) if "ON_FAIL" in self.sql else self.assertIn("RAISE EXCEPTION",self.sql)
        self.assertRegex(MIGRATION.name,r"^\d{14}_lf_[a-z0-9_]+\.sql$")

    def test_no_frozen_migration_filename_reference(self):
        self.assertNotIn("20261012235901",self.sql)
        self.assertNotIn("20261013001500",self.sql)
        self.assertTrue(self.sql.rstrip().endswith("COMMIT;"))

    def test_no_direct_status_write(self):
        self.assertNotIn("SET status='DONE'",self.sql)
        self.assertNotIn("SET status = 'DONE'",self.sql)
        self.assertIn("fn_engineering_checkpoint_transition_v1",self.sql)

if __name__=="__main__":
    unittest.main(verbosity=2)
