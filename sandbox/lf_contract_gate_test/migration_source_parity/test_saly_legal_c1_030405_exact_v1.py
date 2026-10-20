from __future__ import annotations
import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import managed,classified
class TestSalyLegalC1(unittest.TestCase):
  def test_exact_name(self):
    self.assertTrue(managed("saly_legal_c1_03_04_05_evidencia_v1"))
    self.assertTrue(classified("saly_legal_c1_03_04_05_evidencia_v1"))
  def test_other_names(self):
    self.assertFalse(classified("saly_legal_c1_03_04_05_evidencia_v2"))
    self.assertFalse(classified("saly_legal_future_unreviewed"))
if __name__=="__main__": unittest.main()
