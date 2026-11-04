import unittest
from pg_chat_readback_flow import summarize_observation, PLAN
class Tests(unittest.TestCase):
    def setUp(self):
        self.row = dict(plan_code=PLAN,unit_code="PG-00",checkpoint_code="PG-00_C1",
                        status="PENDING",required=True,updated_at="2026-10-28 16:13:20.084475+00")
    def call(self):
        return summarize_observation(self.row,unit="PG-00",checkpoint="PG-00_C1")
    def test_pending_stops(self):
        self.assertFalse(self.call()["write_authorized"])
    def test_done_cannot_authorize(self):
        self.row["status"]="DONE"
        self.assertFalse(self.call()["worker_dispatch_authorized"])
    def test_cross_checkpoint_rejected(self):
        self.row["checkpoint_code"]="PG-00_C2"
        with self.assertRaises(ValueError): self.call()
    def test_cross_plan_rejected(self):
        self.row["plan_code"]="OTHER"
        with self.assertRaises(ValueError): self.call()
if __name__=="__main__":unittest.main()
