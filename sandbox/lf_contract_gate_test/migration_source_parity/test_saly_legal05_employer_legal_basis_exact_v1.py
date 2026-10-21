from __future__ import annotations
import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified,managed
class SalyEmployerLegalBase(unittest.TestCase):
 def test_exact_name(self):
  self.assertTrue(classified("saly_legal05_c2_base_juridica_patronal_v1"))
  self.assertTrue(managed("saly_legal05_c2_base_juridica_patronal_v1"))
 def test_no_saly_wildcard(self):
  self.assertFalse(classified("saly_legal05_c2_base_juridica_patronal_v2"))
  self.assertFalse(classified("saly_legal05_c2_random_v1"))
if __name__=="__main__": unittest.main()
