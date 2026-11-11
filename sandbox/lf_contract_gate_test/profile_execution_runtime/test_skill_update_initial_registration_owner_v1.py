"""Source contract checks; PG17 runtime tests are additionally required in CI."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261109213000_lf_skill_update_initial_registration_owner_v1.sql"
EDGE=ROOT/"supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts"
TEST=ROOT/"supabase/functions/lf-profiles-governance-caller-v1/profile_continuation_test.ts"

class SkillInitialOwnerContract(unittest.TestCase):
    def test_initial_owner_requires_actual_governed_migration(self):
        s=MIGRATION.read_text()
        for needle in ["GOVERNED_INITIAL_ASSET_REGISTRATION",
                       "ACTUALIZACION_DB_LF","lf-migration-merge-train",
                       "v_asset.created_by_execution_id","e.status='COMPLETED'",
                       "registered_by_execution_id","EXISTING_GITHUB_SKILL_CANDIDATE",
                       "a.ruta_esperada=v_asset.ruta_esperada",
                       "SKILL_UPDATE_CHILD_INITIAL_REGISTRATION_NOT_VERIFIED"]:
            self.assertIn(needle,s)
    def test_preserves_previous_14_step_gate_and_no_promotion(self):
        s=MIGRATION.read_text()
        for needle in ["v_required_count<>14","HISTORICAL_COMPLETED_SKILL_UPDATE",
                       "SKILL_UPDATE_CHILD_CANONICAL_OWNER_NOT_VERIFIED",
                       "'github_write_executed',false",
                       "'runtime_write_executed',false",
                       "'production_authorized',false",
                       "'automatic_runtime_promotion',false"]:
            self.assertIn(needle,s)
    def test_existing_step_recorder_uses_bound_skill_root(self):
        s=MIGRATION.read_text()
        self.assertIn("CREATE OR REPLACE FUNCTION public.lf_skill_update_child_step_v1",s)
        self.assertNotIn("target_type='SKILL' AND target_code='ACT-0045'",s)
        self.assertNotIn("v_child.target_path NOT LIKE 'skills/profile_creator/%'",s)
        for token in ["v_child.manifest#>>'{owner_provenance,canonical_root_path}'",
                      "SKILL_UPDATE_STEP_PARENT_CHILD_BINDING_INVALID",
                      "SKILL_UPDATE_STEP_SERVER_CONTEXT_OR_DRIFT_INVALID",
                      "p_evidence->>'skill_identity' IS DISTINCT FROM v_child.target_code",
                      "lf_record_operation_step_core_v1"]:
            self.assertIn(token,s)
    def test_edge_requires_typed_readme_and_delegates_final_authority(self):
        s=EDGE.read_text()
        self.assertIn('declaration_kind: "REGISTERED_CANDIDATE"',s)
        self.assertIn('SKILL_UPDATE_OWNER_DECLARATION_MISMATCH',s)
        self.assertIn("SKILL_UPDATE_TARGET_PATH_RE.test(targetPath)",s)
        self.assertIn('const registeredCandidate = ownerMatch ? null',s)
        self.assertIn("registeredCandidate:false",TEST.read_text())
        self.assertIn("first registered candidate has typed owner provenance",TEST.read_text())

if __name__ == "__main__": unittest.main()
