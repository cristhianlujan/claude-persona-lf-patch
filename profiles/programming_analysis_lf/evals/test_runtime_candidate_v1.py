#!/usr/bin/env python3
"""Source-only Analysis candidate tests: structural PASS and FAIL must both work."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(relative, label):
    spec = importlib.util.spec_from_file_location(label, ROOT / relative)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


V = load("validators/runtime_validate.py", "analysis_contract_validator")
U = load("validators/runtime_semantic_utility.py", "analysis_semantic_floor")


def blocked():
    return {
        "schema_version": "ANALYSIS_IMPLEMENTATION_PACKAGE_V1",
        "candidate_only": True,
        "request_context": {"intent": "Change a capability with unresolved authority", "target_ref": "target://unresolved", "business": "LF"},
        "classification": {"target_granularity": "RULE", "depth": "L2", "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN",
                           "initial_intent_kind": "UNKNOWN", "initial_development_class": "NEED_MORE_EVIDENCE",
                           "initial_evidence_refs": ["router-handoff://candidate", "user-request://candidate"]},
        "stage_trace": [
            {"stage": f"A{i}", "outcome": f"Stage A{i} preserved unresolved evidence", "source_refs": []}
            for i in range(1, 10)
        ],
        "definition_source_reception": {"status": "UNRESOLVED", "business": "LF", "target_ref": None,
                                        "source_refs": [], "source_currentness": "NOT_ATTESTED",
                                        "transport_status": "NOT_ATTESTED", "rule_count": None},
        "material_unknowns": [{"unknown_id": "U1", "scope_id": "S1", "question": "Which canonical authority owns the rule?"}],
        "decisions_pending": [],
        "requirements": [],
        "material_fronts": [{"front_id": "F1", "scope_ids": ["S1"], "obligation_mode": "REQUIRED",
                             "closure": "BLOCKED", "blockers": ["AUTHORITY_UNKNOWN"],
                             "evidence_refs": [], "reason": "Unresolved authority"}],
        "scope_proposals": [{"scope_id": "S1", "readiness_candidate": "BLOCKED",
                             "material_front_refs": ["F1"], "blockers": ["AUTHORITY_UNKNOWN"]}],
        "research_stop": {"decision": "CONTINUE", "decision_stable": False, "all_material_fronts_accounted": True,
                          "unresolved_decision_changing_questions": ["Which canonical authority owns the rule?"]},
        "package_readiness_candidate": "BLOCKED",
    }


def ready_candidate():
    payload = blocked()
    payload["request_context"]["target_ref"] = "authority://verified-target"
    payload["classification"].update(depth="L2", authority_state="EXISTING", implementation_state="EXISTING",
                                     initial_intent_kind="EVOLVE",
                                     initial_development_class="EXISTING_EVOLUTION_CANDIDATE")
    payload["definition_source_reception"].update(status="FOUND_UNATTESTED",target_ref="source://fictional-fixture",
                                                  source_refs=["source://evidence-fixture"],rule_count=3)
    payload["material_unknowns"] = []
    payload["requirements"] = [{"requirement_id": "R1", "scope_id": "S1",
                                 "outcome": "Preserve governed current behavior while changing requested state",
                                 "acceptance_signal": "Verified source ref and behavior state remain equal to authorized requirements",
                                 "evidence_refs": ["evidence://source-current"]}]
    payload["material_fronts"][0].update(closure="CLOSED", blockers=[],
                                         evidence_refs=["evidence://source-current"],
                                         reason="Current explicit source supplied")
    payload["scope_proposals"][0].update(readiness_candidate="READY_CANDIDATE", blockers=[])
    payload["research_stop"] = {"decision": "STOP", "decision_stable": True,
                                "all_material_fronts_accounted": True,
                                "unresolved_decision_changing_questions": []}
    payload["package_readiness_candidate"] = "READY_CANDIDATE"
    return payload


def rejected(payload, code):
    result = V.validate(payload)
    codes = [v["code"] for v in result["errors"]]
    assert result["status"] == "FAIL" and code in codes, result


class AnalysisCandidateContractTests(unittest.TestCase):
    def test_01_blocked_positive(self):
        self.assertEqual(V.validate(blocked())["status"], "PASS")

    def test_02_ready_is_only_candidate_never_admitted(self):
        result = V.validate(ready_candidate())
        self.assertEqual(result["status"], "PASS")
        self.assertIs(result["downstream_authorized"], False)
        self.assertEqual(result["independent_semantic_judge"], "NOT_EXECUTED")
        self.assertEqual(U.evaluate(ready_candidate(), result)["status"], "PASS")
        self.assertIs(U.evaluate(ready_candidate(), result)["downstream_authorized"], False)

    def test_03_false_ready_with_explicit_unknown(self):
        p = blocked()
        p["scope_proposals"][0]["readiness_candidate"] = "READY_CANDIDATE"
        p["package_readiness_candidate"] = "READY_CANDIDATE"
        rejected(p, "ANALYSIS_UNKNOWN_TARGET_STATE_FALSE_READY")
        rejected(p, "ANALYSIS_UNKNOWN_MATERIAL_FALSE_READY")

    def test_04_false_ready_with_blocked_front(self):
        p = ready_candidate()
        p["material_fronts"][0]["closure"] = "BLOCKED"
        p["material_fronts"][0]["blockers"] = ["RISK_UNKNOWN"]
        rejected(p, "ANALYSIS_FALSE_READY_SCOPE")

    def test_05_missing_front_mapping(self):
        p = ready_candidate()
        p["scope_proposals"][0]["material_front_refs"] = []
        rejected(p, "ANALYSIS_SCOPE_FRONT_BIDIRECTIONAL_MISMATCH")

    def test_06_unresolved_stop(self):
        p = blocked()
        p["research_stop"]["decision"] = "STOP"
        rejected(p, "ANALYSIS_STOP_WITH_UNRESOLVED_MATERIAL")

    def test_07_unknown_material_is_never_L1(self):
        p = blocked()
        p["classification"]["depth"] = "L1"
        rejected(p, "ANALYSIS_UNKNOWN_MATERIAL_DEPTH_CANNOT_BE_L1")

    def test_08_missing_evidence_on_closed_front(self):
        p = ready_candidate()
        p["material_fronts"][0]["evidence_refs"] = []
        rejected(p, "ANALYSIS_CLOSED_REQUIRED_FRONT_NEEDS_EVIDENCE")

    def test_09_unverified_reuse(self):
        p = ready_candidate()
        p["material_fronts"][0]["obligation_mode"] = "REUSE_AS_IS"
        p["material_fronts"][0]["evidence_refs"] = []
        rejected(p, "ANALYSIS_REUSE_OR_NA_REQUIRES_CURRENT_EVIDENCE")

    def test_10_duplicate_step(self):
        p = blocked()
        p["stage_trace"][8]["stage"] = "A8"
        rejected(p, "ANALYSIS_A1_A9_SEQUENCE_REQUIRED")

    def test_11_human_decision_false_ready(self):
        p = ready_candidate()
        p["decisions_pending"] = [{"decision_id": "D1", "scope_id": "S1", "question": "Choose material owner"}]
        rejected(p, "ANALYSIS_UNRESOLVED_HUMAN_DECISION_FALSE_READY")

    def test_12_repeated_intent_is_not_utility(self):
        p = ready_candidate()
        p["requirements"][0]["outcome"] = p["request_context"]["intent"]
        g = V.validate(p)
        self.assertEqual(g["status"], "PASS")
        self.assertEqual(U.evaluate(p, g)["status"], "FAIL")

    def test_13_bad_proposed_partial(self):
        p = ready_candidate()
        p["package_readiness_candidate"] = "PARTIAL_READY_CANDIDATE"
        rejected(p, "ANALYSIS_PACKAGE_PARTIAL_NOT_JUSTIFIED")

    def test_14_readiness_unsupported_claim(self):
        p = ready_candidate()
        p["candidate_only"] = False
        rejected(p, "ANALYSIS_CANDIDATE_ONLY_REQUIRED")

    def test_16_closed_front_cannot_retain_blockers(self):
        p = ready_candidate()
        p["material_fronts"][0]["blockers"] = ["RISK_STILL_OPEN"]
        rejected(p, "ANALYSIS_CLOSED_FRONT_HAS_BLOCKERS")

    def test_15_schema_is_canonical(self):
        import jsonschema
        schema = json.loads((ROOT / "schemas/runtime_output.schema.json").read_text())
        jsonschema.Draft202012Validator.check_schema(schema)
        for p in (blocked(), ready_candidate()):
            self.assertEqual(list(jsonschema.Draft202012Validator(schema).iter_errors(p)), [])


    def test_17_missing_business_rejected(self):
        p = blocked()
        del p["request_context"]["business"]
        rejected(p, "ANALYSIS_BUSINESS_CONTEXT_REQUIRED")

    def test_18_noncanonical_business_rejected(self):
        p = blocked()
        p["request_context"]["business"] = "saly"
        rejected(p, "ANALYSIS_BUSINESS_CONTEXT_REQUIRED")


    def test_19_10_1_invalid_pair_must_block(self):
        p = blocked()
        p["classification"]["initial_intent_kind"] = "CREATE"
        rejected(p, "ANALYSIS_10_1_INITIAL_CLASSIFICATION_MISMATCH")

    def test_20_10_1_repair_must_never_be_ready(self):
        p = ready_candidate()
        p["classification"].update(initial_intent_kind="REPAIR", initial_development_class="REPAIR_HANDOFF")
        rejected(p, "ANALYSIS_10_1_UNRESOLVED_OR_REPAIR_FALSE_READY")

    def test_21_10_1_missing_evidence_rejected(self):
        p = blocked()
        p["classification"]["initial_evidence_refs"] = []
        rejected(p, "ANALYSIS_10_1_INTENT_EVIDENCE_MISSING")

    def test_22_10_1_new_with_existing_definitions_and_unknown_code(self):
        p = blocked()
        p["classification"].update(initial_intent_kind="CREATE", initial_development_class="NEW_CANDIDATE",
                                  authority_state="EXISTING", implementation_state="UNKNOWN")
        self.assertEqual(V.validate(p)["status"], "PASS")


    def test_23_10_2_business_mismatch(self):
        p = blocked()
        p["definition_source_reception"]["business"] = "SALY"
        rejected(p, "ANALYSIS_10_2_BUSINESS_MISMATCH")

    def test_24_10_2_no_false_currentness(self):
        p = blocked()
        p["definition_source_reception"]["source_currentness"] = "CURRENT"
        rejected(p, "ANALYSIS_10_2_UNVERIFIED_AUTHORITY_OVERCLAIM")

    def test_25_10_2_sources_need_refs(self):
        p = blocked()
        p["definition_source_reception"]["status"] = "FOUND_UNATTESTED"
        rejected(p, "ANALYSIS_10_2_SOURCE_REFS_MISSING")

    def test_26_10_2_unresolved_no_fake_refs(self):
        p = blocked()
        p["definition_source_reception"]["source_refs"] = ["source://invented"]
        rejected(p, "ANALYSIS_10_2_UNRESOLVED_SOURCE_FALSE_RECEIVED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
