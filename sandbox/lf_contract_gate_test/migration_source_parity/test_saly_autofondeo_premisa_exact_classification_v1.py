from __future__ import annotations
import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified,managed

class SalyAutofondeoPremiseTests(unittest.TestCase):
    def test_exact_name_admitted(self):
        self.assertTrue(managed("saly_autofondeo_prestamo_planilla_premisa_v1"))
        self.assertTrue(classified("saly_autofondeo_prestamo_planilla_premisa_v1"))
    def test_other_saly_names_rejected(self):
        self.assertFalse(classified("saly_autofondeo_prestamo_planilla_premisa_v2"))
        self.assertFalse(classified("saly_autofondeo_other_scope_v1"))
if __name__ == "__main__":
    unittest.main()
