from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates


@pytest.fixture
def quality(tmp_path):
    profile = tmp_path / "profiles/p"
    files = {
        "judges/main.md": "# Judge",
        "judges/semantic.md": "# Independent review",
        "schemas/output.json": json.dumps({
            "type": "object", "required": ["profile_pack_id", "answer"],
            "properties": {"profile_pack_id": {"const": "PACK"}, "answer": {"type": "string"}},
        }),
        "schemas/receipt.json": '{"type":"object"}',
        "validators/contract.py": 'def validate(payload, **kwargs):\n    return ["CONTRACT_FAILED"] if payload.get("answer") == "bad" else []\n',
        "validators/utility.py": 'def evaluate(payload, contract_gate, **kwargs):\n    return {"status":"FAIL","blocking_codes":["UTILITY_FAILED"]} if payload.get("answer") == "shallow" else {"status":"PASS","blocking_codes":[]}\n',
        "validators/semantic.py": 'def evaluate(payload, **kwargs):\n    return payload["validator_result"]\n',
        "validators/receipt.py": 'def validate(receipt, *args):\n    return receipt["validator_result"]\n',
        "validators/materializer.py": 'def materialize(*args, **kwargs):\n    return {"validator_result":{"status":"PASS","blocking_codes":[],"canonical_quality_accepted":True}}\n',
    }
    config = {
        "schema": "LF_PROFILE_RUNTIME_BINDING_V1", "profile_slug": "p", "profile_code": "PERFIL-P",
        "runtime_schema": {"default": "schemas/output.json", "output_modes": {}},
        "canonical_validator": {"path": "validators/contract.py", "callable": "validate"},
        "semantic_utility": {"path": "validators/utility.py", "callable": "evaluate"},
        "governance": {"source_first_required": True, "schema_invention_allowed": False, "fail_closed": True,
                       "exact_head_evidence_required": True, "post_update_baseline_required": True},
        "canonical_quality": {
            "required_for_profile_pack_ids": ["PACK"],
            "judge_path": "judges/main.md", "semantic_judge_path": "judges/semantic.md",
            "semantic_result_validator": {"path": "validators/semantic.py", "callable": "evaluate"},
            "quality_receipt_schema": "schemas/receipt.json",
            "quality_receipt_validator": {"path": "validators/receipt.py", "callable": "validate"},
            "quality_receipt_materializer": {"path": "validators/materializer.py", "callable": "materialize"},
            "deterministic_floors_can_accept_quality": False, "receipt_required_for_pass_to_quality_pack": True,
        },
    }
    files["contracts/runtime_binding.json"] = json.dumps(config)
    for name, text in files.items():
        path = profile / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return OutputGates(RepositoryBindings(tmp_path, max_prompt_chars=10000))


@pytest.mark.parametrize("component", ["semantic", "receipt"])
@pytest.mark.parametrize("bad_result", [
    {"status": "FAIL", "blocking_codes": []},
    {"status": "BLOCKED"},
    {"status": "PASS", "blocking_codes": ["UNRESOLVED"]},
    {"status": "PASS", "blocking_codes": "INVALID_SHAPE"},
])
def test_nonclean_validator_can_never_accept_quality(quality, component, bad_result):
    semantic = {"status": "PASS", "blocking_codes": []}
    receipt = {"status": "PASS", "blocking_codes": [], "canonical_quality_accepted": True}
    if component == "semantic":
        semantic = bad_result
    else:
        receipt = dict(bad_result, canonical_quality_accepted=True)
    result = quality.canonical_quality(
        profile_slug="p", candidate={"profile_pack_id": "PACK", "answer": "good"},
        evidence_manifest={}, semantic_result={"validator_result": semantic},
        quality_receipt={"validator_result": receipt},
    )
    assert result["status"] == "FAIL"
    assert result["blocking_codes"]
    assert result["canonical_quality_accepted"] is False


