"""Quality 497B historical CURRENT_CONTEXT evidence; new owner policy allows score gate.

PG17/PG18 behavioral tests live in test_owner_rule_promotion_score_current_context_pgdual_v1.py.
This test replaces the obsolete NOT_ATTESTED expectation from PR #4000.
The old migration remains an intact historical source; the new version overrides it.
"""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql"

QUALITY_STEP70_SELECT={
    "execution_id":"EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C",
    "review_mode":"CURRENT_CONTEXT_REVIEW",
    "verdict":"PASS_REVIEWED_CURRENT_CONTEXT",
    "reviewer_is_producer":True,
    "producer_independence_proven":False,
    "model_call_count":0,
    "judge_independence_status":"NOT_PROVEN",
}

class QualityHistoricalEvidenceOwnerScoreTest(unittest.TestCase):
    def test_owner_score_does_not_claim_judge_independence(self):
        self.assertTrue(QUALITY_STEP70_SELECT["reviewer_is_producer"])
        self.assertFalse(QUALITY_STEP70_SELECT["producer_independence_proven"])
        self.assertEqual(QUALITY_STEP70_SELECT["judge_independence_status"],"NOT_PROVEN")
        sql=MIG.read_text(encoding="utf-8")
        request=sql.split("-- LF_OWNER_SCORE_REQUEST_BEGIN",1)[1].split(
            "-- LF_OWNER_SCORE_REQUEST_END",1)[0]
        score=sql.split("-- LF_OWNER_SCORE_SCORER_BEGIN",1)[1].split(
            "-- LF_OWNER_SCORE_SCORER_END",1)[0]
        self.assertIn("PASS_REVIEWED_CURRENT_CONTEXT",request)
        self.assertIn("PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED",request)
        self.assertNotIn("PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED",request)
        self.assertNotIn("judge_invocation_kind",request)
        self.assertNotIn("judge_role",request)
        self.assertIn("NOT_PROVEN_OWNER_ACCEPTED",score)

if __name__=="__main__":
    unittest.main()
