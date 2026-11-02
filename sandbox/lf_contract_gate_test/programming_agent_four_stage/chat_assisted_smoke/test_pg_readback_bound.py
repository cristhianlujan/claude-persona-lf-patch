import unittest
from pg_readback_bound import bind_readback,BoundReadbackError,PLAN

def row():
    return {"plan_code":PLAN,"unit_code":"PG-00","checkpoint_code":"PG-00_C1",
        "status":"PENDING","required":True,"updated_at":"2026-10-28 16:13:20+00",
        "assertion_receipt_sha256":None}
def bind(r,**kw):
    args=dict(expected_plan=PLAN,expected_unit="PG-00",expected_checkpoint="PG-00_C1",source_ref="a"*64)
    args.update(kw)
    return bind_readback(r,**args)

class Tests(unittest.TestCase):
    def test_real_shape_is_non_authoritative(self):
        v=bind(row())
        self.assertFalse(v["source_authenticated"])
        self.assertFalse(v["write_authorized"])
        self.assertFalse(v["pip1_run_bound"])
    def test_cross_plan_rejected(self):
        with self.assertRaises(BoundReadbackError):bind({**row(),"plan_code":"OTHER"})
    def test_bad_source_rejected(self):
        with self.assertRaises(BoundReadbackError):bind(row(),source_ref="not-a-hash")
    def test_run_cannot_be_claimed(self):
        with self.assertRaises(BoundReadbackError):bind(row(),run_id=5)
    def test_invalid_receipt_hash_rejected(self):
        with self.assertRaises(BoundReadbackError):bind({**row(),"assertion_receipt_sha256":"fake"})
    def test_missing_timestamp_rejected(self):
        with self.assertRaises(BoundReadbackError):bind({**row(),"updated_at":None})
if __name__=="__main__":unittest.main()
