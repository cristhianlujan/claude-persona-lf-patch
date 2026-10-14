import unittest
from .causal_diagnosis_v2 import update_diagnosis
H=[{"id":"stale","prior":.2},{"id":"auth","prior":.5},{"id":"race","prior":.3}]
E=[{"evidence_ref":"readback://test/1","origin_id":"independent-provider-1",
    "likelihood_by_hypothesis":{"stale":.05,"auth":.9,"race":.4}}]
PROBES=[
 {"probe_id":"probe-token","pr_positive_given_hypothesis":{"stale":.03,"auth":.95,"race":.08}},
 {"probe_id":"probe-reload","pr_positive_given_hypothesis":{"stale":.9,"auth":.3,"race":.5}},
 {"probe_id":"probe-nondiscriminative","pr_positive_given_hypothesis":{"stale":.5,"auth":.5,"race":.5}},
]
class BayesianCausalTests(unittest.TestCase):
    def test_posterior_with_competing_explanations(self):
        r=update_diagnosis(H,E,PROBES)
        self.assertAlmostEqual(r["posterior"]["auth"],.45/.58,places=9)
        self.assertAlmostEqual(r["posterior"]["race"],.12/.58,places=9)
        self.assertAlmostEqual(r["posterior"]["stale"],.01/.58,places=9)
        self.assertEqual(r["ranking"][0]["id"],"auth")
        self.assertFalse(r["root_cause_certified"])
        self.assertFalse(r["cutover_eligible"])
    def test_information_gain_prefers_discriminating_probes(self):
        r=update_diagnosis(H,E,PROBES)
        self.assertAlmostEqual(next(x["expected_information_gain_bits"] for x in r["next_probes"] if x["probe_id"]=="probe-nondiscriminative"),0,places=12)
        self.assertGreater(r["next_probes"][0]["expected_information_gain_bits"],0)
        self.assertTrue(all(not x["probe_executed"] for x in r["next_probes"]))
    def test_sequential_new_evidence_changes_posterior_not_history(self):
        old=update_diagnosis(H,E)
        more=E+[{"evidence_ref":"readback://test/2","origin_id":"independent-provider-2",
            "likelihood_by_hypothesis":{"stale":.05,"auth":.1,"race":.8}}]
        new=update_diagnosis(H,more)
        self.assertEqual(old["posterior"],new["evidence_history"][0]["posterior"])
        self.assertLess(new["posterior"]["auth"],old["posterior"]["auth"])
        self.assertGreater(new["posterior"]["race"],old["posterior"]["race"])
    def test_correlated_evidence_double_count_blocked(self):
        x=E+[dict(E[0])]
        with self.assertRaisesRegex(ValueError,"CORRELATED_SOURCE_DOUBLE_COUNT"):
            update_diagnosis(H,x)
    def test_inconsistent_model_fails_closed(self):
        x=[{**E[0],"likelihood_by_hypothesis":{h["id"]:0 for h in H}}]
        with self.assertRaisesRegex(ValueError,"EVIDENCE_MODEL_INCONSISTENT"):
            update_diagnosis(H,x)
    def test_bad_prior_fails_closed(self):
        with self.assertRaisesRegex(ValueError,"PRIORS_NOT_NORMALIZED"):
            update_diagnosis([{**H[0],"prior":.4}]+H[1:],E)
if __name__=="__main__":unittest.main()
