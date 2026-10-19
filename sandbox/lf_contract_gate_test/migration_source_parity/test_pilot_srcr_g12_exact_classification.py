from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified
from lf_migration_name_classification_check import classify_path


class PilotSrcrG12ExactClassificationTests(unittest.TestCase):
    EXACT_NAME = "20261003003000_lf_pilot_srcr_g12_state_authority_v1"
    REAL_PATH = (
        "supabase/migrations/"
        "20261012064408_20261003003000_lf_pilot_srcr_g12_state_authority_v1.sql"
    )
    FAILURE_CODE = "FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY"

    def assert_path_rejected(self, path: str, expected_code: str) -> None:
        with self.assertRaises(ValueError) as raised:
            classify_path(path, self.FAILURE_CODE)
        self.assertTrue(str(raised.exception).startswith(expected_code), str(raised.exception))

    def test_versioned_real_path_is_classified(self):
        name, classification = classify_path(self.REAL_PATH, self.FAILURE_CODE)
        self.assertEqual(name, self.EXACT_NAME)
        self.assertEqual(classification, "CLASSIFIED_EXTERNAL")

    def test_path_with_uppercase_name_variant_is_rejected(self):
        path = self.REAL_PATH.replace("_lf_", "_LF_", 1)
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_path_with_leading_space_in_name_is_rejected(self):
        path = self.REAL_PATH.replace("20261012064408_", "20261012064408_ ", 1)
        self.assert_path_rejected(path, "FAIL_MIGRATION_FILENAME:")

    def test_path_with_trailing_space_in_name_is_rejected(self):
        path = self.REAL_PATH.replace("_authority_v1.sql", "_authority_v1 .sql")
        self.assert_path_rejected(path, "FAIL_MIGRATION_FILENAME:")

    def test_path_with_extra_prefix_before_exact_name_is_rejected(self):
        path = self.REAL_PATH.replace("20261012064408_", "20261012064408_x_", 1)
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_path_with_extra_suffix_after_exact_name_is_rejected(self):
        path = self.REAL_PATH.replace("_authority_v1.sql", "_authority_v1_extra.sql")
        self.assert_path_rejected(path, self.FAILURE_CODE)

    def test_exact_name_is_classified(self):
        self.assertTrue(classified(self.EXACT_NAME))

    def test_v2_variants_are_not_classified(self):
        for name in (self.EXACT_NAME.replace("_v1", "_v2"), self.EXACT_NAME + "_v2"):
            with self.subTest(name=name):
                self.assertFalse(classified(name))
                self.assert_path_rejected(
                    f"supabase/migrations/20261012064408_{name}.sql", self.FAILURE_CODE
                )

    def test_name_without_embedded_version_keeps_existing_managed_admission(self):
        # On unmodified main, the existing lf_ prefix already admits this bare
        # name under another outer version as MANAGED. Exact external-name
        # registration must neither broaden nor remove that existing behavior;
        # this filename classifier does not verify ledger version identity.
        bare_name = "lf_pilot_srcr_g12_state_authority_v1"
        path = f"supabase/migrations/20261012064409_{bare_name}.sql"
        self.assertTrue(classified(bare_name))
        self.assertEqual(classify_path(path, self.FAILURE_CODE), (bare_name, "MANAGED"))

    def test_unknown_name_is_not_classified(self):
        name = "totally_unknown_future_migration"
        self.assertFalse(classified(name))
        self.assert_path_rejected(
            f"supabase/migrations/20261012064408_{name}.sql", self.FAILURE_CODE
        )


if __name__ == "__main__":
    unittest.main()
