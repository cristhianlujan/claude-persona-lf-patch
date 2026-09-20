#!/usr/bin/env python3
import copy
import importlib.util
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

fixture_globals = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
valid_pair = fixture_globals["valid_pair"]

spec = importlib.util.spec_from_file_location("srcr_quality_receipt", VALIDATORS / "validate_quality_receipt.py")
quality = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(quality)

schema = json.loads((ROOT / "schemas" / "quality_receipt.schema.json").read_text())
schema_validator = Draft7Validator(schema)

INVARIANTS = [
    "SCOPE_AUTHORITY_INTEGRITY",
    "EVIDENCE_INTEGRITY",
    "CAUSAL_CLOSURE",
    "CONTRADICTION_INTEGRITY",
    "MINIMUM_SUFFICIENT_REUSE",
    "INDEPENDENT_DECISION_CLOSURE",
    "FALSIFIABILITY_REGRESSION",
]


def make_semantic(candidate):
    candidate_sha = fixture_globals["closure_proof"].canonical_candidate_digest(candidate).split(":", 1)[1]
    return {
        "verdict": "PASS_INDEPENDENT_SEMANTIC",
        "candidate_sha256": candidate_sha,
        "scope_packet_sha256": "a" * 64,
        "source_refs_inspected": ["fixture://quality-receipt/source"],
        "observed_candidate_changes": [],
        "requirement_reconciliation": [],
        "change_declaration_reconciliation": [],
        "scope_conformance_reconciliation": [],
        "invariant_results": [
            {"invariant": name, "result": "PASS", "evidence_refs": ["fixture://quality-receipt/evidence"], "reason": "Fixture proves exact bounded condition."}
            for name in INVARIANTS
        ],
        "open_design_decisions_found": [],
        "unsupported_claims": [],
        "blocking_codes": [],
        "repair_instructions": [],
        "next_gate": "QUALITY_RECEIPT",
    }


def make_receipt(candidate, evidence, semantic):
    summary_errors, summary = fixture_globals["closure_proof"].validate_v03_closure(candidate, evidence)
    assert not summary_errors, summary_errors
    return {
        "receipt_version": "SRCR_QUALITY_RECEIPT_V1",
        "profile_pack_id": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3",
        "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "decision": "PASS_TO_QUALITY_PACK",
        "review_boundary": {
            "issuer": "CANONICAL_SRCR_MINI_JUDGE",
            "execution_mode": "INDEPENDENT_SEMANTIC_REVIEW",
            "reviewer_is_producer": False,
            "producer_context_available": False,
            "semantic_execution_receipt_ref": "fixture://independent-semantic-execution/001",
        },
        "candidate_binding": {
            "candidate_revision": "quality-boundary-candidate-rev-1",
            "candidate_digest": fixture_globals["closure_proof"].canonical_candidate_digest(candidate),
        },
        "evidence_binding": {
            "bundle_id": evidence["bundle_id"],
            "bundle_digest": evidence["bundle_digest"],
        },
        "semantic_binding": {
            "semantic_result_digest": quality.canonical_semantic_result_digest(semantic),
            "semantic_verdict": semantic["verdict"],
            "candidate_sha256": semantic["candidate_sha256"],
            "scope_packet_sha256": semantic["scope_packet_sha256"],
        },
        "proof_binding": {
            "required_obligation_ids": summary["required_obligation_ids"],
            "closed_obligation_ids": summary["closed_obligation_ids"],
            "open_obligation_ids": summary["open_obligation_ids"],
        },
        "blocking_codes": [],
        "issued_at": "2026-09-20T04:45:00Z",
    }


def assert_valid(receipt, candidate, evidence, semantic, label):
    schema_errors = list(schema_validator.iter_errors(receipt))
    assert not schema_errors, (label, [e.message for e in schema_errors[:5]])
    result = quality.validate_quality_receipt(receipt, candidate, evidence, semantic)
    assert result["status"] == "PASS", (label, result)
    assert result["canonical_quality_accepted"] is True, (label, result)


def assert_blocked(receipt, candidate, evidence, semantic, expected_code, label):
    result = quality.validate_quality_receipt(receipt, candidate, evidence, semantic)
    assert result["status"] == "FAIL", (label, result)
    assert result["canonical_quality_accepted"] is False, (label, result)
    assert expected_code in result["blocking_codes"], (label, expected_code, result["blocking_codes"])


