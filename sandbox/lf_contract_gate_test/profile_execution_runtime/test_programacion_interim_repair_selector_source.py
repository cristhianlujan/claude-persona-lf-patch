"""Source-only guards for interim PROGRAMACION -> Reparador selector migration.

These tests are NOT a PostgreSQL execution proof. The migration itself contains
transactional positive/negative readback and must run only through LF Merge Train.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261109140000_lf_programacion_interim_repair_selection_v1.sql"


class InterimProgrammingRepairSelectionSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")

    def test_only_existing_selector_function_patched(self):
        sql = self.sql
        self.assertIn("public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)", sql)
        self.assertIn("v_patched:=replace(v_function,v_old,v_new)", sql)
        self.assertIn("EXECUTE v_patched;", sql)
        for forbidden in ("CREATE TABLE", "ALTER TABLE", "GRANT ", "REVOKE ", "UPDATE public.",
                          "INSERT INTO", "DELETE FROM", "public.lf_router_route_v1("):
            self.assertNotIn(forbidden, sql.upper() if forbidden.isupper() else sql)

    def test_interim_owner_requires_preexisting_authority(self):
        sql = self.sql
        self.assertIn("v_channel='PROGRAMACION' AND v_deriv IS NULL", sql)
        self.assertIn("PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF", sql)
        self.assertIn("a.operation_code='EJECUCION_PERFIL_LF'", sql)
        self.assertIn("a.status='ACTIVE'", sql)
        self.assertIn("p->>'entry_policy'='DERIVATION_ONLY'", sql)

    def test_valid_returns_and_other_channels_preserved(self):
        sql = self.sql
        self.assertIn("v_deriv IS NOT NULL", sql)
        self.assertIn("LF_PROGRAMACION_OTHER_CHANNEL_REGRESSION", sql)
        self.assertIn("LF_PROGRAMACION_FORGED_DERIVATION_NOT_CLOSED", sql)
        self.assertIn("LF_PROGRAMACION_POSTCHANGE_OWNER_OR_AUTHORITY_INVALID", sql)

    def test_exact_source_and_readback_guards(self):
        sql = self.sql
        self.assertIn("de64438021ab995e27cf0494862f5f23", sql)
        self.assertIn("LF_PROGRAMACION_SELECTOR_SOURCE_DRIFT", sql)
        self.assertIn("LF_PROGRAMACION_SELECTOR_EXACT_ANCHOR_REQUIRED", sql)
        self.assertIn("LF_PROGRAMACION_FUNCTION_READBACK_MISMATCH", sql)


if __name__ == "__main__":
    unittest.main()
