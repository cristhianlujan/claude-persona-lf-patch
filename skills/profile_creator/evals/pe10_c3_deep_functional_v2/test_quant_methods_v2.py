from __future__ import annotations
import math,unittest
from .quant_methods_v2 import complaints_risk,allocation_balance,expected_net,beta_sf,beta_upper_quantile

class DecisionMathV2Tests(unittest.TestCase):
    def test_beta_closed_forms(self):
        self.assertAlmostEqual(beta_sf(.2,1,1),.8,places=11)
        self.assertAlmostEqual(beta_sf(.2,2,1),.96,places=11)
        self.assertAlmostEqual(beta_sf(.2,1,2),.64,places=11)
        self.assertAlmostEqual(beta_upper_quantile(.95,1,1),.95,places=10)
    def test_actual_small_sample_5_1000(self):
        r=complaints_risk(events=5,exposures=1000,limit=.01)
        self.assertAlmostEqual(r["observed_rate"],.005)
        self.assertAlmostEqual(r["posterior_pr_exceeds_guardrail"],.0657649804911695,places=8)
        self.assertAlmostEqual(r["posterior_upper95"],.0104736321870167,places=8)
        self.assertFalse(r["observed_guardrail_exceeded"])
        self.assertGreater(r["wilson_upper95"],.01)
    def test_risky_observed_30_1000(self):
        r=complaints_risk(events=30,exposures=1000,limit=.01)
        self.assertTrue(r["observed_guardrail_exceeded"])
        self.assertGreater(r["posterior_pr_exceeds_guardrail"],.999)
    def test_posterior_prior_sensitivity(self):
        a=complaints_risk(events=5,exposures=1000,limit=.01,prior_a=1,prior_b=1)
        b=complaints_risk(events=5,exposures=1000,limit=.01,prior_a=.5,prior_b=.5)
        self.assertNotEqual(a["posterior_pr_exceeds_guardrail"],b["posterior_pr_exceeds_guardrail"])
    def test_SRM(self):
        r=allocation_balance(control=670,treatment=830)
        self.assertAlmostEqual(r["z_normal_approximation"],4.131182235954578,places=8)
        self.assertLess(r["p_value_two_sided_normal_approximation"],.00005)
        self.assertTrue(r["small_p_warning"])
        self.assertFalse(r["causal_claim_allowed"])
    def test_expected_net(self):
        a=expected_net(paid_amount=120,probability_paid=.4,cost=3,complaint_probability=.005,complaint_cost=40)
        b=expected_net(paid_amount=120,probability_paid=.5,cost=6,complaint_probability=.03,complaint_cost=40)
        self.assertAlmostEqual(a["expected_net"],44.8)
        self.assertAlmostEqual(b["expected_net"],52.8)
        self.assertEqual(round(b["expected_net"]-a["expected_net"],8),8)
    def test_fail_closed_bad_inputs(self):
        for kwargs in (
            {"events":6,"exposures":5,"limit":.01},
            {"events":-1,"exposures":100,"limit":.01},
            {"events":5,"exposures":0,"limit":.01},
            {"events":5,"exposures":100,"limit":0},
        ):
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError):
                complaints_risk(**kwargs)
        with self.assertRaises(ValueError):allocation_balance(control=100,treatment=-1)
        with self.assertRaises(ValueError):expected_net(paid_amount=200,probability_paid=1.2,cost=1,complaint_probability=.1,complaint_cost=20)
    def test_monotonic_risk(self):
        vals=[complaints_risk(events=e,exposures=1000,limit=.01)["posterior_pr_exceeds_guardrail"] for e in (2,5,8,11,25)]
        self.assertEqual(vals,sorted(vals))
if __name__=="__main__":unittest.main()
