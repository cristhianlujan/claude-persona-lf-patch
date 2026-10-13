import unittest
from profile_delta_debug_candidate_v1 import minimize_failure


class Checks(unittest.TestCase):
    def test_ddmin(self):
        r=minimize_failure(['a','b','c','d'], lambda xs: 'a' in xs and 'b' in xs)
        self.assertEqual(r['status'],'ONE_MINIMAL_REPRODUCER')
        self.assertEqual(r['atoms'],['a','b'])
        self.assertFalse(r['globally_minimal'])
        self.assertFalse(r['cutover_eligible'])
    def test_simple(self):
        r=minimize_failure(['a'],lambda xs: 'a' in xs)
        self.assertEqual(r['status'],'ONE_MINIMAL_REPRODUCER')
    def test_no_reproduction(self):
        self.assertEqual(minimize_failure(['a','b'],lambda _:False)['status'],'NOT_REPRODUCED')
    def test_budget(self):
        r=minimize_failure(['a','b','c','d'],lambda _:True,probe_budget=1)
        self.assertEqual(r['status'],'INCOMPLETE_BUDGET')
        self.assertFalse(r['minimality_proven'])
    def test_non_boolean(self):
        self.assertEqual(minimize_failure(['a'],lambda _:1)['reason'],'PREDICATE_NOT_BINARY')
    def test_duplicate_atom(self):
        self.assertEqual(minimize_failure(['a','a'],lambda _:True)['reason'],'ATOMS_INVALID')
    def test_missing_predicate(self):
        self.assertEqual(minimize_failure(['a'],None)['reason'],'SAFE_PREDICATE_REQUIRED')
    def test_invalid_budget(self):
        self.assertEqual(minimize_failure(['a'],lambda _:True,probe_budget=True)['reason'],'PROBE_BUDGET_INVALID')

if __name__=='__main__':unittest.main()
