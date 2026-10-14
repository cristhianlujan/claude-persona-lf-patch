import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lf_migration_source_parity_ci_context import classified


NAMES = (
    "ig_m8_2_per_family_resolver_hook_v1",
    "ig_m8_2_per_family_resolver_facade_v1",
    "ig_m8_6_batch_common_v1",
    "lf_d2_facade_request_plan_v1",
    "lf_d2_facade_receipt_readback_v1",
    "lf_d2_source_binding_candidate_v1",
    "lf_d2_admission_readiness_v1",
    "b2b_scoped_load_metadata_rls_v1",
    "lf_d2_admission_column_grants_v1",
    "lf_source_asset_authority_acl_v1",
    "lf_d2_metadata_admission_split_v1",
    "ig_m99_ekb_jsonb_null_assertion_v1",
    "ig_m99_cohort_authority_reconcile_v1",
    "ig_m99_rollback_receipt_policy_v1",
    "ig_m99_transversal_reconciler_decouple_v1",
    "ig_m99_runtime_proof_gate_contract_v1",
    "ig_m910_versioned_cohort_contract_v1",
    "ig_m99_reversible_consumer_binding_v1",
    "ig_m910_residue_delta_ekb_v1",
    "ig_m912_readiness_ig_owned_contract_v1",
    "ig_m912_receipt_sourcepack_reconcile_v1",
    "ig_m912_ekb_contract_errors_v1",
    "ig_m912_m98_technical_consumption_v1",
    "ig_m913_ledger_independent_contract_v1",
    "ig_m913_ekb_contract_errors_v1",
    "ig_m100_typed_frozen_bundle_contract_v1",
    "ig_m100_human_approval_semantics_v1",
    "ig_m100_ekb_contract_findings_v1",
    "lf_gpt_native_in_chat_capture_policy_candidate_v1",
)


class Lote3ExactExternalClassificationTests(unittest.TestCase):
    def test_exact_ledger_names_are_classified(self):
        self.assertEqual(len(NAMES), 29)
        for name in NAMES:
            with self.subTest(name=name):
                self.assertTrue(classified(name))

    def test_variants_remain_unclassified(self):
        variants = (
            NAMES[0] + "_v2",
            "20261014000000_" + NAMES[0],
            "unregistered_lote3_migration_v1",
        )
        for name in variants:
            with self.subTest(name=name):
                self.assertFalse(classified(name))


if __name__ == "__main__":
    unittest.main()
