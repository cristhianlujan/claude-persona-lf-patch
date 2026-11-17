"""Fail-closed grep guard: no owner-name/repository/channel literals dispersed in PR #4063.

Only the canonical SQL config seed and a single common test fixture may
contain configured values. This test does not claim live user authentication.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import unittest
from owner_chat_fixture_v1 import CLAUDE_HASH

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
CLAUDE_CHANNEL_PATTERN = re.compile("CHAT_CLAUDE_" + "SESSION")
GPT_CHANNEL_PATTERN = re.compile("CHAT_GPT_" + "SESSION")
CLAUDE_EMAIL_SHA_PATTERN = re.compile("e9ff5f5f431ad1a7" + "fdea5aeda30fcbad4bd48d2f0d73231e9383682098c4e258")



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

    def test_account_hash_and_session_channels_only_in_seed_and_fixture(self):
        for path in TARGETS:
            value=(ROOT / path).read_text(encoding="utf-8")
            sha_expected=1 if path in (MIGRATION,FIXTURE) else 0
            claude_expected=2 if path==MIGRATION else (1 if path==FIXTURE else 0)
            gpt_expected=2 if path==MIGRATION else (1 if path==FIXTURE else 0)
            self.assertEqual(len(CLAUDE_EMAIL_SHA_PATTERN.findall(value)),sha_expected,path)
            self.assertEqual(len(CLAUDE_CHANNEL_PATTERN.findall(value)),claude_expected,path)
            self.assertEqual(len(GPT_CHANNEL_PATTERN.findall(value)),gpt_expected,path)

    def test_session_table_references_canonical_owner_and_seeds_both_channels(self):
        sql=(ROOT/MIGRATION).read_text(encoding="utf-8")
        self.assertIn("REFERENCES private.lf_owner_chat_identity_v1(owner_sub)",sql)
        self.assertIn("account_email_sha256",sql)
        self.assertIn("identity_mode text NOT NULL CHECK (identity_mode='ACCOUNT_SESSION')",sql)
        self.assertIn("CHAT_OWNER_ACCOUNT_SESSION_NOT_AUTHORIZED",sql)
        self.assertNotIn("p_identity_mode text",sql)
        self.assertIn("CROSS JOIN (VALUES('CHAT_" + "CLAUDE_SESSION'),('CHAT_" + "GPT_SESSION'))",sql)
        self.assertIn("p_session_account_email text",sql)
        self.assertIn("convert_to(lower(btrim(p_session_account_email))",sql)

    def test_no_owner_cleartext_email_in_any_tracked_repository_file(self):
        # Compare hashes, never embed or print the owner's plaintext email.
        assert len(CLAUDE_HASH)==64
        # Native git scan covers ALL tracked blobs, including binary bytes;
        # it is faster than opening files one by one in Python.
        # Fixed-string prefilter for the authorized account's domain is fast
        # even for binary blobs; compute hash on complete mailbox tokens only.
        result=subprocess.run(
            ['git','grep','--cached','-a','-n','--no-color','-i','-F',
             '@gmail.com'],
            cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
        self.assertIn(result.returncode,(0,1),'GIT_EMAIL_SCAN_FAILED')
        tokens=re.compile(rb'[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}')
        for hit in result.stdout.splitlines():
            path,line,content=hit.split(b':',2)
            for email in tokens.findall(content):
                fingerprint=hashlib.sha256(email.strip().lower()).hexdigest()
                self.assertNotEqual(fingerprint,CLAUDE_HASH,
                    path.decode('utf-8','replace')+':'+line.decode('ascii','replace'))

    def test_single_shared_hash_seed_and_external_installation_variable(self):
        sql=(ROOT/MIGRATION).read_text(encoding='utf-8')
        self.assertEqual(sql.count(CLAUDE_HASH),1)
        self.assertIn("OWNER_ACCOUNT_EMAIL",sql)
        py=(ROOT/'scripts/lf_owner_chat_gate_ci_v1.py').read_text(encoding='utf-8')
        self.assertIn("os.environ.get('OWNER_ACCOUNT_EMAIL')",py)
        register_signature=sql.split("CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_register_v1(",1)[1].split(") RETURNS jsonb",1)[0]
        self.assertIn("p_session_account_email text",register_signature)
        self.assertNotIn("p_session_account_sha256",register_signature)

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
