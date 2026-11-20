"""Source-grounded candidate regression; NOT an independent semantic judge or runtime test."""
import copy
import json
import unittest
from pathlib import Path

FIXTURE = (
    Path(__file__).resolve().parents[4]
    / "docs/input-governance/IG_EVO_AUTH021_SEMANTIC_CANDIDATE_V1.json"
)

REQUIRED_PENDING = {
    "OBTAIN_EXACT_INTENT_CONTEXT_SHA256_VIA_GOVERNED_CURATOR",
    "RESOLVE_FAMILIES_AGAINST_RUN_REGISTRY",
    "NATIVE_CURATOR_SEMANTIC_EXECUTION",
    "INDEPENDENT_NATIVE_VALIDATOR_REVIEW",
    "RUNTIME_SECURITY_POSITIVE_NEGATIVE_ADVERSARIAL_TESTS",
    "CONSUMER_ENFORCEMENT_AT_EFFECT_BOUNDARY",
}


def safe_candidate(doc):
    """Pure fixture shape check; NEVER returns semantic PASS."""
    if doc.get("schema_version") != "IG_EVO_INTENT_ANALYSIS_V1_CANDIDATE":
        return False
    if doc.get("context_sha256") is not None:
        return False  # this fixture cannot attest the governed Curator source graph
    if doc.get("execution_mode") != "CURRENT_CONTEXT_MODEL_REVIEW_NOT_INDEPENDENT":
        return False
    for key in ("semantic_quality_evaluated", "semantic_pass_authorized",
                "runtime_enforcement_verified", "qa_verified",
                "promotion_authorized", "production_authorized"):
        if doc.get(key) is not False:
            return False
    if doc.get("semantic_quality_verdict") != "NOT_TESTED":
        return False
    signals = doc.get("candidate_signals")
    scenarios = doc.get("test_scenarios")
    if not isinstance(signals, list) or not signals:
        return False
    if not isinstance(scenarios, list) or not scenarios:
        return False
    ids = [s.get("signal_id") for s in signals]
    if len(ids) != len(set(ids)) or any(not sid for sid in ids):
        return False
    expected_types = {"EXPLICIT_RULE_STATEMENT", "GOVERNED_POLICY_REFERENCE"}
    required = {"signal_id", "intent_role", "expected_behavior", "reasoning",
                "evidence_type", "source_locations", "candidate_family_codes",
                "graph_edge_refs", "unresolved_reason", "resolution"}
    for signal in signals:
        if not required.issubset(signal):
            return False
        if signal["evidence_type"] not in expected_types:
            return False
        if signal["resolution"] != "UNMATCHED_RESEARCH_REQUIRED":
            return False
        locs = signal["source_locations"]
        if not isinstance(locs, list) or not locs:
            return False
        if any(not x.get("source_ref") or not x.get("verbatim_anchor")
               for x in locs):
            return False
    for scenario in scenarios:
        if scenario.get("execution_status") != "NOT_TESTED":
            return False
        if scenario.get("semantic_judge_verdict") != "NOT_TESTED":
            return False
        if scenario.get("runtime_evidence_refs") != []:
            return False
        if not scenario.get("related_signal_ids"):
            return False
        if any(x not in ids for x in scenario["related_signal_ids"]):
            return False
    if not REQUIRED_PENDING.issubset(set(doc.get("pending", []))):
        return False
    return True


class IntentCandidateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_candidate_shape_source_grounded(self):
        self.assertTrue(safe_candidate(self.fixture))
        self.assertEqual(len(self.fixture["candidate_signals"]), 10)
        self.assertEqual(len(self.fixture["test_scenarios"]), 7)
        self.assertEqual(
            {s["kind"] for s in self.fixture["test_scenarios"]},
            {"POSITIVE", "NEGATIVE", "ADVERSARIAL"},
        )

    def test_status_guards_are_fail_closed(self):
        for key in ("semantic_quality_evaluated", "semantic_pass_authorized",
                    "runtime_enforcement_verified", "qa_verified",
                    "promotion_authorized", "production_authorized"):
            changed = copy.deepcopy(self.fixture)
            changed[key] = True
            with self.subTest(key=key):
                self.assertFalse(safe_candidate(changed))

    def test_no_fabricated_runtime_receipts(self):
        changed = copy.deepcopy(self.fixture)
        changed["test_scenarios"][0]["execution_status"] = "PASS"
        self.assertFalse(safe_candidate(changed))
        changed = copy.deepcopy(self.fixture)
        changed["test_scenarios"][0]["runtime_evidence_refs"] = ["invented"]
        self.assertFalse(safe_candidate(changed))

    def test_no_bare_obligation_without_source(self):
        changed = copy.deepcopy(self.fixture)
        changed["candidate_signals"][0]["source_locations"] = []
        self.assertFalse(safe_candidate(changed))

    def test_no_duplicate_or_unaccounted_scenario(self):
        changed = copy.deepcopy(self.fixture)
        changed["candidate_signals"][1]["signal_id"] = changed["candidate_signals"][0]["signal_id"]
        self.assertFalse(safe_candidate(changed))
        changed = copy.deepcopy(self.fixture)
        changed["test_scenarios"][0]["related_signal_ids"] = ["NOT_IN_SOURCE"]
        self.assertFalse(safe_candidate(changed))

    def test_no_false_semantic_match_or_authority(self):
        changed = copy.deepcopy(self.fixture)
        changed["candidate_signals"][0]["resolution"] = "MATCHED_TO_GRAPH"
        self.assertFalse(safe_candidate(changed))
        changed = copy.deepcopy(self.fixture)
        changed["pending"].remove("INDEPENDENT_NATIVE_VALIDATOR_REVIEW")
        self.assertFalse(safe_candidate(changed))

    def test_candidate_policy_is_not_runtime_proof(self):
        policies = self.fixture["source_scope"]["linked_policies"]
        self.assertEqual([p["id"] for p in policies], [1, 17, 22])
        self.assertEqual([p["source_status"] for p in policies],
                         ["VIGENTE", "VIGENTE", "CANDIDATO"])
        self.assertTrue(all(p["screen_binding_status"] == "CANDIDATO" for p in policies))
        self.assertTrue(all(p["runtime_enforcement_verified"] is False for p in policies))


if __name__ == "__main__":
    unittest.main()
