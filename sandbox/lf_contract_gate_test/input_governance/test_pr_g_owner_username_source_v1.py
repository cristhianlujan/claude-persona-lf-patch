#!/usr/bin/env python3
"""PR-G stable-suffix static regression; Train may legitimately retimestamp the migration."""
import json
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[3]
GLOB="*_lf_ig_owner_username_only_pr_g_v1.sql"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_g_owner_username_only_rollback.sql"
RUNNER=ROOT/"sandbox/lf_contract_gate_test/input_governance/run_pr_g_owner_username_pg17_v1.py"
SRC=ROOT/"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"

class TestPRG(unittest.TestCase):
    def migration(self):
        paths=list((ROOT/"supabase/migrations").glob(GLOB))
        self.assertEqual(len(paths),1,"exactly one PR-G migration even after Train timestamp change")
        return paths[0].read_text()

    def test_exact_before_after_migration_gate(self):
        s=self.migration()
        for key in [
          "2d6f2592e8f7e002ab29f212bcca0663",
          "e9bd839b8978a3f7872dd82a104ce99c",
          "f2e2c80a1d8e7d85ac15b7238df02a2b",
          "e1c17dcff3b03c5a9623e77aa1674cae",
          "PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_12",
          "PR_G_OWNER_WRITER_POSTIMAGE_MD5_DRIFT",
          "PR_G_OWNER_EXECUTE_ACL_DRIFT"
        ]: self.assertIn(key,s)
        self.assertIn("USERNAME_ONLY_UNVERIFIED",s)
        self.assertIn("'usuario','veredicto'",s)
        self.assertIn("clock_timestamp()",s)
        self.assertIn("v_decision_record::text",s)

    def test_no_other_gates_or_rules_modified(self):
        s=self.migration().lower()
        for forbidden in (
         "update lf_ops.reglas", "insert into lf_ops.reglas",
         "alter table public.lf_ig_project_owner_v2",
         "alter table public.lf_ig_rule_change_v2",
         "create or replace function public.lf_ig_rule_finalize_v2",
         "create or replace function public.lf_ig_rule_child_guard_v2",
         "create or replace function public.lf_ig_rule_cycle_once_v3",
         "lf_global_config", "owner_sub set",
         "revoke execute", "grant execute", "commit;"
        ): self.assertNotIn(forbidden,s)

    def test_real_rollback_negative_foreign_user(self):
        s=HARNESS.read_text()
        self.assertEqual(s.splitlines().count("BEGIN;"),1)
        self.assertEqual(s.splitlines().count("ROLLBACK;"),1)
        self.assertEqual(s.splitlines().count("COMMIT;"),0)
        for key in ("OTRO_USUARIO","LF_IG_OWNER_DECISION_INPUT_INVALID",
                    "PR_G_IN_TRANSACTION_PASS","PR_G_REAL_POST_ROLLBACK_PASS",
                    "B2B-RULE-AUTH-018","B2B-RULE-AUTH-019",
                    "B2B-RULE-AUTH-020"):
            self.assertIn(key,s)
        self.assertIn("PR_G_EXACT_HEAD",RUNNER.read_text())
        self.assertIn("CREATE FUNCTION public.lf_ig_rule_owner_decide_v2(",SRC.read_text())

    def test_writers_unchanged_by_file_names(self):
        # No file outside 1 migration, 2 tests, 1 runner, 1 docs and workflow
        # is allowed by the change manifest. Enforcement in CI uses git diff.
        self.assertNotIn("PR_G_MIGRATION_TRANSACTION_FORBIDDEN",self.migration())

if __name__=="__main__":
    tests=unittest.defaultTestLoader.loadTestsFromTestCase(TestPRG)
    result=unittest.TextTestRunner(verbosity=2).run(tests)
    if result.wasSuccessful(): print("PR_G_OWNER_USERNAME_STATIC_PASS 4/4")
    raise SystemExit(0 if result.wasSuccessful() else 1)
