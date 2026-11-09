"""Read-only static contract checks for the governed skill-invoker migration.

Structural verification only. SQL execution/rollback and two-session concurrency
require a real isolated PostgreSQL harness and must NOT be marked PASS from these.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261109101500_lf_skill_invoker_idempotent_replay_v1.sql"


class SkillInvokerIdempotencySourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")

    def test_01_existing_function_and_authority_remain(self):
        self.assertEqual(self.sql.count("CREATE OR REPLACE FUNCTION public.lf_skill_invoke_v1"), 1)
        self.assertIn("SECURITY DEFINER", self.sql)
        self.assertIn("SKILL_NOT_AUTHORIZED_FOR_PROFILE", self.sql)
        self.assertIn("PARENT_EXECUTION_NOT_ACTIVE", self.sql)
        self.assertIn("SKILL_INPUT_INVALID", self.sql)

    def test_02_same_parent_skill_input_serialized_before_handler(self):
        sql = self.sql
        self.assertEqual(sql.count("pg_advisory_xact_lock"), 1)
        self.assertLess(sql.index("pg_advisory_xact_lock"), sql.index("execute format('select public.%I($1)'"))
        for field in ("parent_execution_id=p_execution_id", "skill_code=p_skill", "input_sha256=v_in"):
            self.assertIn(field, sql)

    def test_03_exact_replay_refs_are_not_new_child(self):
        sql = self.sql
        self.assertIn("'replay',true", sql)
        self.assertIn("'skill_run_id',v_prior.skill_run_id", sql)
        self.assertIn("'child_execution_id',v_prior.child_execution_id", sql)
        self.assertIn("'evidence_ref',v_prior.evidence_ref", sql)
        self.assertIn("'SKILL_REPLAY_CHILD_BINDING_MISMATCH'", sql)

    def test_04_legacy_duplicates_preserved_fail_closed(self):
        sql = self.sql
        self.assertIn("'SKILL_REPLAY_AMBIGUOUS_HISTORY'", sql)
        self.assertIn("'RECONCILE_HISTORICAL_DUPLICATES_WITHOUT_DELETE'", sql)
        self.assertNotRegex(sql, r"(?im)^\s*(DELETE|TRUNCATE)\s+")
        self.assertIn("created_at >= timestamptz '2026-11-09 08:00:00+00'", sql)
        self.assertIn("lf_skill_invocation_v1_new_parent_skill_input_uniq", sql)

    def test_05_child_opened_does_not_mean_applied(self):
        sql = self.sql
        self.assertIn("'effect_verified',false", sql)
        self.assertIn("'VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE'", sql)
        self.assertIn("'SKILL_CHILD_EXECUTION_BLOCKED'", sql)

    def test_06_no_router_ig_acl_override(self):
        sql = self.sql
        self.assertNotRegex(sql, r"(?im)^\s*(GRANT|REVOKE|DROP|TRUNCATE)\b")
        self.assertNotIn("service_role_key", sql)
        self.assertNotIn("lf_router_pipeline_context", sql)
        self.assertNotIn("fn_input_governance", sql)

    def test_07_source_guard_and_readback(self):
        self.assertIn("'BLOCK_SKILL_INVOKER_SOURCE_DRIFT'", self.sql)
        self.assertIn("'BLOCK_SKILL_INVOKER_NEW_ROWS_UNASSESSED'", self.sql)
        self.assertIn("'BLOCK_SKILL_INVOKER_IDEMPOTENCE_READBACK'", self.sql)


if __name__ == "__main__":
    unittest.main()
