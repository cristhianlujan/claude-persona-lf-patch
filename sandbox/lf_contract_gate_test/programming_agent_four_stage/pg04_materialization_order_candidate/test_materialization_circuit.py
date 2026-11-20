import unittest
from materialization_circuit import Circuit, CircuitBlocked
ACTIONS = ['PG01_ADMITTED','TASK_DRAFT_CREATED','TASK_SEALED_BY_DB',
           'BLIND_TEST_CONTRACT_DRAFT','BLIND_TEST_CONTRACT_SEALED_BY_DB',
           'DELIVERY_CONTRACT_DRAFT','DELIVERY_CONTRACT_SEALED_BY_DB','DB_READINESS_CONFIRMED']
class CircuitTests(unittest.TestCase):
    def test_full_simulation_remains_non_authoritative(self):
        c = Circuit()
        for action in ACTIONS: c.advance(action, authenticated=True)
        self.assertEqual(c.stage, 'READINESS_CONFIRMED')
        self.assertFalse(c.snapshot()['dispatch_allowed'])
        self.assertTrue(c.snapshot()['state_is_simulated'])
    def test_every_stage_rejects_missing_external_proof(self):
        c = Circuit()
        for action in ACTIONS:
            with self.assertRaisesRegex(CircuitBlocked, 'EXTERNAL_AUTHORITY_EVIDENCE_REQUIRED'):
                c.advance(action)
            c.advance(action, authenticated=True)
    def test_cannot_skip_task_seal(self):
        c=Circuit();c.advance(ACTIONS[0], authenticated=True);c.advance(ACTIONS[1], authenticated=True)
        with self.assertRaisesRegex(CircuitBlocked,'INVALID_ORDER'):
            c.advance('BLIND_TEST_CONTRACT_DRAFT',authenticated=True)
    def test_cannot_seal_delivery_before_test(self):
        c=Circuit()
        for a in ACTIONS[:4]:c.advance(a,authenticated=True)
        with self.assertRaisesRegex(CircuitBlocked,'INVALID_ORDER'):
            c.advance('DELIVERY_CONTRACT_SEALED_BY_DB',authenticated=True)
    def test_no_dispatch_after_simulated_readiness(self):
        c=Circuit()
        for a in ACTIONS:c.advance(a,authenticated=True)
        with self.assertRaisesRegex(CircuitBlocked,'INVALID_ORDER'):
            c.advance('WORKER_DISPATCH',authenticated=True)
    def test_no_mutation_on_rejected_transition(self):
        c=Circuit();snap=c.snapshot()
        with self.assertRaises(CircuitBlocked):c.advance(ACTIONS[2],authenticated=True)
        self.assertEqual(snap,c.snapshot())
if __name__=='__main__':unittest.main()
