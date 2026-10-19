from __future__ import annotations
import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import managed,classified
class SalyLegalMatrixTest(unittest.TestCase):
    def test_exact_name(self):
        self.assertTrue(managed("saly_fondeo_dictamen_legal_matriz_v1"))
        self.assertTrue(classified("saly_fondeo_dictamen_legal_matriz_v1"))
    def test_other_names_rejected(self):
        self.assertFalse(classified("saly_fondeo_dictamen_legal_matriz_v2"))
        self.assertFalse(classified("saly_fondeo_unrelated_future_v1"))
if __name__=="__main__":
    unittest.main()
