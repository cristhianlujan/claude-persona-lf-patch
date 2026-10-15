from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified, managed


class SalyFondeoLegalExactClassificationTests(unittest.TestCase):
    def test_saly_fondeo_legal_exact_name_is_managed(self):
        self.assertTrue(managed("saly_fondeo_legal_seguimiento_v1"))
        self.assertTrue(classified("saly_fondeo_legal_seguimiento_v1"))

    def test_other_saly_name_is_not_automatically_managed(self):
        self.assertFalse(managed("saly_fondeo_legal_seguimiento_v2"))
        self.assertFalse(classified("saly_fondeo_legal_seguimiento_v2"))

    def test_lf_unrelated_name_not_classified_by_saly(self):
        self.assertFalse(classified("saly_other_project_unreviewed_v1"))


if __name__ == "__main__":
    unittest.main()
