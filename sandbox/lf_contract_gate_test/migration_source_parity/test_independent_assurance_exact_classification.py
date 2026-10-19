from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified
from lf_migration_name_classification_check import classify_path


class IndependentAssuranceExactClassificationTests(unittest.TestCase):
    REAL_PATH = (
        "supabase/migrations/"
        "20261003003243_independent_assurance_oracle_independence_measure_v1.sql"
    )
    FAILURE_CODE = "FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY"

    def assert_path_rejected(self, path: str, expected_code: str) -> None:
        with self.assertRaises(ValueError) as raised:
            classify_path(path, self.FAILURE_CODE)
        self.assertTrue(str(raised.exception).startswith(expected_code), str(raised.exception))

    def test_versioned_real_path_is_classified(self):
        name, classification = classify_path(self.REAL_PATH, self.FAILURE_CODE)
        self.assertEqual(name, "independent_assurance_oracle_independence_measure_v1")
        self.assertEqual(classification, "CLASSIFIED_EXTERNAL")

    def test_path_with_uppercase_name_variant_is_rejected(self):
        path = self.REAL_PATH.replace("_independent_", "_Independent_", 1)
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_path_with_leading_space_in_name_is_rejected(self):
        path = self.REAL_PATH.replace("_independent_", "_ independent_", 1)
        self.assert_path_rejected(path, "FAIL_MIGRATION_FILENAME:")

    def test_path_with_trailing_space_in_name_is_rejected(self):
        path = self.REAL_PATH.replace("_measure_v1.sql", "_measure_v1 .sql")
        self.assert_path_rejected(path, "FAIL_MIGRATION_FILENAME:")

    def test_path_with_extra_prefix_before_exact_name_is_rejected(self):
        path = self.REAL_PATH.replace(
            "_independent_assurance", "_x_independent_assurance", 1
        )
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_path_with_extra_suffix_after_exact_name_is_rejected(self):
        path = self.REAL_PATH.replace("_measure_v1.sql", "_measure_v1_extra.sql")
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_exact_name_is_classified(self):
        self.assertTrue(classified("independent_assurance_oracle_independence_measure_v1"))

    def test_v2_suffix_is_not_classified(self):
        self.assertFalse(classified("independent_assurance_oracle_independence_measure_v1_v2"))

    def test_version_prefixed_name_is_not_classified(self):
        self.assertFalse(classified("20261003003243_independent_assurance_oracle_independence_measure_v1"))

    def test_unknown_name_is_not_classified(self):
        self.assertFalse(classified("independent_assurance_oracle_independence_measure_unknown_v1"))


if __name__ == "__main__":
    unittest.main()
