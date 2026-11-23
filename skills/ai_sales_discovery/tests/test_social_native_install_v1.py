"""Checks the exact unchanged candidate SQL plus dormant native writer install wrapper."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261123011000_lf_saly_social_writer_native_install_v1.sql"
WRITER=ROOT/"skills/ai_sales_discovery/adapters/social_native_writer_candidate_v1.sql"

class SocialNativeInstallContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mig=MIG.read_text()
        cls.writer=WRITER.read_text()

    def test_one_exact_writer(self):
        self.assertIn(self.writer, self.mig)
        self.assertEqual(self.mig.count("CREATE FUNCTION saly.ventas_social_ingesta_execute_v1"),1)

    def test_invoker_only(self):
        self.assertIn("SECURITY INVOKER",self.mig)
        self.assertNotIn("SECURITY DEFINER",self.mig)

    def test_native_operation_not_second_router(self):
        self.assertIn("INGESTA_EMPRESARIAL_SALY",self.mig)
        self.assertIn("fn_lf_operation_reserve_effect_v1",self.mig)
        self.assertIn("fn_lf_operation_mark_effect_succeeded_v1",self.mig)

    def test_stays_disabled(self):
        self.assertNotIn("INSERT INTO public.lf_operation_contracts",self.mig)
        self.assertNotIn("INSERT INTO saly.ventas_discovery_catalogo",self.mig)
        self.assertNotIn("UPDATE public.lf_operation_contracts",self.mig)
        self.assertNotIn("GRANT EXECUTE",self.mig)
        self.assertIn("REVOKE ALL ON FUNCTION",self.mig)

    def test_prestate_and_poststate(self):
        self.assertIn("SOCIAL_NATIVE_INSTALL_PRESTATE",self.mig)
        self.assertIn("SOCIAL_NATIVE_INSTALL_POSTSTATE",self.mig)
        self.assertIn("has_function_privilege('service_role'",self.mig)
        self.assertIn("contract_code='SALY_SOCIAL_INGESTION_V1'",self.mig)

    def test_one_migration_transaction(self):
        self.assertTrue(self.mig.startswith("-- SALY U07"))
        self.assertIn("\nBEGIN;\n",self.mig)
        self.assertTrue(self.mig.rstrip().endswith("COMMIT;"))

if __name__=="__main__":
    unittest.main()
