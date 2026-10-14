from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified


class IndependentAssuranceExactClassificationTests(unittest.TestCase):
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
