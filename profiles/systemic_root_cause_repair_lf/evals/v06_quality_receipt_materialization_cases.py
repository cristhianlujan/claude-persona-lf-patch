#!/usr/bin/env python3
"""V0.6 canonical quality receipt materialization and independence cases."""
import copy
import importlib.util
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
base = runpy.run_path(str(ROOT / "evals" / "v03_quality_receipt_cases.py"))
fixture_globals = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
valid_pair = fixture_globals["valid_pair"]
closure = fixture_globals["closure_proof"]

spec = importlib.util.spec_from_file_location(
    "srcr_quality_materializer",
    ROOT / "validators" / "materialize_quality_receipt.py",
)
materializer = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(materializer)

qspec = importlib.util.spec_from_file_location(
    "srcr_quality_validator_v06",
    ROOT / "validators" / "validate_quality_receipt.py",
)
quality = importlib.util.module_from_spec(qspec)
assert qspec and qspec.loader
qspec.loader.exec_module(quality)

schema = json.loads((ROOT / "schemas" / "quality_receipt.schema.json").read_text())
schema_validator = Draft202012Validator(schema)

candidate, evidence = valid_pair()
candidate = copy.deepcopy(candidate)
candidate["profile_pack_id"] = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
semantic = base["make_semantic"](candidate)
semantic["evidence_manifest_sha256"] = materializer._canonical_json_sha256(evidence)
review_input_sha256 = "c" * 64
semantic["reviewer_execution_id"] = "EXEC-REVIEW-001"
semantic["review_input_sha256"] = review_input_sha256
semantic["reviewer_context_mode"] = "ISOLATED_NO_PRODUCER_PRIVATE_CONTEXT"
semantic["review_input_classes"] = [
    "CURRENT_AUTHORITY_REFS",
    "EVIDENCE_MANIFEST",
    "EXACT_CANDIDATE",
    "SCOPE_AUTHORITY_PACKET",
]

receipt = materializer.materialize_quality_receipt(
    candidate,
    evidence,
    semantic,
    candidate_revision="candidate-revision-v06-001",
    semantic_execution_receipt_ref="supabase://semantic-review/EXEC-REVIEW-001",
    issued_at="2026-09-22T05:10:00Z",
    producer_execution_id="EXEC-PRODUCER-001",
    reviewer_execution_id="EXEC-REVIEW-001",
    producer_execution_receipt_ref="supabase://producer/EXEC-PRODUCER-001",
    review_input_sha256=review_input_sha256,
)

errors = list(schema_validator.iter_errors(receipt))
assert not errors, [e.message for e in errors[:5]]
validated = quality.validate_quality_receipt(receipt, candidate, evidence, semantic)
assert validated["status"] == "PASS", validated
assert validated["canonical_quality_accepted"] is True, validated
assert receipt["review_boundary"]["producer_execution_id"] != receipt["review_boundary"]["reviewer_execution_id"]
assert set(receipt["review_boundary"]["independence_evidence_refs"]) == {
    receipt["review_boundary"]["producer_execution_receipt_ref"],
    receipt["review_boundary"]["semantic_execution_receipt_ref"],
}

try:
    materializer.materialize_quality_receipt(
        candidate,
        evidence,
        semantic,
        candidate_revision="candidate-revision-v06-002",
        semantic_execution_receipt_ref="supabase://semantic-review/EXEC-SAME",
        issued_at="2026-09-22T05:10:00Z",
        producer_execution_id="EXEC-SAME",
        reviewer_execution_id="EXEC-SAME",
        producer_execution_receipt_ref="supabase://producer/EXEC-SAME",
        review_input_sha256=review_input_sha256,
    )
except materializer.QualityReceiptMaterializationError as exc:
    assert "REVIEWER_EXECUTION_MUST_DIFFER_FROM_PRODUCER" in str(exc)
else:
    raise AssertionError("same producer/reviewer execution must fail")

bad = copy.deepcopy(receipt)
bad["review_boundary"]["reviewer_execution_id"] = bad["review_boundary"]["producer_execution_id"]
blocked = quality.validate_quality_receipt(bad, candidate, evidence, semantic)
assert "SRCR_V06_REVIEW_EXECUTION_NOT_INDEPENDENT" in blocked["blocking_codes"], blocked

bad = copy.deepcopy(receipt)
bad["review_boundary"]["independence_evidence_refs"] = [
    bad["review_boundary"]["semantic_execution_receipt_ref"],
    "supabase://other/not-producer",
]
blocked = quality.validate_quality_receipt(bad, candidate, evidence, semantic)
assert "SRCR_V06_INDEPENDENCE_EVIDENCE_REFS_INCOMPLETE" in blocked["blocking_codes"], blocked

bad = copy.deepcopy(receipt)
bad["review_boundary"]["reviewer_context_mode"] = "PRODUCER_CONTEXT_REUSED"
blocked = quality.validate_quality_receipt(bad, candidate, evidence, semantic)
assert "SRCR_V06_REVIEWER_CONTEXT_NOT_ISOLATED" in blocked["blocking_codes"], blocked

bad = copy.deepcopy(receipt)
bad["review_boundary"]["review_input_classes"] = [
    "EXACT_CANDIDATE",
    "EVIDENCE_MANIFEST",
    "SCOPE_AUTHORITY_PACKET",
    "PRODUCER_PRIVATE_REASONING",
]
blocked = quality.validate_quality_receipt(bad, candidate, evidence, semantic)
assert "SRCR_V06_REVIEW_INPUT_CLASS_BOUNDARY_INVALID" in blocked["blocking_codes"], blocked

semantic_bad = copy.deepcopy(semantic)
semantic_bad["reviewer_execution_id"] = "EXEC-REVIEW-OTHER"
blocked = quality.validate_quality_receipt(receipt, candidate, evidence, semantic_bad)
assert "SRCR_V06_SEMANTIC_REVIEWER_EXECUTION_ID_MISMATCH" in blocked["blocking_codes"], blocked

semantic_bad = copy.deepcopy(semantic)
semantic_bad["review_input_sha256"] = "d" * 64
blocked = quality.validate_quality_receipt(receipt, candidate, evidence, semantic_bad)
assert "SRCR_V06_SEMANTIC_REVIEW_INPUT_SHA_MISMATCH" in blocked["blocking_codes"], blocked

candidate_bad = copy.deepcopy(candidate)
candidate_bad["symptom"]["statement"] += " post-review mutation"
blocked = quality.validate_quality_receipt(receipt, candidate_bad, evidence, semantic)
assert "SRCR_QUALITY_CANDIDATE_DIGEST_MISMATCH" in blocked["blocking_codes"], blocked

print("SRCR_V06_QUALITY_RECEIPT_MATERIALIZATION=9/9")
