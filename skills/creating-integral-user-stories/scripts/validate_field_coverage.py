"""Read-only executable validator for J04 field contracts and J05 observations/errors."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from lf_common import (
    ValidationInputError,
    duplicate_values,
    emit,
    failure,
    load_json,
    main_guard,
    require_object,
    result_object,
)

J04 = "J04_FIELD_CONTRACTS"
J05 = "J05_OBSERVATIONS_ERRORS"
JUDGES = (J04, J05)
VERSION = "v0.5"
POS = "E23_FIELD_CONTRACTS_POSITIVE"
NEG = "E24_FIELD_CONTRACTS_NEGATIVE"
FIXTURE = "evals/fixtures/screen_sensitive_fields.json"
PII = {"PII_INDIRECT", "PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}
SKILL_ROOT = Path(__file__).resolve().parents[1]


def field_checks(pack: dict[str, Any]) -> tuple[dict[str, list[Any]], dict[str, int]]:
    screen_fields = pack.get("screen_fields", [])
    fields = pack.get("fields", [])
    if not isinstance(screen_fields, list) or not isinstance(fields, list):
        raise ValidationInputError("screen_fields_and_fields_must_be_arrays")

    codes = [item.get("field_code") for item in fields if isinstance(item, dict)]
    declared = {item for item in screen_fields if isinstance(item, str)}
    contracted = {item for item in codes if item}
    checks: dict[str, list[Any]] = {
        "fields_without_contract": sorted(declared - contracted),
        "unexpected_field_contracts": sorted(contracted - declared),
        "duplicate_field_codes": duplicate_values(item for item in codes if item),
        "fields_without_visibility_rule": [],
        "fields_without_editability_rule": [],
        "pii_fields_without_classification": [],
        "pii_fields_with_analytics_allowed": [],
        "pii_fields_with_logs_allowed_without_rule": [],
        "editable_fields_without_audit_strategy": [],
        "fields_without_validation_mapping": [],
    }
    for index, item in enumerate(fields):
        code = item.get("field_code") if isinstance(item, dict) else f"index:{index}"
        if not isinstance(item, dict):
            checks["fields_without_visibility_rule"].append(code)
            checks["fields_without_editability_rule"].append(code)
            continue
        if not item.get("visibility_mode"):
            checks["fields_without_visibility_rule"].append(code)
        if "editable" not in item:
            checks["fields_without_editability_rule"].append(code)
        classification = item.get("pii_classification")
        if not classification:
            checks["pii_fields_without_classification"].append(code)
        if classification in PII and item.get("analytics_allowed") is not False:
            checks["pii_fields_with_analytics_allowed"].append(code)
        if classification in PII and item.get("logs_allowed") is True and not item.get("masking_rule"):
            checks["pii_fields_with_logs_allowed_without_rule"].append(code)
        if item.get("editable") is True and (
            item.get("audit_required") is not True
            or not item.get("previous_value_strategy")
            or not item.get("new_value_strategy")
        ):
            checks["editable_fields_without_audit_strategy"].append(code)
        if not item.get("validation_codes"):
            checks["fields_without_validation_mapping"].append(code)

    summary = {
        "screen_fields_count": len(declared),
        "field_contracts_count": len(fields),
        "pii_field_count": sum(
            isinstance(item, dict) and item.get("pii_classification") in PII for item in fields
        ),
        "editable_field_count": sum(
            isinstance(item, dict) and item.get("editable") is True for item in fields
        ),
    }
    return checks, summary


def observations_errors_checks(pack: dict[str, Any]) -> tuple[dict[str, list[Any]], dict[str, int]]:
    observations = pack.get("observations", [])
    errors = pack.get("errors", [])
    if not isinstance(observations, list) or not isinstance(errors, list):
        raise ValidationInputError("observations_and_errors_must_be_arrays")

    codes = [
        item.get("error_code")
        for item in errors
        if isinstance(item, dict) and item.get("error_code")
    ]
    checks: dict[str, list[Any]] = {
        "blocking_conditions_without_error_code": [],
        "observations_without_user_action": [],
        "retryable_errors_without_retry_policy": [],
        "errors_without_correlation_strategy": [],
        "technical_errors_exposed_to_user": [],
        "duplicate_error_codes": duplicate_values(codes),
        "errors_without_message_code": [],
    }
    for index, item in enumerate(observations):
        code = item.get("observation_code") if isinstance(item, dict) else f"index:{index}"
        if not isinstance(item, dict) or not item.get("user_action"):
            checks["observations_without_user_action"].append(code)
    for index, item in enumerate(errors):
        code = item.get("error_code") if isinstance(item, dict) else f"index:{index}"
        if not isinstance(item, dict):
            checks["blocking_conditions_without_error_code"].append(code)
            continue
        if item.get("blocking") is True and not item.get("error_code"):
            checks["blocking_conditions_without_error_code"].append(code or f"index:{index}")
        retry_policy = item.get("retry_policy")
        if item.get("retryable") is True and (
            not isinstance(retry_policy, dict)
            or not isinstance(retry_policy.get("max_attempts"), int)
            or retry_policy.get("max_attempts", 0) < 1
            or not retry_policy.get("backoff")
        ):
            checks["retryable_errors_without_retry_policy"].append(code)
        if item.get("correlation_id_required") is not True and not item.get("trace_code"):
            checks["errors_without_correlation_strategy"].append(code)
        if item.get("technical_detail_visibility") != "INTERNAL_ONLY":
            checks["technical_errors_exposed_to_user"].append(code)
        if not item.get("user_message_code"):
            checks["errors_without_message_code"].append(code)

    summary = {
        "observation_count": len(observations),
        "error_count": len(errors),
        "error_code_count": len(codes),
        "retry_policy_count": sum(
            isinstance(item, dict) and isinstance(item.get("retry_policy"), dict)
            for item in errors
        ),
        "correlation_strategy_count": sum(
            isinstance(item, dict)
            and (item.get("correlation_id_required") is True or bool(item.get("trace_code")))
            for item in errors
        ),
    }
    return checks, summary


def validate(pack: dict[str, Any], judge: str) -> tuple[list[str], list[dict[str, Any]], dict[str, Any]]:
    checks, summary = field_checks(pack) if judge == J04 else observations_errors_checks(pack)
    failed = [f"{key}={len(value)}" for key, value in checks.items() if value]
    repairs = [
        failure(
            key,
            "fields" if judge == J04 else ("observations" if key.startswith("observations_") else "errors"),
            f"Repair objects: {value}",
        )
        for key, value in checks.items()
        if value
    ]
    return sorted(failed), repairs, {**summary, "checks": checks}


def positive() -> dict[str, Any]:
    rows = [
        ("document_number", False, "MASKED", "PII_DIRECT", "SHOW_LAST_4", "VAL-DOCUMENT-FORMAT"),
        ("phone", True, "MASKED", "PII_DIRECT", "SHOW_LAST_3", "VAL-PHONE-FORMAT"),
        ("email", True, "MASKED", "PII_DIRECT", "MASK_EMAIL", "VAL-EMAIL-FORMAT"),
        ("bank_account", True, "MASKED", "PII_FINANCIAL", "SHOW_LAST_4", "VAL-BANK-ACCOUNT"),
        ("monthly_income", False, "SUMMARY", "PII_FINANCIAL", None, "VAL-INCOME-RANGE"),
    ]
    fields: list[dict[str, Any]] = []
    for code, editable, visibility, classification, masking, validation in rows:
        item: dict[str, Any] = {
            "field_code": code,
            "data_type": "DECIMAL" if code == "monthly_income" else "STRING",
            "required": code in {"document_number", "phone", "email"},
            "editable": editable,
            "visibility_mode": visibility,
            "pii_classification": classification,
            "analytics_allowed": False,
            "logs_allowed": False,
            "export_allowed": False,
            "audit_required": editable,
            "validation_codes": [validation],
            "source_ref": f"SRC-SENSITIVE#{code}",
        }
        if masking:
            item["masking_rule"] = masking
        if editable:
            item.update(previous_value_strategy="MASKED", new_value_strategy="MASKED")
        fields.append(item)
    return {
        "screen_fields": [row[0] for row in rows],
        "fields": fields,
        "observations": [
            {
                "observation_code": "OBS-CONTACT-FORMAT",
                "user_action": "Corregir formato y reenviar",
                "message_code": "MSG-CONTACT-FORMAT",
            }
        ],
        "errors": [
            {
                "error_code": "ERR-PROFILE-UPDATE-TIMEOUT",
                "blocking": True,
                "retryable": True,
                "retry_policy": {"max_attempts": 2, "backoff": "EXPONENTIAL"},
                "user_message_code": "MSG-PROFILE-TEMPORARILY-UNAVAILABLE",
                "correlation_id_required": True,
                "trace_code": "TRACE-PROFILE-UPDATE",
                "technical_detail_visibility": "INTERNAL_ONLY",
            }
        ],
    }


def negative() -> dict[str, Any]:
    return {
        "screen_fields": ["document_number", "phone", "bank_account"],
        "fields": [
            {
                "field_code": "document_number",
                "data_type": "STRING",
                "required": True,
                "editable": False,
                "visibility_mode": "FULL",
                "pii_classification": "PII_DIRECT",
                "analytics_allowed": True,
                "logs_allowed": True,
                "export_allowed": False,
                "audit_required": False,
                "validation_codes": [],
                "source_ref": "SRC-SENSITIVE#document",
            },
            {
                "field_code": "phone",
                "data_type": "STRING",
                "required": True,
                "editable": True,
                "visibility_mode": "FULL",
                "pii_classification": "PII_DIRECT",
                "analytics_allowed": False,
                "logs_allowed": False,
                "export_allowed": False,
                "audit_required": False,
                "validation_codes": [],
                "source_ref": "SRC-SENSITIVE#phone",
            },
        ],
        "observations": [{"observation_code": "OBS-UNKNOWN", "message_code": "MSG-UNKNOWN"}],
        "errors": [
            {
                "blocking": True,
                "retryable": True,
                "correlation_id_required": False,
                "technical_detail_visibility": "USER_VISIBLE",
                "technical_detail": "stack trace",
            }
        ],
    }


def eval_case(case_id: str, judge: str) -> int:
    if case_id == POS:
        pack, expected, must_reject = positive(), "PASS_WITH_EVIDENCE", False
    elif case_id == NEG:
        pack, expected, must_reject = negative(), "RETURN_TO_WORKER", True
    else:
        raise ValidationInputError(f"eval_case_not_found:{case_id}")

    failed, _, candidate_evidence = validate(pack, judge)
    actual = "PASS_WITH_EVIDENCE" if not failed else "RETURN_TO_WORKER"
    mismatch = [] if actual == expected else [f"validator_result_mismatch:{actual}!={expected}"]
    if must_reject and actual == "PASS_WITH_EVIDENCE":
        mismatch.append("negative_case_not_rejected=1")

    fixture_path = SKILL_ROOT / FIXTURE
    evidence = {
        "case_id": case_id,
        "judge": judge,
        "fixture_ref": FIXTURE,
        "expected_validation_result": expected,
        "actual_validation_result": actual,
        "matched": not mismatch,
        "candidate_failed_assertions": failed,
        "candidate_evidence": candidate_evidence,
        "negative_must_be_rejected": must_reject,
        "input_path": str(fixture_path),
    }
    repairs = [] if not mismatch else [
        failure(
            "validator_result_mismatch",
            f"evals.{case_id}.{judge}",
            "Align candidate, expectation or validator without weakening assertions.",
        )
    ]
    return emit(
        result_object(
            judge,
            mismatch,
            evidence,
            [f"file:{fixture_path}", f"eval:{case_id}"],
            repairs,
            retry_count=0,
            judge_version=VERSION,
            executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J04_J05_EVAL_RUNNER",
        )
    )


def self_test() -> int:
    outcomes: list[dict[str, Any]] = []
    passed = True
    for case_id, judge, expected in (
        (POS, J04, "PASS_WITH_EVIDENCE"),
        (POS, J05, "PASS_WITH_EVIDENCE"),
        (NEG, J04, "RETURN_TO_WORKER"),
        (NEG, J05, "RETURN_TO_WORKER"),
    ):
        pack = positive() if case_id == POS else negative()
        failed, _, _ = validate(pack, judge)
        actual = "PASS_WITH_EVIDENCE" if not failed else "RETURN_TO_WORKER"
        matched = actual == expected
        outcomes.append(
            {
                "case_id": case_id,
                "judge": judge,
                "expected": expected,
                "actual": actual,
                "matched": matched,
                "failed_assertions": failed,
            }
        )
        passed = passed and matched
    print(
        json.dumps(
            {
                "judge_code": "J04_J05_FIELD_OBSERVATIONS_ERRORS_CHAIN",
                "result": "PASS_WITH_EVIDENCE" if passed else "FAIL",
                "compliance_bit": 1 if passed else 0,
                "outcomes": outcomes,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0 if passed else 1


def run() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, nargs="?")
    parser.add_argument("--judge", choices=JUDGES, default=J04)
    parser.add_argument("--case-id")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.case_id:
        return eval_case(args.case_id, args.judge)
    if args.input is None:
        raise ValidationInputError("story_pack_input_required")

    pack = require_object(load_json(args.input), "story_pack")
    failed, repairs, evidence = validate(pack, args.judge)
    evidence["input_path"] = str(args.input)
    return emit(
        result_object(
            args.judge,
            failed,
            evidence,
            args.evidence_ref or [f"file:{args.input}"],
            repairs,
            retry_count=args.retry_count,
            judge_version=VERSION,
            executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J04_J05_VALIDATOR",
        )
    )


if __name__ == "__main__":
    raise SystemExit(main_guard("J04_J05_FIELD_OBSERVATIONS_ERRORS_CHAIN", run))