def test_quality_acceptance_must_be_explicit(quality):
    result = quality.canonical_quality(
        profile_slug="p", candidate={"profile_pack_id": "PACK", "answer": "good"},
        evidence_manifest={}, semantic_result={"validator_result": {"status": "PASS", "blocking_codes": []}},
        quality_receipt={"validator_result": {"status": "PASS", "blocking_codes": []}},
    )
    assert result["canonical_quality_accepted"] is False


@pytest.mark.parametrize("validator_result", [
    {"status": "FAIL", "errors": [], "blocking_codes": []},
    {"valid": False, "errors": []},
    {"status": "PASS", "errors": [], "blocking_codes": ["FAILED_FLOOR"]},
    {"status": "PASS", "errors": [], "blocking_codes": "INVALID_SHAPE"},
])
def test_candidate_contract_cannot_erase_explicit_failure(quality, validator_result):
    validator = SimpleNamespace(validate=lambda *_args, **_kwargs: validator_result)
    with patch.object(quality.repository, "load_validator", return_value=validator):
        result, _ = quality.contract(
            profile_slug="p", raw_output='{"profile_pack_id":"PACK","answer":"good"}',
            schema=quality.repository.runtime_schema("p"),
        )
    assert result["status"] == "FAIL"
    assert result["blocking_codes"]


@pytest.mark.parametrize("candidate,expected", [
    ({"profile_pack_id": "PACK"}, "JSON_SCHEMA_VALIDATION_FAILED"),
    ({"profile_pack_id": "PACK", "answer": "bad"}, "CONTRACT_FAILED"),
    ({"profile_pack_id": "PACK", "answer": "shallow"}, "UTILITY_FAILED"),
])
def test_finalization_cannot_bypass_candidate_floors(quality, candidate, expected):
    result = quality.canonical_quality_finalize(
        profile_slug="p", candidate=candidate, evidence_manifest={}, scope_authority_packet={},
        semantic_result={"validator_result": {"status": "PASS", "blocking_codes": []}},
        candidate_revision="candidate-1", semantic_execution_receipt_ref="review://1",
        producer_execution_id="producer-1", reviewer_execution_id="reviewer-1",
        producer_execution_receipt_ref="producer://1", issued_at="2026-09-22T06:00:00Z",
    )
    assert result["status"] == "FAIL"
    assert result["canonical_quality_accepted"] is False
    assert result["quality_receipt"] is None
    assert expected in result["blocking_codes"]


def test_clean_finalization_keeps_acceptance_separate_from_authorization(quality):
    result = quality.canonical_quality_finalize(
        profile_slug="p", candidate={"profile_pack_id": "PACK", "answer": "good"},
        evidence_manifest={}, scope_authority_packet={},
        semantic_result={"validator_result": {"status": "PASS", "blocking_codes": []}},
        candidate_revision="candidate-1", semantic_execution_receipt_ref="review://1",
        producer_execution_id="producer-1", reviewer_execution_id="reviewer-1",
        producer_execution_receipt_ref="producer://1", issued_at="2026-09-22T06:00:00Z",
    )
    assert result["status"] == "PASS"
    assert result["canonical_quality_accepted"] is True
    assert result["quality_receipt"] is not None
    assert result["profile_contract_valid"]["status"] == "PASS"
    assert result["semantic_utility"]["status"] == "PASS"
    assert result["review_input_binding"]["reviewer_context_mode"] == "ISOLATED_NO_PRODUCER_PRIVATE_CONTEXT"
    assert set(result["review_input_binding"]["review_input_classes"]) == {
        "CURRENT_AUTHORITY_REFS",
        "EVIDENCE_MANIFEST",
        "EXACT_CANDIDATE",
        "SCOPE_AUTHORITY_PACKET",
    }
    assert "PRODUCER_PRIVATE_REASONING" in result["review_input_binding"]["forbidden_input_classes"]
    assert result["expected_review_input_sha256"] == result["review_input_binding"]["review_input_sha256"]
    assert result["downstream_authorized"] is False
