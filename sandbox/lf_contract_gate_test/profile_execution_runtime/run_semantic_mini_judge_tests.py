#!/usr/bin/env python3
"""Offline regression suite for semantic mini-judge contracts. No model call."""

from __future__ import annotations

from copy import deepcopy

from semantic_mini_judge import (
    CheckResult,
    MiniJudgeInputError,
    aggregate_verdict,
    build_receipt,
    parse_model_response,
    partition_checks,
    validate_bundle,
)
from semantic_obligation_manifest import (
    ObligationManifestError,
    build_check_bundle,
    canonical_json_sha256,
    validate_obligation_manifest,
)

EXECUTION_ID = "EXEC-TEST-001"
PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SHA = "c" * 64
INPUT_SHA = "a" * 64


def manifest(obligations):
    ids = [item["obligation_id"] for item in obligations]
    return {
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": EXECUTION_ID,
        "profile_code": PROFILE_CODE,
        "profile_source_sha256": PROFILE_SHA,
        "input_sha256": INPUT_SHA,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profiles/ui_architect/SKILL.md",
                "source_sha256": PROFILE_SHA,
                "required_obligation_ids": ids,
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": "input:/literal",
                "source_sha256": INPUT_SHA,
                "required_obligation_ids": [],
            },
        ],
        "obligations": obligations,
    }


def derive(obligations, raw):
    m = validate_obligation_manifest(manifest(obligations))
    return m, validate_bundle(build_check_bundle(m, raw, raw_output_sha256=canonical_json_sha256(raw)))


