#!/usr/bin/env python3
"""Offline regression suite for semantic mini-judge contracts. No model call."""

from __future__ import annotations

from semantic_mini_judge import (
    CheckResult,
    MiniJudgeInputError,
    aggregate_verdict,
    build_receipt,
    parse_model_response,
    partition_checks,
    validate_bundle,
)


def bundle(checks):
    return {
        "schema": "PROFILE_SEMANTIC_CHECK_BUNDLE_V1",
        "execution_id": "EXEC-TEST-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "input_sha256": "a" * 64,
        "raw_output_sha256": "b" * 64,
        "checks": checks,
    }


def main() -> int:
    passed = 0

    b = validate_bundle(bundle([{
        "check_id": "D1", "check_type": "REQUIRED_SUBSTRING",
        "rule": "must preserve token", "evidence": "padding uses space_24",
        "expected": ["space_24"],
    }]))
    deterministic, semantic = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES" and not semantic
    passed += 1

    b = validate_bundle(bundle([{
        "check_id": "D2", "check_type": "REQUIRED_SUBSTRING",
        "rule": "must preserve token", "evidence": "add more spacing",
        "expected": ["space_24"],
    }]))
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "CONTRADICTS"
    passed += 1

    b = validate_bundle(bundle([{
        "check_id": "D3", "check_type": "FORBIDDEN_SUBSTRING",
        "rule": "no invented card suffix", "evidence": "Use Visa card",
        "forbidden": ["4242"],
    }]))
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES"
    passed += 1

    b = validate_bundle(bundle([{
        "check_id": "D4", "check_type": "FORBIDDEN_SUBSTRING",
        "rule": "no invented card suffix", "evidence": "Visa ending in 4242",
        "forbidden": ["4242"],
    }]))
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "CONTRADICTS"
    passed += 1

    b = validate_bundle(bundle([{
        "check_id": "D5", "check_type": "EXACT_VALUE",
        "rule": "preserve canonical spacing", "evidence": "space_24",
        "expected_value": "space_24", "observed_value": "space_24",
    }]))
    deterministic, _ = partition_checks(b)
    assert deterministic[0].verdict == "COMPLIES"
    passed += 1

    b = validate_bundle(bundle([{
        "check_id": "S1", "check_type": "SEMANTIC_RELATION",
        "rule": "Remove the duplicated presentation.",
        "evidence": "Duplicate it again in the upper strip.",
    }]))
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

    b = validate_bundle(bundle([{
        "check_id": "D6", "check_type": "EXACT_VALUE",
        "rule": "preserve upstream behavior", "evidence": "CTA active",
        "expected_value": "CTA_ACTIVE_ERROR_ON_CLICK", "observed_value": "CTA_ACTIVE_ERROR_ON_CLICK",
    }]))
    receipt = build_receipt(b, [CheckResult("D6", "COMPLIES", "EXACT_VALUE_MATCH", "PYTHON_DETERMINISTIC")])
    assert receipt["verdict"] == "PASS"
    assert receipt["downstream_disposition"] == "ELIGIBLE"
    assert receipt["self_authorizes_downstream"] is False
    assert len(receipt["receipt_sha256"]) == 64
    passed += 1

    try:
        validate_bundle(bundle([{
            "check_id": "X", "check_type": "SEMANTIC_RELATION",
            "rule": "r", "evidence": "e",
        }, {
            "check_id": "X", "check_type": "SEMANTIC_RELATION",
            "rule": "r2", "evidence": "e2",
        }]))
    except MiniJudgeInputError as exc:
        assert str(exc) == "CHECK_ID_DUPLICATE"
    else:
        raise AssertionError("duplicate check id must fail")
    passed += 1

    if passed != 11:
        raise SystemExit(f"SEMANTIC_MINI_JUDGE_TESTS_FAIL {passed}/11")
    print("SEMANTIC_MINI_JUDGE_TESTS_PASS 11/11")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
