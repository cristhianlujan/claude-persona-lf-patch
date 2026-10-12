from __future__ import annotations

import pathlib
import sys
import unittest

PARITY = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(PARITY.parent))
sys.path.insert(0, str(PARITY))
from lf_migration_source_parity_ci_context import classified, managed  # noqa: E402

FAMILY_EXAMPLES = {
    "analysis_a9_pg01_": "analysis_a9_pg01_receipt_digest_guard_fix_v1",
    "ig_m9_m10_contract_preflight_": "ig_m9_m10_contract_preflight_v1",
    "b2b_effective_menu_grants_": "b2b_effective_menu_grants_v1",
    "b2b_shell_nav_order_reconcile_": "b2b_shell_nav_order_reconcile_v1",
    "ig_ci50_qualification_activation_": "ig_ci50_qualification_activation_v1",
    "ig_m82_resolver_timing_sink_": "ig_m82_resolver_timing_sink_v2",
    "ig_candidate_action_receipt_consumption_": "ig_candidate_action_receipt_consumption_v1",
    "ig_test_deliverable_misbind_repair_": "ig_test_deliverable_misbind_repair_v1",
    "ig_m5_4_remove_legacy_resolver_calls": "ig_m5_4_remove_legacy_resolver_calls",
    "ig_m5_5_explicit_fingerprint": "ig_m5_5_explicit_fingerprint",
    "programming_context_snapshot_runtime_guard_": "programming_context_snapshot_runtime_guard_v1",
    "engineering_specific_technical_contract_reduction_": "engineering_specific_technical_contract_reduction_v1",
    "engineering_transversal_read_only_measure_adapter_": "engineering_transversal_read_only_measure_adapter_v1",
    "intelligence_method_portfolio_": "intelligence_method_portfolio_v1",
}


class MigrationNameFamilyClassificationTest(unittest.TestCase):
    def test_each_reviewed_family_is_managed(self) -> None:
        for prefix, name in FAMILY_EXAMPLES.items():
            with self.subTest(family=prefix):
                self.assertTrue(managed(name))
                self.assertTrue(classified(name))

    def test_unreviewed_name_still_fails_closed(self) -> None:
        self.assertFalse(classified("f0_unreviewed_name_v1"))

    def test_ig_cv_remains_external_not_managed_by_ig_root(self) -> None:
        name = "ig_cv_n13_continuation_currentness_requiredness_v1"
        self.assertTrue(classified(name))
        self.assertFalse(managed(name))


if __name__ == "__main__":
    unittest.main()
