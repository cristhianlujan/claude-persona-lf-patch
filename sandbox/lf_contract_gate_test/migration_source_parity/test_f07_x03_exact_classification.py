import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified, managed, fail

class F07X03ExactClassificationTests(unittest.TestCase):
    def test_x03_post_cutover_classified(self):
        name = "pase_f07_x03_runtime_implementation_deploy_v1"
        filename = "20261009230101_" + name + ".sql"
        self.assertTrue(filename.startswith("20261009230101_"))
        self.assertTrue(classified(name))
        self.assertTrue(managed(name))

    def test_b2b_s06_exact_source_managed_without_family_widening(self):
        self.assertTrue(managed("b2b_corporate_scope_model_v1"))
        self.assertTrue(classified("b2b_corporate_scope_model_v1"))
        for name in (
            "b2b_corporate_scope_model_v2",
            "b2b_other_group_model_v1",
            "b2b_unreviewed_future_migration",
        ):
            with self.subTest(name=name):
                self.assertFalse(managed(name))
                self.assertFalse(classified(name))

    def test_arbitrary_pase_remains_fail_closed(self):
        name = "pase_cualquier_otra_cosa_v1"
        filename = "20261009230102_" + name + ".sql"
        self.assertFalse(classified(name))
        self.assertFalse(managed(name))
        with self.assertRaises(SystemExit) as caught:
            if not classified(name):
                fail("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION", "git=" + filename)
        self.assertEqual(str(caught.exception),
            "FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION: git=" + filename)

if __name__ == "__main__":
    unittest.main()
