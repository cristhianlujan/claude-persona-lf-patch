"""Fail-closed grep guard: no owner-name/repository/channel literals dispersed in PR #4063.

Only the canonical SQL config seed and a single common test fixture may
contain configured values. This test does not claim live user authentication.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = "supabase/migrations/20261117000100_lf_owner_chat_verified_receipt_guard_v1.sql"
FIXTURE = "sandbox/lf_contract_gate_test/owner_chat_approval/owner_chat_fixture_v1.py"
TARGETS = [
    MIGRATION, FIXTURE,
    "scripts/lf_owner_chat_event_v1.py",
    "scripts/lf_owner_chat_gate_ci_v1.py",
    "docs/operations/LF_OWNER_CHAT_SIGNED_APPROVAL_V1_DRAFT.md",
    ".github/workflows/lf-migration-merge-train.yml",
    ".github/workflows/lf-migration-name-classification.yml",
    "sandbox/lf_contract_gate_test/owner_chat_approval/test_lf_owner_chat_event_v1.py",
    "sandbox/lf_contract_gate_test/owner_chat_approval/test_lf_owner_chat_one_use_rollback_v1.py",
    "sandbox/lf_contract_gate_test/owner_chat_approval/test_lf_owner_chat_pgdual_rollback_v1.py",
    "sandbox/lf_contract_gate_test/owner_chat_approval/test_lf_owner_chat_literal_single_source_v1.py",
]
OWNER_NAME_PATTERN = re.compile(r"Cristhian" + r" Luj[aá]n", re.IGNORECASE)
REPO_PATTERN = re.compile(re.escape("cristhianlujan") + "/" + re.escape("claude-persona-lf-patch"), re.IGNORECASE)
CHANNEL_PATTERN = re.compile("CHAT_ORCHESTRATOR_" + "USER_TURN")


class SingleAuthorityLiteralGuard(unittest.TestCase):
    def test_owner_name_only_in_common_fixture(self):
        for path in TARGETS:
            value=(ROOT / path).read_text(encoding="utf-8")
            expected=1 if path==FIXTURE else 0
            self.assertEqual(len(OWNER_NAME_PATTERN.findall(value)),expected,path)

    def test_repository_only_in_config_seed_and_common_fixture(self):
        for path in TARGETS:
            value=(ROOT / path).read_text(encoding="utf-8")
            expected=1 if path in (MIGRATION,FIXTURE) else 0
            self.assertEqual(len(REPO_PATTERN.findall(value)),expected,path)

    def test_channel_only_in_config_seed_and_common_fixture(self):
        for path in TARGETS:
            value=(ROOT / path).read_text(encoding="utf-8")
            expected=1 if path in (MIGRATION,FIXTURE) else 0
            self.assertEqual(len(CHANNEL_PATTERN.findall(value)),expected,path)

    def test_owner_sub_canonical_join_and_no_name_gate(self):
        sql=(ROOT/MIGRATION).read_text(encoding="utf-8")
        self.assertIn("private.lf_owner_chat_identity_v1",sql)
        self.assertIn("JOIN public.lf_ig_project_owner_v2",sql)
        self.assertIn("owner_sub uuid NOT NULL",sql)
        self.assertIn("authority_role_code",sql)
        self.assertIn("repository_full_name",sql)
        self.assertNotIn("owner_identity",sql)
        self.assertNotIn("p_expected_owner_subject",sql)
        self.assertNotIn("actor_subject",sql)


if __name__=="__main__":
    unittest.main()
