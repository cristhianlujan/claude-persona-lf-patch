#!/usr/bin/env python3
"""PR-F: static scope, nine AUTH keys and documentary rule-proposal guards."""
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MIGRATION_SUFFIX = "_lf_global_auth_params_pr_f_v1.sql"

def resolve_unique_migration(root):
    matches = sorted((root / "supabase/migrations").glob("*" + MIGRATION_SUFFIX))
    if len(matches) != 1:
        raise RuntimeError(f"PR_F_MIGRATION_SUFFIX_NOT_UNIQUE:count={len(matches)}")
    return matches[0]

MIGRATION = resolve_unique_migration(ROOT)
HARNESS = ROOT / "sandbox/lf_contract_gate_test/input_governance/pr_f_auth_params_rollback.sql"
PROPOSALS = ROOT / "docs/input-governance/PR_F_AUTH_CANDIDATE_PROPOSALS_ONLY_20261118.json"
VALUES = {
    "MFA_DEVICE_IDLE_DAYS": 30,
    "MFA_PASSWORD_AGE_MONTHS": 3,
    "TEMP_KEY_TTL_HOURS": 24,
    "LOGIN_LOCKOUT_ATTEMPTS_1": 5,
    "LOGIN_LOCKOUT_MINUTES_1": 15,
    "LOGIN_LOCKOUT_ATTEMPTS_2": 3,
    "LOGIN_LOCKOUT_MINUTES_2": 60,
    "LOGIN_LOCKOUT_ATTEMPTS_3": 3,
    "LOGIN_LOCKOUT_MINUTES_3": 1440,
}


class PRFStatic(unittest.TestCase):
    def test_resolve_migration_by_unique_suffix(self):
        self.assertEqual(MIGRATION.name, "20261118073819_lf_global_auth_params_pr_f_v1.sql")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / "supabase/migrations"
            folder.mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, "count=0"):
                resolve_unique_migration(root)
            candidate = folder / "20261118073819_lf_global_auth_params_pr_f_v1.sql"
            candidate.write_text("fixture only")
            self.assertEqual(resolve_unique_migration(root), candidate)
            (folder / "20261118090000_lf_global_auth_params_pr_f_v1.sql").write_text("fixture only")
            with self.assertRaisesRegex(RuntimeError, "count=2"):
                resolve_unique_migration(root)

    def test_only_global_config_insert_no_rule_policy_modification(self):
        src = MIGRATION.read_text()
        self.assertEqual(src.count("INSERT INTO public.lf_global_config"), 1)
        for forbidden in ("UPDATE lf_ops", "INSERT INTO lf_ops", "DELETE FROM lf_ops",
                          "ALTER TABLE", "CREATE TABLE", "DROP TABLE",
                          "politicas_seguridad", "CASCADE", "CREATE POLICY",
                          "GRANT ALL", "COMMIT;"):
            self.assertNotIn(forbidden, src)
        self.assertIn("PR_F_AUTH_PARAMETER_PREEXISTENCE", src)
        self.assertIn("PR_F_AUTH_TOTAL_NOT_NINE", src)
        self.assertIn("PR_F_EXISTING_RLS_DRIFT", src)

    def test_nine_exact_owner_values_and_now(self):
        s = MIGRATION.read_text()
        for key, value in VALUES.items():
            pat = r"\('AUTH','" + re.escape(key) + r"','" + str(value) + r"','INTEGER','REAL',"
            self.assertRegex(s, pat)
        self.assertEqual(s.count("'INTEGER','REAL',"), 9)
        self.assertEqual(s.count(",now()),"), 8)
        self.assertEqual(s.count(",now());"), 1)

    def test_real_postgres_rollback_and_negative_controls(self):
        s = HARNESS.read_text()
        self.assertEqual(s.splitlines().count("BEGIN;"), 1)
        self.assertEqual(s.splitlines().count("ROLLBACK;"), 1)
        self.assertEqual(s.splitlines().count("COMMIT;"), 0)
        for phrase in ("PR_F_UNIQUE_REJECTED_PASS", "PR_F_BAD_STATUS_REJECTED_PASS",
                       "PR_F_BAD_TYPE_REJECTED_PASS", "PR_F_AUTH_FIXTURE_RULES_MUTATED",
                       "PR_F_REAL_POST_ROLLBACK_PASS",
                       "PR_F_IN_TRANSACTION_PASS", "PR_F_ROLE_EXPOSED"):
            self.assertIn(phrase, s)

    def test_four_rules_stay_document_proposals_not_active(self):
        doc = json.loads(PROPOSALS.read_text())
        self.assertEqual(doc["state"], "NOT_STAGED_NOT_APPROVED")
        rules = doc["new_rule_proposals"]
        self.assertEqual(len(rules), 4)
        self.assertEqual(len({r["proposed_code"] for r in rules}), 4)
        self.assertTrue(all(r["estado_propuesto"] == "CANDIDATO" for r in rules))
        self.assertTrue(all(r["valor_config"].get("production_authorized") is False
                            for r in rules))
        lockout = rules[3]["valor_config"]
        self.assertFalse(lockout["enforcement_enabled"])
        self.assertTrue(all(lockout[k] == "PENDING_OWNER_DECISION" for k in
                            ("counter_subject", "measurement_window",
                             "counter_reset_conditions")))


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PRFStatic))
    if result.wasSuccessful():
        print("PR_F_GLOBAL_AUTH_STATIC_PASS 5/5")
    raise SystemExit(0 if result.wasSuccessful() else 1)
