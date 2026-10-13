"""Pure math controls. Fixtures are synthetic; not GPT Native performance evidence."""
import unittest
from quantitative_method_checks_candidate_v1 import (
    bayesian_posterior, expected_information_gain, pareto_frontier, next_probe_required
)


class Checks(unittest.TestCase):
    def test_bayes_informative(self):
        self.assertAlmostEqual(bayesian_posterior(prior=.5,p_e_given_h=.8,p_e_given_not_h=.2,calibration_ref='fixture://cal'),.8)

    def test_bayes_zero_evidence(self):
        with self.assertRaisesRegex(ValueError,'ZERO_PROBABILITY_EVIDENCE'):
            bayesian_posterior(prior=.5,p_e_given_h=0,p_e_given_not_h=0,calibration_ref='fixture://cal')

    def test_no_calibration_bayes(self):
        with self.assertRaisesRegex(ValueError,'CALIBRATION_REF_REQUIRED'):
            bayesian_posterior(prior=.5,p_e_given_h=.8,p_e_given_not_h=.2,calibration_ref='')

    def test_bool_probability_rejected(self):
        with self.assertRaisesRegex(ValueError,'PROBABILITY_INVALID'):
            bayesian_posterior(prior=True,p_e_given_h=.8,p_e_given_not_h=.2,calibration_ref='fixture://cal')

    def test_voi_informative(self):
        self.assertGreater(expected_information_gain(prior=.5,likelihood_by_outcome=[(.8,.2),(.2,.8)],calibration_ref='fixture://cal'),.2)

    def test_voi_uninformative(self):
        self.assertAlmostEqual(expected_information_gain(prior=.5,likelihood_by_outcome=[(.5,.5),(.5,.5)],calibration_ref='fixture://cal'),0)

    def test_voi_no_calibration(self):
        with self.assertRaisesRegex(ValueError,'CALIBRATION_REF_REQUIRED'):
            expected_information_gain(prior=.5,likelihood_by_outcome=[(.8,.2),(.2,.8)],calibration_ref='')

    def test_voi_unbalanced_outcomes(self):
        with self.assertRaisesRegex(ValueError,'OUTCOME_DISTRIBUTIONS_INVALID'):
            expected_information_gain(prior=.5,likelihood_by_outcome=[(.4,.2),(.2,.8)],calibration_ref='fixture://cal')

    def test_pareto_dominated(self):
        choices=[dict(id='A',quality=.9,cost=2,latency=5,risk=0),dict(id='B',quality=.9,cost=3,latency=6,risk=0),dict(id='C',quality=.8,cost=1,latency=4,risk=0)]
        self.assertEqual(pareto_frontier(choices),['A','C'])

    def test_pareto_no_observation(self):
        with self.assertRaisesRegex(ValueError,'OBSERVED_METRIC_MISSING'):
            pareto_frontier([dict(id='A',quality=.8,cost=1,latency=5)])

    def test_pareto_duplicate(self):
        row=dict(id='A',quality=.8,cost=1,latency=5,risk=0)
        with self.assertRaisesRegex(ValueError,'CANDIDATE_ID_INVALID'):
            pareto_frontier([row,row])

    def test_pareto_invalid_quality(self):
        with self.assertRaisesRegex(ValueError,'OBSERVED_METRIC_INVALID'):
            pareto_frontier([dict(id='A',quality=1.1,cost=1,latency=5,risk=0)])

    def test_duplicate_read(self):
        self.assertFalse(next_probe_required(['r1','r2'],['r1']))

    def test_new_read(self):
        self.assertTrue(next_probe_required(['r1'],['r2']))

    def test_bad_reference(self):
        with self.assertRaisesRegex(ValueError,'EVIDENCE_REF_INVALID'):
            next_probe_required(['r1'],[''])


if __name__=='__main__':
    unittest.main()
