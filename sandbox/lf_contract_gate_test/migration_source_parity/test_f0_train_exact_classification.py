import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified, managed


class F0TrainExactClassificationTests(unittest.TestCase):
    def test_f0_train_credential_canary_is_managed_and_classified(self):
        name = "f0_train_credential_canary_noop_v1"
        self.assertTrue(managed(name))
        self.assertTrue(classified(name))

    def test_unknown_f0_name_remains_unclassified(self):
        name = "f0_unrecognized_future_name_v1"
        self.assertFalse(managed(name))
        self.assertFalse(classified(name))


if __name__ == "__main__":
    unittest.main()
