import unittest
from profile_ochiai_candidate_v1 import rank_ochiai


def sample():
    return [{"case_id": str(i), "failed": f, "covered": x, "frozen": True,
             "subject_sha256": "a"*64, "execution_receipt_ref": "exec://"+str(i),
             "evaluator_receipt_ref": "judge://"+str(i), "independent_evaluator": True}
            for i, (f,x) in enumerate([(True,["A","B"]),(True,["A"]),(False,["B"])])]


class Checks(unittest.TestCase):
    def test_positive(self):
        r=rank_ochiai(sample(),["A","B"])
        self.assertEqual(r["status"],"RANKED_CANDIDATES_NOT_CAUSAL_PROOF")
        self.assertEqual([x["suspect"] for x in r["ranking"]],["A","B"])
        self.assertAlmostEqual(r["ranking"][0]["score"],1)
        self.assertAlmostEqual(r["ranking"][1]["score"],.5)
        self.assertFalse(r["expertise_certified"])
    def test_no_control(self):
        a=sample()[:2]
        self.assertEqual(rank_ochiai(a,["A","B"])["status"],"NOT_OBSERVED")
    def test_not_independent(self):
        a=sample();a[0]["independent_evaluator"]=False
        self.assertEqual(rank_ochiai(a,["A","B"])["reason"],"INDEPENDENT_EVALUATOR_REQUIRED")
    def test_invalid_coverage(self):
        a=sample();a[1]["covered"]=["A","A"]
        self.assertEqual(rank_ochiai(a,["A","B"])["reason"],"COVERAGE_INVALID")
    def test_identity_drift(self):
        a=sample();a[1]["subject_sha256"]="b"*64
        self.assertEqual(rank_ochiai(a,["A","B"])["reason"],"FROZEN_SUBJECT_MISMATCH")
    def test_no_auto_admission(self):
        self.assertFalse(rank_ochiai(sample(),["A","B"])["cutover_eligible"])

if __name__ == "__main__": unittest.main()
