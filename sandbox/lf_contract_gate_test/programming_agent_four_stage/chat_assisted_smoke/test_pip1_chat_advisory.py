import unittest
from pip1_chat_advisory import advise, AdvisoryError, KNOWN

class Tests(unittest.TestCase):
    def test_states_never_authorize(self):
        for state in KNOWN:
            with self.subTest(state=state):
                x = advise({'checkpoint_id':'PG-02.C1','state':state},expected_checkpoint='PG-02.C1')
                self.assertFalse(x['write_authorized'])
                self.assertFalse(x['transition_authorized'])
                self.assertFalse(x['worker_dispatch_authorized'])
    def test_wrong_checkpoint_blocked(self):
        with self.assertRaises(AdvisoryError):
            advise({'checkpoint_id':'PG-03.C1','state':'ELIGIBLE'},expected_checkpoint='PG-02.C1')
    def test_unknown_state_blocked(self):
        with self.assertRaises(AdvisoryError):
            advise({'checkpoint_id':'PG-02.C1','state':'WRITE'},expected_checkpoint='PG-02.C1')
    def test_invalid_input_blocked(self):
        with self.assertRaises(AdvisoryError):
            advise(None,expected_checkpoint='PG-02.C1')

if __name__=='__main__': unittest.main()
