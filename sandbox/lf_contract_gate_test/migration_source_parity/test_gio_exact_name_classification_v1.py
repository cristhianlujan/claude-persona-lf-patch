"""Candidate-only classifier regression, copied into a disposable LF checkout."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import MANAGED_EXACT_NAMES, MANAGED_PREFIXES, classified, managed

class GioExactNameClassificationTests(unittest.TestCase):
    def test_exact_bootstrap_only(self):
        n = "gio_private_schema_bootstrap_v1"
        self.assertIn(n, MANAGED_EXACT_NAMES)
        self.assertTrue(managed(n))
        self.assertTrue(classified(n))

    def test_no_generic_namespace_prefix(self):
        self.assertNotIn("gio_", MANAGED_PREFIXES)
        for n in ("gio_", "gio_private_schema_bootstrap_v2", "gio_private_schema_bootstrap_v1_extra", "gio_unreviewed_write_v1"):
            with self.subTest(name=n):
                self.assertFalse(managed(n))
                self.assertFalse(classified(n))

if __name__ == "__main__":
    unittest.main()
