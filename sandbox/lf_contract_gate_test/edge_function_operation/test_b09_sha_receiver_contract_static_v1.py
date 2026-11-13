"""Non-authorizing static proof. PG tests must separately PASS on Docker."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SQL=(ROOT/"supabase/migrations/20261113143831_lf_ig_native_chat_sha_receiver_v1.sql").read_text()
DOWN=(ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_lf_ig_native_chat_sha_receiver_v1.sql").read_text()

class B09ShaReceiverContractStatic(unittest.TestCase):
    def test_live_step70_g15_remain_untouched(self):
        self.assertIn("B09_SHA_RECEIVER_STEP70_OR_G15_SOURCE_DRIFT",SQL)
        self.assertIn("SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED",SQL)
        self.assertNotIn("'status','CRYPTOGRAPHICALLY_VERIFIED'",SQL)
        self.assertIn("'effect_authority',false",SQL)
        self.assertIn("'downstream_execution_allowed',false",SQL)
    def test_no_parallel_writer_or_live_history_rewrite(self):
        self.assertNotIn("CREATE FUNCTION public.lf_ig_native_chat_receipt_register",SQL)
        self.assertNotIn("UPDATE public.lf_operation_execution ",SQL)
        self.assertIn("REVOKE ALL ON public.lf_ig_native_chat_receipt_v1",SQL)
        self.assertIn("B09_RECEIPT_IMMUTABLE",SQL)
        self.assertIn("B09_RUN_NOT_ELIGIBLE",SQL)
    def test_rollback_prohibits_data_loss(self):
        self.assertIn("B09_ROLLBACK_NONEMPTY_NO_DATA_LOSS",DOWN)
        self.assertNotIn("DELETE FROM",DOWN)
        self.assertNotIn("DROP EXTENSION",DOWN)
        self.assertNotIn("DROP TABLE public.lf_operation_execution",DOWN)

if __name__=="__main__":
    unittest.main()
