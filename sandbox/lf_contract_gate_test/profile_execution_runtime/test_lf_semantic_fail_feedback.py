import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[3] / "scripts"
sys.path.insert(0, str(SCRIPTS))
from lf_semantic_fail_feedback import CHECKS, classify_failure, persist_feedback


def review():
    checks = {name: {"result": True, "reason": "Verified", "source_refs": ["source://a"]}
              for name in CHECKS}
    checks["acceptance_detects_wrong_implementation"] = {
        "result": False, "reason": "Wrong implementation could still be accepted",
        "source_refs": ["source://a"]}
    checks["router_direct_consistency"] = {
        "result": "blocked", "reason": "No comparable direct run",
        "source_refs": ["source://a"]}
    return {"verdict": "FAIL_ACCEPTANCE_WEAK", "decision_checks": checks,
            "candidate_sha256": "a" * 64, "scope_packet_sha256": "b" * 64,
            "source_refs": ["source://a"], "resolved_context_refs": ["context://a"],
            "blocking_codes": ["ACCEPTANCE_WRONG_IMPLEMENTATION_UNDETECTED"]}


class SemanticFailFeedbackTest(unittest.TestCase):
    def test_fail_feedback_preserves_original(self):
        r = review()
        before = json.dumps(r, sort_keys=True)
        out = classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")
        self.assertEqual(json.dumps(r, sort_keys=True), before)
        self.assertEqual(out["outcome"], "RETURN_TO_WORKER")
        self.assertFalse(out["governed_semantic_pass"])
        self.assertFalse(out["producer_executed_by_bridge"])
        self.assertEqual(len(out["failed_checks"]), 2)

    def test_artifact_keeps_review_and_feedback(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "profile-semantic-judge.json"
            result = persist_feedback(review(), "EXEC-EXAMPLE", "PROFILE-A", path)
            data = json.loads(path.read_text())
            self.assertEqual(data["producer_feedback"], result)
            self.assertEqual(data["independent_review"]["verdict"], "FAIL_ACCEPTANCE_WEAK")

    def test_pass_not_accepted_as_fail(self):
        r = review()
        r["verdict"] = "PASS_INDEPENDENT_SEMANTIC"
        with self.assertRaisesRegex(ValueError, "FAILURE_VERDICT_REQUIRED"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_failure_needs_actual_failed_check(self):
        r = review()
        for check in r["decision_checks"].values():
            check["result"] = True
        with self.assertRaisesRegex(ValueError, "WITHOUT_FAILED_CHECKS"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_missing_decision_check_blocked(self):
        r = review()
        del r["decision_checks"]["claims_authorized"]
        with self.assertRaisesRegex(ValueError, "CHECKS_MISMATCH"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_bad_digest_blocked(self):
        r = review()
        r["candidate_sha256"] = "bad"
        with self.assertRaisesRegex(ValueError, "DIGESTS_INVALID"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_missing_evidence_blocked(self):
        r = review()
        r["source_refs"] = []
        with self.assertRaisesRegex(ValueError, "SOURCES_REQUIRED"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_profile_agnostic(self):
        a = classify_failure(review(), "EXEC-A", "PRODUCT-DIRECTOR")
        b = classify_failure(review(), "EXEC-B", "UI-ARCHITECT")
        self.assertEqual(a["failed_checks"], b["failed_checks"])

    def test_observed_independent_review_shape_is_accepted(self):
        r = review()
        r["decision_checks"] = [dict(check=k, **v) for k, v in r["decision_checks"].items()]
        r["candidate_sha"] = "sha256:" + r.pop("candidate_sha256")
        r["scope_sha"] = "sha256:" + r.pop("scope_packet_sha256")
        out = classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")
        self.assertEqual(out["candidate_sha256"], "a" * 64)
        self.assertEqual(out["scope_packet_sha256"], "b" * 64)
        self.assertEqual(len(out["failed_checks"]), 2)

    def test_duplicate_list_checks_rejected(self):
        r = review()
        r["decision_checks"] = [dict(check=k, **v) for k, v in r["decision_checks"].items()]
        r["decision_checks"][0] = r["decision_checks"][1].copy()
        with self.assertRaisesRegex(ValueError, "CHECKS_MISMATCH"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_conflicting_hash_alias_rejected(self):
        r = review()
        r["candidate_sha"] = "sha256:" + "f" * 64
        with self.assertRaisesRegex(ValueError, "DIGESTS_INVALID"):
            classify_failure(r, "EXEC-EXAMPLE", "PROFILE-A")

    def test_blocked_review_does_not_pass(self):
        r = review()
        r["verdict"] = "BLOCKED_SOURCE_INSUFFICIENT"
        self.assertFalse(classify_failure(r, "EXEC-A", "PROFILE-A")["governed_semantic_pass"])


if __name__ == "__main__":
    unittest.main()
