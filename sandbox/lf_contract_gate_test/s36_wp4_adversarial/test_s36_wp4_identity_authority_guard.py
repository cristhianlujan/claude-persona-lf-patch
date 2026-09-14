from __future__ import annotations

import unittest

from s36_wp4_identity_authority_guard import evaluate_identity_authority


class IdentityAuthorityGuardTests(unittest.TestCase):
    def test_positive_independent_authorized(self):
        actual = evaluate_identity_authority(
            producer_execution_id="EXEC-PRODUCER-001",
            reviewer_execution_id="EXEC-REVIEWER-002",
            reviewer_mode="INDEPENDENT_HOLDOUT",
            requested_authority="REVIEW_ONLY",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "PASS", "code": "IDENTITY_AUTHORITY_INVARIANTS_PROVEN"})

    def test_producer_as_reviewer_blocks(self):
        actual = evaluate_identity_authority(
            producer_execution_id="EXEC-SAME",
            reviewer_execution_id="EXEC-SAME",
            reviewer_mode="S36_ASSURANCE",
            requested_authority="REVIEW_ONLY",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "BLOCK", "code": "PRODUCER_AS_REVIEWER"})

    def test_non_independent_mode_blocks(self):
        actual = evaluate_identity_authority(
            producer_execution_id="EXEC-PRODUCER-001",
            reviewer_execution_id="EXEC-REVIEWER-002",
            reviewer_mode="SELF_REVIEW",
            requested_authority="REVIEW_ONLY",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "BLOCK", "code": "REVIEW_MODE_NOT_INDEPENDENT"})

    def test_authority_escalation_blocks(self):
        actual = evaluate_identity_authority(
            producer_execution_id="EXEC-PRODUCER-001",
            reviewer_execution_id="EXEC-REVIEWER-002",
            reviewer_mode="INDEPENDENT_HOLDOUT",
            requested_authority="WRITE_RUNTIME",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "BLOCK", "code": "AUTHORITY_ESCALATION_ATTEMPT"})

    def test_missing_identity_blocks(self):
        actual = evaluate_identity_authority(
            producer_execution_id="",
            reviewer_execution_id="EXEC-REVIEWER-002",
            reviewer_mode="INDEPENDENT_HOLDOUT",
            requested_authority="REVIEW_ONLY",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "BLOCK", "code": "REVIEW_IDENTITY_MISSING"})

    def test_missing_requested_authority_blocks(self):
        actual = evaluate_identity_authority(
            producer_execution_id="EXEC-PRODUCER-001",
            reviewer_execution_id="EXEC-REVIEWER-002",
            reviewer_mode="INDEPENDENT_HOLDOUT",
            requested_authority="",
            granted_authorities=["REVIEW_ONLY"],
        ).as_dict()
        self.assertEqual(actual, {"decision": "BLOCK", "code": "REQUESTED_AUTHORITY_MISSING"})


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(
        "S36_WP4_IDENTITY_AUTHORITY_EXECUTED=1 "
        f"TEST_COUNT={result.testsRun} RESULT={'PASS' if result.wasSuccessful() else 'FAIL'}"
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
