#!/usr/bin/env python3
"""PR-D narrow change + safe migration static guards; real PG test in CI runner."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
ORIGIN = ROOT / "supabase/migrations/20261118061500_lf_payment_provider_config_niubiz_generic_v1.sql"
MIGRATIONS = list((ROOT / "supabase/migrations").glob("*_lf_global_config_consolidation_v1.sql"))
assert len(MIGRATIONS) == 1, f"PR_D_MIGRATION_SOURCE_NOT_UNIQUE:{MIGRATIONS}"
MIGRATION = MIGRATIONS[0]
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_d_global_config_rollback.sql"
DESCRIPTION = "Correo generico enviado a Niubiz cuando el correo del cliente empieza con numero (R-PAY-040/041)"


class GlobalConfigSourceTests(unittest.TestCase):
    def test_01_one_new_table_only_and_non_cascade_drop(self):
        sql = MIGRATION.read_text()
        self.assertEqual(sql.count("CREATE TABLE"), 1)
        self.assertEqual(sql.count("CREATE TABLE public.lf_global_config"), 1)
        self.assertEqual(sql.count("DROP TABLE public.payment_provider_config;"), 1)
        self.assertNotIn("CASCADE", sql)
        self.assertNotIn("CREATE OR REPLACE", sql)
        self.assertNotIn("ALTER TABLE public.payment_provider_config", sql)
        self.assertNotIn("CREATE POLICY", sql)
        self.assertNotIn("GRANT ", sql)
        self.assertNotIn("DELETE FROM", sql)
        self.assertNotIn("TRUNCATE ", sql)

    def test_02_eight_columns_status_type_unique_rls(self):
        sql = MIGRATION.read_text()
        self.assertIn("UNIQUE (scope, config_key, valid_from)", sql)
        self.assertIn("value_type IN ('TEXT', 'INTEGER', 'DECIMAL', 'BOOLEAN', 'JSON', 'EMAIL')", sql)
        self.assertIn("value_status IN ('FICTICIO', 'REAL')", sql)
        self.assertIn("ENABLE ROW LEVEL SECURITY", sql)
        self.assertIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertIn("FROM PUBLIC, anon, authenticated;", sql)
        for column in ("scope text", "config_key text", "config_value text",
                       "value_type text", "value_status text", "description text",
                       "valid_from timestamptz", "created_at timestamptz"):
            self.assertIn(column, sql)

    def test_03_copy_actual_source_fields_and_check_before_removal(self):
        sql = MIGRATION.read_text()
        self.assertIn("FROM public.payment_provider_config", sql)
        self.assertIn("'PAGOS'", sql)
        self.assertIn("'EMAIL'", sql)
        self.assertIn(DESCRIPTION, sql)
        self.assertIn("SELECT\n    'PAGOS',\n    config_key,\n    config_value", sql)
        self.assertIn("valid_from,\n    created_at\nFROM public.payment_provider_config", sql)
        self.assertIn("dst.valid_from = src.valid_from", sql)
        self.assertIn("dst.created_at = src.created_at", sql)
        self.assertLess(sql.index("PR_D_COPY_OR_TIMESTAMP_MISMATCH"),
                        sql.index("DROP TABLE public.payment_provider_config;"))
        self.assertTrue(ORIGIN.is_file())

    def test_04_real_transaction_and_negative_pg_checks(self):
        sql = HARNESS.read_text()
        self.assertEqual(sql.count("@@PRC_SOURCE_SQL@@"), 1)
        self.assertEqual(sql.count("@@PRD_MIGRATION_SQL@@"), 1)
        self.assertEqual(sql.splitlines().count("BEGIN;"), 1)
        self.assertEqual(sql.splitlines().count("ROLLBACK;"), 1)
        self.assertEqual(sql.splitlines().count("COMMIT;"), 0)
        for marker in ("PR_D_BAD_TYPE_DENIED_PASS", "PR_D_BAD_STATUS_DENIED_PASS",
                       "PR_D_DUPLICATE_DENIED_PASS", "PR_D_REAL_POST_ROLLBACK_PASS",
                       "PR_D_CLIENT_ROLE_EXPOSED", "PR_D_IN_TRANSACTION_PASS",
                       "PR_D_OLD_TABLE_NOT_DROPPED"):
            self.assertIn(marker, sql)


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(GlobalConfigSourceTests))
    if result.wasSuccessful():
        print("PR_D_GLOBAL_CONFIG_STATIC_PASS 4/4")
    raise SystemExit(0 if result.wasSuccessful() else 1)
