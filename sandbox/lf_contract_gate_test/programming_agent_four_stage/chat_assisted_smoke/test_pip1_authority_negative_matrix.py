"""Adversarial boundary tests, not an operational authority verifier."""
import unittest
from pip1_core.core import Pins, RunContract, Inventory, State, Receipt, Outcome, transition, PIPError
from pip1_operation_preflight import compare_operation, PreflightError

def scenario():
    pins=Pins("a"*40,"b"*64,"c"*64,"d"*64)
    run=RunContract("PIP-1","1","exec-synthetic","run-synthetic","chat","fixture",pins)
    inventory=Inventory("1","d"*64,frozenset(),{"PG-02":("PG-02.C1",)},
                        {"PG-02":frozenset()},frozenset())
    operation={"execution_id":run.execution_id,
               "operation_code":"CIERRE_CHECKPOINT_INGENIERIA_LF",
               "target_type":"ENGINEERING_CHECKPOINT","status":"CREATED",
               "manifest":{"pip1_run_id":run.run_id,
                           "inventory_sha256":run.pins.inventory_sha256,
                           "head_sha":run.pins.head_sha}}
    receipt=Receipt(run.execution_id,run.run_id,"PG-02.C1",run.pins.head_sha,
                    run.pins.fingerprint(),"provider-fixture","e"*64,"PASS")
    return run,inventory,operation,receipt

class NegativeMatrix(unittest.TestCase):
    def test_synthetic_receipt_cannot_accredit(self):
        run,inv,op,receipt=scenario()
        with self.assertRaises(PIPError):
            transition(State.PENDING,State.SUCCEEDED_ACCREDITED,run=run,
                       checkpoint_id="PG-02.C1",inventory=inv,outcomes={},receipt=receipt)
    def test_operational_eligible_closed(self):
        run,inv,op,receipt=scenario()
        with self.assertRaisesRegex(PIPError,"EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED"):
            transition(State.PENDING,State.ELIGIBLE,run=run,
                       checkpoint_id="PG-02.C1",inventory=inv,outcomes={},operational=True)
    def test_receipt_replay_other_run(self):
        run,inv,op,receipt=scenario()
        other=RunContract("PIP-1","1","exec-synthetic","run-other","chat","fixture",run.pins)
        self.assertFalse(receipt.valid(other,"PG-02.C1"))
    def test_receipt_other_checkpoint(self):
        run,inv,op,receipt=scenario()
        self.assertFalse(receipt.valid(run,"PG-02.C2"))
    def test_receipt_head_drift(self):
        run,inv,op,receipt=scenario()
        pins=Pins("f"*40,"b"*64,"c"*64,"d"*64)
        other=RunContract("PIP-1","1","exec-synthetic","run-synthetic","chat","fixture",pins)
        self.assertFalse(receipt.valid(other,"PG-02.C1"))
    def test_operation_wrong_run(self):
        run,inv,op,receipt=scenario()
        op["manifest"]["pip1_run_id"]="run-other"
        with self.assertRaises(PreflightError):
            compare_operation(run,op,observed_inventory_sha256=inv.digest)
    def test_operation_inventory_drift(self):
        run,inv,op,receipt=scenario()
        op["manifest"]["inventory_sha256"]="f"*64
        with self.assertRaises(PreflightError):
            compare_operation(run,op,observed_inventory_sha256=inv.digest)
    def test_operation_wrong_execution(self):
        run,inv,op,receipt=scenario()
        op["execution_id"]="exec-other"
        with self.assertRaises(PreflightError):
            compare_operation(run,op,observed_inventory_sha256=inv.digest)
    def test_shape_match_never_authorizes(self):
        run,inv,op,receipt=scenario()
        r=compare_operation(run,op,observed_inventory_sha256=inv.digest)
        self.assertFalse(r["authority_verified"])
        self.assertFalse(r["checkpoint_accredited"])
        self.assertFalse(r["write_authorized"])

if __name__=="__main__":
    unittest.main()
