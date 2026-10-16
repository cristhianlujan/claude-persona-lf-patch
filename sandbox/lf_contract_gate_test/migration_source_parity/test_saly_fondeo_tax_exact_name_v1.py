from __future__ import annotations
import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified, managed
class SalyFondeoTaxClassificationTests(unittest.TestCase):
    def test_exact_name_admitted(self):
        self.assertTrue(managed("saly_fondeo_escenarios_tributarios_v1"))
        self.assertTrue(classified("saly_fondeo_escenarios_tributarios_v1"))
    def test_unapproved_names_denied(self):
        self.assertFalse(classified("saly_fondeo_escenarios_tributarios_v2"))
        self.assertFalse(classified("saly_fondeo_unreviewed_name_v1"))
        self.assertFalse(classified("saly_impuestos_future_scope_v1"))
if __name__ == "__main__":
    unittest.main()
