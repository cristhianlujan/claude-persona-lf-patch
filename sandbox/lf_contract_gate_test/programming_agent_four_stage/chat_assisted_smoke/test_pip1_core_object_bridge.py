import unittest
from pip1_core_object_bridge import advise_pip1, AdvisoryError
from pip1_core.core import Pins,RunContract,Inventory,Outcome,State

def sample():
    pins=Pins('a'*40,'b'*64,'c'*64,'d'*64)
    run=RunContract('PIP-1','1','exec-test','run-test','chat','synthetic',pins)
    inventory=Inventory('1','d'*64,frozenset(),{'PG-02':('PG-02.C1',)},{'PG-02':frozenset()},frozenset())
    return run,inventory

class BridgeTests(unittest.TestCase):
    def test_pending_never_authorizes(self):
        run,inv=sample()
        x=advise_pip1(run,inv,{},checkpoint_id='PG-02.C1')
        self.assertEqual(x['observed_state'],'PENDING')
        self.assertFalse(x['worker_dispatch_authorized'])
    def test_accredited_requires_external_readback(self):
        run,inv=sample()
        x=advise_pip1(run,inv,{'PG-02.C1':Outcome(State.SUCCEEDED_ACCREDITED,'x','x')},checkpoint_id='PG-02.C1')
        self.assertEqual(x['suggested_next'],'EXTERNAL_AUTHORITY_READBACK_REQUIRED')
        self.assertFalse(x['transition_authorized'])
    def test_mismatched_inventory_rejected(self):
        run,inv=sample()
        inv=Inventory('1','e'*64,inv.pg00,inv.checkpoints,inv.requires,inv.excluded)
        with self.assertRaisesRegex(AdvisoryError,'INVENTORY_PIN_MISMATCH'):
            advise_pip1(run,inv,{},checkpoint_id='PG-02.C1')
    def test_unknown_checkpoint_rejected(self):
        run,inv=sample()
        with self.assertRaisesRegex(AdvisoryError,'CHECKPOINT_NOT_IN_INVENTORY'):
            advise_pip1(run,inv,{},checkpoint_id='PG-03.C1')
    def test_invalid_run_rejected(self):
        run,inv=sample()
        run=RunContract('OTHER','1','exec-test','run-test','chat','synthetic',run.pins)
        with self.assertRaisesRegex(AdvisoryError,'PIP1_OBJECT_INVALID'):
            advise_pip1(run,inv,{},checkpoint_id='PG-02.C1')
if __name__=='__main__':unittest.main()