def main() -> int:
    passed = 0

    m, b = derive([{
        "obligation_id": "D1", "check_type": "REQUIRED_SUBSTRING",
        "rule": "must preserve token", "evidence_pointer": "/text",
        "authority_ids": ["PROFILE-CONTRACT"], "expected": ["space_24"],
    }], {"text": "padding uses space_24"})
    deterministic, semantic = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES" and not semantic
    assert b["obligation_manifest_sha256"] == canonical_json_sha256(m)
    passed += 1

    _, b = derive([{
        "obligation_id": "D2", "check_type": "REQUIRED_SUBSTRING",
        "rule": "must preserve token", "evidence_pointer": "/text",
        "authority_ids": ["PROFILE-CONTRACT"], "expected": ["space_24"],
    }], {"text": "add more spacing"})
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "CONTRADICTS"
    passed += 1

    _, b = derive([{
        "obligation_id": "D3", "check_type": "FORBIDDEN_SUBSTRING",
        "rule": "no invented card suffix", "evidence_pointer": "/text",
        "authority_ids": ["PROFILE-CONTRACT"], "forbidden": ["4242"],
    }], {"text": "Use Visa card"})
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES"
    passed += 1

    _, b = derive([{
        "obligation_id": "D4", "check_type": "FORBIDDEN_SUBSTRING",
        "rule": "no invented card suffix", "evidence_pointer": "/text",
        "authority_ids": ["PROFILE-CONTRACT"], "forbidden": ["4242"],
    }], {"text": "Visa ending in 4242"})
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "CONTRADICTS"
    passed += 1

    _, b = derive([{
        "obligation_id": "D5", "check_type": "EXACT_VALUE",
        "rule": "preserve canonical spacing", "evidence_pointer": "/value",
        "authority_ids": ["PROFILE-CONTRACT"], "expected_value": "space_24",
    }], {"value": "space_24"})
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES"
    passed += 1

    _, b = derive([{
        "obligation_id": "S1", "check_type": "SEMANTIC_RELATION",
        "rule": "Remove the duplicated presentation.", "evidence_pointer": "/action",
        "authority_ids": ["PROFILE-CONTRACT"],
    }], {"action": "Duplicate it again in the upper strip."})
    deterministic, semantic = partition_checks(b)
    assert not deterministic and semantic[0]["check_id"] == "S1"
    passed += 1

    parsed = parse_model_response('{"verdict":"CONTRADICTS","reason_code":"REVERSES_RULE"}', check_id="S1")
    assert parsed.verdict == "CONTRADICTS"
    passed += 1

    parsed = parse_model_response('not-json', check_id="S2")
    assert parsed.verdict == "UNCERTAIN" and parsed.reason_code == "MODEL_OUTPUT_NOT_JSON"
    passed += 1

    verdict, downstream = aggregate_verdict([
        CheckResult("A", "COMPLIES", "OK", "PYTHON_DETERMINISTIC"),
        CheckResult("B", "UNCERTAIN", "UNKNOWN", "LOCAL_SEMANTIC_MODEL"),
    ])
    assert verdict == "UNCERTAIN" and downstream == "BLOCK"
    passed += 1

    m, b = derive([{
        "obligation_id": "D6", "check_type": "EXACT_VALUE",
        "rule": "preserve upstream behavior", "evidence_pointer": "/state",
        "authority_ids": ["PROFILE-CONTRACT"], "expected_value": "CTA_ACTIVE_ERROR_ON_CLICK",
    }], {"state": "CTA_ACTIVE_ERROR_ON_CLICK"})
    receipt = build_receipt(b, [CheckResult("D6", "COMPLIES", "EXACT_VALUE_MATCH", "PYTHON_DETERMINISTIC")])
    assert receipt["verdict"] == "PASS"
    assert receipt["downstream_disposition"] == "ELIGIBLE"
    assert receipt["obligation_manifest_sha256"] == canonical_json_sha256(m)
    assert receipt["self_authorizes_downstream"] is False
    passed += 1

    two = manifest([{
        "obligation_id": "A1", "check_type": "REQUIRED_SUBSTRING",
        "rule": "first", "evidence_pointer": "/a",
        "authority_ids": ["PROFILE-CONTRACT"], "expected": ["ok-a"],
    }, {
        "obligation_id": "A2", "check_type": "REQUIRED_SUBSTRING",
        "rule": "second", "evidence_pointer": "/b",
        "authority_ids": ["PROFILE-CONTRACT"], "expected": ["ok-b"],
    }])
    normalized = validate_obligation_manifest(two)
    derived = build_check_bundle(normalized, {"a": "ok-a", "b": "ok-b"}, raw_output_sha256=canonical_json_sha256({"a": "ok-a", "b": "ok-b"}))
    assert [x["check_id"] for x in derived["checks"]] == ["A1", "A2"]
    passed += 1

    incomplete = deepcopy(two)
    incomplete["obligations"].pop()
    try:
        validate_obligation_manifest(incomplete)
    except ObligationManifestError as exc:
        assert str(exc) == "REQUIRED_OBLIGATION_SET_MISMATCH"
    else:
        raise AssertionError("enumerated authority obligation omission must fail")
    passed += 1

    bad_authority = deepcopy(two)
    bad_authority["authority_sources"][0]["required_obligation_ids"] = ["A1"]
    try:
        validate_obligation_manifest(bad_authority)
    except ObligationManifestError as exc:
        assert str(exc) in {"OBLIGATION_A2_AUTHORITY_COVERAGE_MISMATCH", "REQUIRED_OBLIGATION_SET_MISMATCH"}
    else:
        raise AssertionError("authority coverage omission must fail")
    passed += 1

    missing_pointer = manifest([{
        "obligation_id": "P1", "check_type": "REQUIRED_SUBSTRING",
        "rule": "pointer must resolve", "evidence_pointer": "/missing",
        "authority_ids": ["PROFILE-CONTRACT"], "expected": ["x"],
    }])
    try:
        build_check_bundle(validate_obligation_manifest(missing_pointer), {"other": "x"}, raw_output_sha256=canonical_json_sha256({"other": "x"}))
    except ObligationManifestError as exc:
        assert str(exc).startswith("EVIDENCE_POINTER_NOT_FOUND")
    else:
        raise AssertionError("missing evidence pointer must fail")
    passed += 1

    manual = deepcopy(derived)
    manual["checks"] = manual["checks"][:1]
    try:
        validate_bundle(manual)
    except MiniJudgeInputError:
        raise AssertionError("bundle shape alone may be valid; completeness belongs to manifest gate")
    assert len(manual["checks"]) == 1 and len(derived["checks"]) == 2
    passed += 1

    if passed != 15:
        raise SystemExit(f"SEMANTIC_MINI_JUDGE_TESTS_FAIL {passed}/15")
    print("SEMANTIC_MINI_JUDGE_TESTS_PASS 15/15")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
