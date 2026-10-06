from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

from story_independent_assurance_adapter_v1 import (
    canonical_package_sha256,
    consume_story_independent_review,
    prepare_story_independent_review,
)

ROOT = Path(__file__).resolve().parent
PACKAGE = json.loads((ROOT / "fixtures/onb_004_implementation_package_v1_1.json").read_text(encoding="utf-8"))
SOURCE_HEAD = "85bb733e73b9d21222f4e86b618ef1a099208051"
CAPABILITY = {
    "capability_code": "INDEPENDENT_ASSURANCE",
    "status": "ACTIVE",
    "version": "1.0.1",
    "manifest_sha256": "b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1",
}


def _prepared():
    result = prepare_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
    )
    assert result["result"] == "REVIEW_REQUIRED", result
    return result


def _receipt():
    prepared = _prepared()
    return {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "receipt_sha256": "1" * 64,
        "capability_code": "INDEPENDENT_ASSURANCE",
        "receipt_kind": "AUDIT_VERDICT",
        "subject_type": prepared["subject_type"],
        "subject_ref": prepared["subject_ref"],
        "subject_sha256": prepared["subject_sha256"],
        "source_head_sha": SOURCE_HEAD,
        "authority_ref": prepared["authority_ref"],
        "verification_state": "VERIFIED",
        "receipt_payload": {
            "capability_version": CAPABILITY["version"],
            "capability_manifest_sha256": CAPABILITY["manifest_sha256"],
            "producer_identity": "STORY_CREATOR",
            "reviewer_identity": "INDEPENDENT_REVIEWER_A",
            "independent": True,
            "independence_measure": {"state": "INDEPENDENT"},
            "verdict": "PASS",
            "review_dimensions": {
                "implementation_actionability": "PASS",
                "source_fidelity": "PASS",
                "reuse_correctness": "PASS",
                "context_sufficiency": "PASS",
                "acceptance_executability": "PASS",
            },
            "evidence_refs": ["provider-bound://evidence/1"],
        },
    }


def test_prepare_uses_current_capability_without_hardcoded_v2():
    prepared = _prepared()
    assert prepared["capability_version"] == "1.0.1"
    assert prepared["subject_type"] == "STORY_IMPLEMENTATION_PACKAGE"
    assert prepared["subject_sha256"] == canonical_package_sha256(PACKAGE)


def test_missing_receipt_fails_closed():
    result = consume_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=None,
    )
    assert result == {"result": "BLOCKED", "code": "INDEPENDENT_REVIEW_RECEIPT_REQUIRED"}


def test_exact_verified_independent_receipt_passes():
    result = consume_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=_receipt(),
    )
    assert result["result"] == "PASS", result
    assert result["verification_state"] == "VERIFIED"


def test_self_review_fails_closed():
    receipt = _receipt()
    receipt["receipt_payload"]["reviewer_identity"] = "STORY_CREATOR"
    result = consume_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=receipt,
    )
    assert result["code"] == "INDEPENDENT_REVIEW_INDEPENDENCE_INVALID"


def test_receipt_from_previous_capability_current_fails_closed():
    receipt = _receipt()
    receipt["receipt_payload"]["capability_manifest_sha256"] = "2" * 64
    result = consume_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=receipt,
    )
    assert result["code"] == "INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID"


def test_package_mutation_changes_subject_and_rejects_old_receipt():
    receipt = _receipt()
    mutated = deepcopy(PACKAGE)
    mutated["outcome"]["target"] = "MUTATED"
    assert canonical_package_sha256(mutated) != canonical_package_sha256(PACKAGE)
    result = consume_story_independent_review(
        mutated,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=receipt,
    )
    assert result["code"] == "INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID"


def test_incomplete_review_dimension_fails_closed():
    receipt = _receipt()
    receipt["receipt_payload"]["review_dimensions"]["source_fidelity"] = "FAIL"
    result = consume_story_independent_review(
        PACKAGE,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
        ledger_receipt=receipt,
    )
    assert result["code"] == "INDEPENDENT_REVIEW_CONTENT_INVALID"


def test_noncurrent_story_authority_fails_before_review():
    mutated = deepcopy(PACKAGE)
    mutated["decision_closure"]["source_currentness_state"] = "STALE"
    result = prepare_story_independent_review(
        mutated,
        source_head_sha=SOURCE_HEAD,
        capability_current=CAPABILITY,
    )
    assert result["code"] == "STORY_IMPLEMENTATION_PACKAGE_AUTHORITY_NOT_CURRENT"


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"PASS story independent assurance adapter: {len(tests)}/{len(tests)}")
