#!/usr/bin/env python3
"""PR-C zero-secret source guard. PostgreSQL integration lives in the SQL harness."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = list((ROOT / "supabase/migrations").glob("*_lf_payment_provider_config_niubiz_generic_v1.sql"))
assert len(MIGRATIONS) == 1, f"PR_C_MIGRATION_SOURCE_NOT_UNIQUE:{MIGRATIONS}"
MIGRATION = MIGRATIONS[0]
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_c_payment_provider_config_rollback.sql"
EMAIL = "niubiz-generico@lf-ficticio.invalid"


class PaymentProviderConfigSourceTest(unittest.TestCase):
    def test_01_exactly_one_table_and_one_insert(self):
        sql = MIGRATION.read_text()
        self.assertEqual(len(re.findall(r"\bCREATE TABLE\b", sql, re.I)), 1)
        self.assertEqual(len(re.findall(r"\bINSERT INTO\b", sql, re.I)), 1)
        self.assertIn("CREATE TABLE public.payment_provider_config", sql)
        self.assertIn("INSERT INTO public.payment_provider_config", sql)
        for bad in ("CREATE OR REPLACE FUNCTION", "ALTER TABLE lf_ops.",
                    "UPDATE lf_ops.", "INSERT INTO lf_ops.",
                    "DROP TABLE", "CASCADE", "service_role", "MERGE INTO"):
            self.assertNotIn(bad, sql.upper() if bad == "CASCADE" else sql)

    def test_02_restrict_exposed_roles_and_status(self):
        sql = MIGRATION.read_text()
        self.assertIn("CHECK (value_status IN ('FICTICIO', 'REAL'))", sql)
        self.assertIn("UNIQUE (provider, config_key, valid_from)", sql)
        self.assertIn("ENABLE ROW LEVEL SECURITY", sql)
        self.assertIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertIn("FROM PUBLIC, anon, authenticated;", sql)
        self.assertNotIn("CREATE POLICY", sql)
        self.assertNotIn("GRANT ", sql)
        self.assertNotIn("current_setting('app.environment')", sql)

    def test_03_exact_reserved_address_and_fake_status(self):
        sql = MIGRATION.read_text()
        self.assertIn(EMAIL, sql)
        self.assertIn("'NIUBIZ', 'NIUBIZ_EMAIL_GENERICO'", sql)
        self.assertIn("'FICTICIO'", sql)
        self.assertEqual(sql.count(EMAIL), 1)
        self.assertIn(".invalid", EMAIL)

    def test_04_real_rollback_harness_is_transactional(self):
        sql = HARNESS.read_text()
        self.assertEqual(sql.splitlines().count("BEGIN;"), 1)
        self.assertEqual(sql.splitlines().count("ROLLBACK;"), 1)
        self.assertEqual(sql.splitlines().count("COMMIT;"), 0)
        self.assertEqual(sql.count("@@MIGRATION_SQL@@"), 1)
        for claim in (
            "PR_C_IN_TRANSACTION_PASS",
            "PR_C_DUPLICATE_REJECTED_PASS",
            "PR_C_STATUS_ENUM_REJECTED_PASS",
            "PR_C_REAL_POST_ROLLBACK_PASS",
            "PR_C_ROLE_EXPOSED",
            "PR_C_RLS_NOT_FORCED",
            "PR_C_EXACTLY_ONE_FAKE_ROW_FAILED",
        ):
            self.assertIn(claim, sql)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PaymentProviderConfigSourceTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():
        print("PR_C_NIUBIZ_STATIC_PASS 4/4")
    raise SystemExit(0 if result.wasSuccessful() else 1)
