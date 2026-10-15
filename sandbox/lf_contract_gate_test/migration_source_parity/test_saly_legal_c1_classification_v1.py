from __future__ import annotations
import pathlib, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import managed, classified
class SalyLegalC1ClassificationTests(unittest.TestCase):
    def test_exact_c1_name(self):
        self.assertTrue(managed("saly_fondeo_legal_c1_lote01_v1"))
        self.assertTrue(classified("saly_fondeo_legal_c1_lote01_v1"))
    def test_other_names_rejected(self):
        self.assertFalse(classified("saly_fondeo_legal_c1_lote01_v2"))
        self.assertFalse(classified("saly_fondeo_legal_c1_lote02_v1"))
        self.assertFalse(classified("saly_unrelated_future_v1"))
if __name__ == "__main__":
    unittest.main()
