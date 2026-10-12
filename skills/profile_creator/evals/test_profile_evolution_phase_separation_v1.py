#!/usr/bin/env python3
"""Static phase-boundary contract regression; NOT an executed GPT-native benchmark."""
import copy
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / "skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json"
SQL_PATH = ROOT / "supabase/migrations/20261013001500_lf_profile_evolution_phase_boundary_v1.sql"


def assert_phase_contract(c):
    assert c["schema"] == "PROFILE_EVOLUTION_PHASE_SEPARATION_V1"
    first, expert, split = c["first_evolution"], c["expert_certification"], c["separation"]
    assert first["status"] == "CODE_MERGED_USER_ACCEPTED"
    assert first["evidence_count"] == 9
    assert all(first[k] is False for k in (
        "independent_execution", "expertise_certified",
        "runtime_activated", "operational_cutover_authorized"))
    assert expert["status"] == "BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING"
    assert len(expert["arms"]) == 4 and expert["checkpoint_status_change_allowed_only_after_real_evidence"]
    assert split["first_evolution_is_expert_admission"] is False
    assert split["expert_checkpoint_is_not_applicable"] is False
    assert split["v02_cutover_requires_expert_benchmark"] is True
    assert split["existing_checkpoints_unchanged"] is True


class TestPhaseSeparation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
        cls.sql = SQL_PATH.read_text(encoding="utf-8")

    def test_positive_two_distinct_stages(self):
        assert_phase_contract(self.contract)

    def test_negative_no_cutover_from_code_merge(self):
        bad = copy.deepcopy(self.contract)
        bad["first_evolution"]["operational_cutover_authorized"] = True
        with self.assertRaises(AssertionError):
            assert_phase_contract(bad)

    def test_negative_no_expert_claim_from_code_merge(self):
        bad = copy.deepcopy(self.contract)
        bad["first_evolution"]["expertise_certified"] = True
        with self.assertRaises(AssertionError):
            assert_phase_contract(bad)

    def test_negative_cannot_waive_expert_checkpoint(self):
        bad = copy.deepcopy(self.contract)
        bad["separation"]["expert_checkpoint_is_not_applicable"] = True
        with self.assertRaises(AssertionError):
            assert_phase_contract(bad)

    def test_positive_exact_nine_git_merge_receipts(self):
        pairs = re.findall(r"jsonb_build_object\('profile','([^']+)','pr',(\d+),'merge_sha','([0-9a-f]{40})'\)", self.sql)
        self.assertEqual(len(pairs), 9)
        self.assertEqual(len({p for p, _, _ in pairs}), 9)
        self.assertEqual(len({n for _, n, _ in pairs}), 9)

    def test_negative_runner_stays_blocked_without_real_evidence(self):
        self.assertIn("'status','BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'", self.sql)
        self.assertIn("'action_kind','DECLARED_TEST_EXECUTION'", self.sql)
        self.assertIn("coalesce((v_boot->>'execution_allowed')::boolean,false)", self.sql)
        self.assertIn("v_boot->>'terminal_action'='CONTINUE_CURRENT_CHECKPOINT'", self.sql)
        self.assertNotIn("UPDATE programacion.engineering_work_checkpoints", self.sql)

    def test_positive_governance_is_candidate_and_ekb_is_append_only(self):
        self.assertIn("'v1.3-phase-separation-candidate'", self.sql)
        self.assertIn("'CANDIDATE',clock_timestamp()", self.sql)
        self.assertNotIn("UPDATE public.lf_policy_versions", self.sql)
        self.assertIn("LF-PE-PHASE-CONFLATION-20261012-001", self.sql)
        self.assertIn("WHERE NOT EXISTS (", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
