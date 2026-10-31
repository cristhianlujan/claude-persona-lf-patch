import unittest
from pg_ledger_readback_advisory import project_checkpoint_row,ReadbackBlocked

def source(status="PENDING",receipt=False):
    return {"unit_code":"PG-00","checkpoint_code":"PG-00_C1","status":status,"required":True,"has_receipt":receipt}

class Tests(unittest.TestCase):
    def call(self,r):
        return project_checkpoint_row(r,expected_unit="PG-00",expected_checkpoint="PG-00_C1")
    def test_pending_blocks(self):
        x=self.call(source())
        self.assertFalse(x["worker_dispatch_authorized"])
        self.assertFalse(x["transition_authorized"])
    def test_done_without_receipt_cannot_authorize(self):
        x=self.call(source("DONE"))
        self.assertFalse(x["pip1_outcome_accredited"])
    def test_present_receipt_not_verified(self):
        x=self.call(source("DONE",True))
        self.assertTrue(x["receipt_present_unverified"])
        self.assertFalse(x["write_authorized"])
    def test_wrong_checkpoint_rejected(self):
        with self.assertRaises(ReadbackBlocked):self.call({**source(),"checkpoint_code":"PG-00_C2"})
    def test_unknown_status_rejected(self):
        with self.assertRaises(ReadbackBlocked):self.call(source("SUPER_PASS"))
    def test_missing_required_boolean_rejected(self):
        with self.assertRaises(ReadbackBlocked):self.call({**source(),"required":"true"})
if __name__=="__main__":unittest.main()