candidate, evidence = valid_pair()
semantic = make_semantic(candidate)
receipt = make_receipt(candidate, evidence, semantic)
assert_valid(receipt, candidate, evidence, semantic, "valid_exact_binding")

c2 = copy.deepcopy(candidate)
c2["symptom"]["statement"] += " mutation"
assert_blocked(receipt, c2, evidence, semantic, "SRCR_QUALITY_CANDIDATE_DIGEST_MISMATCH", "candidate_mutation")

e2 = copy.deepcopy(evidence)
e2["evidence"][0]["digest"] = "sha256:mutated-evidence"
assert_blocked(receipt, candidate, e2, semantic, "SRCR_QUALITY_EVIDENCE_BUNDLE_DIGEST_MISMATCH", "evidence_mutation")

s2 = copy.deepcopy(semantic)
s2["next_gate"] = "CHANGED_AFTER_RECEIPT"
assert_blocked(receipt, candidate, evidence, s2, "SRCR_QUALITY_SEMANTIC_RESULT_DIGEST_MISMATCH", "semantic_mutation")

c3 = copy.deepcopy(candidate)
c3["quality_receipt"] = copy.deepcopy(receipt)
assert_blocked(receipt, c3, evidence, semantic, "SRCR_CANDIDATE_SELF_ISSUED_QUALITY_RECEIPT", "candidate_self_issue")

r2 = copy.deepcopy(receipt)
r2["proof_binding"]["closed_obligation_ids"] = []
assert_blocked(r2, candidate, evidence, semantic, "SRCR_QUALITY_CLOSED_PROOF_SET_MISMATCH", "proof_set_mismatch")

r3 = copy.deepcopy(receipt)
r3["review_boundary"]["reviewer_is_producer"] = True
assert_blocked(r3, candidate, evidence, semantic, "SRCR_QUALITY_REVIEWER_NOT_INDEPENDENT", "producer_review")

s3 = copy.deepcopy(semantic)
s3["candidate_sha256"] = "b" * 64
r4 = copy.deepcopy(receipt)
r4["semantic_binding"]["semantic_result_digest"] = quality.canonical_semantic_result_digest(s3)
r4["semantic_binding"]["candidate_sha256"] = "b" * 64
assert_blocked(r4, candidate, evidence, s3, "SRCR_SEMANTIC_RESULT_CANDIDATE_SHA_MISMATCH", "semantic_candidate_mismatch")

s4 = copy.deepcopy(semantic)
s4["verdict"] = "RETURN_TO_WORKER_FOR_SELF_REPAIR"
s4["blocking_codes"] = ["SEMANTIC_REPAIR_REQUIRED"]
r5 = copy.deepcopy(receipt)
r5["semantic_binding"]["semantic_result_digest"] = quality.canonical_semantic_result_digest(s4)
r5["semantic_binding"]["semantic_verdict"] = s4["verdict"]
r5["blocking_codes"] = s4["blocking_codes"]
assert_blocked(r5, candidate, evidence, s4, "SRCR_QUALITY_DECISION_SEMANTIC_MISMATCH", "pass_over_nonpass_semantic")

v02 = json.loads((ROOT / "examples" / "good_output.json").read_text())
assert_blocked(receipt, v02, evidence, semantic, "SRCR_QUALITY_RECEIPT_REQUIRES_V03", "v02_not_eligible")

r6 = copy.deepcopy(receipt)
r6["semantic_binding"]["semantic_result_digest"] = "sha256:" + ("0" * 64)
assert_blocked(r6, candidate, evidence, semantic, "SRCR_QUALITY_SEMANTIC_RESULT_DIGEST_MISMATCH", "semantic_digest_tamper")

r7 = copy.deepcopy(receipt)
r7["evidence_binding"]["bundle_digest"] = "sha256:" + ("0" * 64)
assert_blocked(r7, candidate, evidence, semantic, "SRCR_QUALITY_EVIDENCE_BUNDLE_DIGEST_MISMATCH", "evidence_digest_tamper")

print("PASS_SRCR_V03_QUALITY_RECEIPT=12/12")
