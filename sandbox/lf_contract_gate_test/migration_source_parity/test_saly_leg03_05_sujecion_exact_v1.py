from __future__ import annotations
import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import managed,classified
class TestSalySujecion(unittest.TestCase):
 def test_exact_name(self):
  self.assertTrue(managed("saly_leg03_05_c2_sujecion_actividad_v1"))
  self.assertTrue(classified("saly_leg03_05_c2_sujecion_actividad_v1"))
 def test_no_wildcard(self):
  self.assertFalse(classified("saly_leg03_05_c2_sujecion_actividad_v2"))
  self.assertFalse(classified("saly_leg03_05_c2_unreviewed_scope_v1"))
if __name__=="__main__": unittest.main()
