"""Static qualification for the one-shot governed editorial fact SQL."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261123020500_lf_saly_social_first_editorial_fact_v1.sql"

class TestOneShotNewsFact(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=MIG.read_text(encoding="utf-8")
    def test_native_writer(self):
        self.assertIn("saly.ventas_social_ingesta_execute_v1(",self.s)
        self.assertIn("fn_lf_operation_reserve_execution_v1(",self.s)
        self.assertIn("fn_lf_operation_acquire_lease_v1(",self.s)
        self.assertIn("fn_lf_operation_release_lease_v1(",self.s)
    def test_one_exact_editorial_url(self):
        self.assertIn("PE-NEWS-FACTS-CORREO",self.s)
        self.assertIn("20534471808",self.s)
        self.assertIn("2026-11-01T11:04:35-05:00",self.s)
        self.assertIn("WIPO-PE-DL822-ART9D-FACTS-ONLY",self.s)
    def test_no_fabricated_meta_permission(self):
        self.assertNotIn("'PE-INSTAGRAM','PERSISTENCIA_PERMITIDA'",self.s)
        self.assertNotIn("'PE-FACEBOOK','PERSISTENCIA_PERMITIDA'",self.s)
        self.assertIn("'meta_sources_enabled',false",self.s)
    def test_no_content_reproduction(self):
        for tok in ("Matías Chipana","Alonso Mariñas","Alejandro de la Cruz","Jassiel Zumaeta"):
            self.assertNotIn(tok,self.s)
        self.assertIn("summary_non_personal",self.s)
    def test_window_and_partial_status(self):
        self.assertIn("2026-09-22T00:00:00-05:00",self.s)
        self.assertIn("2026-11-22T23:59:59-05:00",self.s)
        self.assertIn("status='INCOMPLETO'",self.s)
        self.assertNotIn("SET status='COMPLETED'",self.s)
    def test_transaction_and_readback(self):
        self.assertIn("\nBEGIN;\n",self.s)
        self.assertTrue(self.s.rstrip().endswith("COMMIT;"))
        self.assertIn("SALY_EDITORIAL_READBACK_OR_UNRELATED_DATA",self.s)
        self.assertIn("SOCIAL_INGESTION_V1",self.s)
if __name__=="__main__": unittest.main()
