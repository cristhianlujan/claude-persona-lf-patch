"""Validate 1:1 field coverage, privacy and audit invariants for J04."""
from __future__ import annotations

from lf_common import (
    add_common_input, duplicate_values, emit, failure, load_json, main_guard,
    parser, require_object, result_object,
)

JUDGE = "J04_FIELD_CONTRACTS"
PII = {"PII_INDIRECT", "PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}


def run() -> int:
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")

    screen_fields = pack.get("screen_fields", [])
    contracts = pack.get("fields", [])
    if not isinstance(screen_fields, list) or not isinstance(contracts, list):
        raise ValueError("screen_fields_and_fields_must_be_arrays")

    codes = [item.get("field_code") for item in contracts if isinstance(item, dict)]
    duplicates = duplicate_values(code for code in codes if code)
    declared = set(value for value in screen_fields if isinstance(value, str))
    contracted = set(code for code in codes if code)
    missing = sorted(declared - contracted)
    unexpected = sorted(contracted - declared)

    missing_visibility = []
    missing_editability = []
    pii_no_classification = []
    pii_analytics = []
    pii_logs = []
    editable_no_audit = []
    fields_without_validation = []

    for index, contract in enumerate(contracts):
        code = contract.get("field_code") if isinstance(contract, dict) else f"index:{index}"
        if not isinstance(contract, dict):
            missing_visibility.append(code)
            continue
        if not contract.get("visibility_mode"):
            missing_visibility.append(code)
        if "editable" not in contract:
            missing_editability.append(code)
        classification = contract.get("pii_classification")
        if not classification:
            pii_no_classification.append(code)
        if classification in PII and contract.get("analytics_allowed") is not False:
            pii_analytics.append(code)
        if classification in PII and contract.get("logs_allowed") and not contract.get("masking_rule"):
            pii_logs.append(code)
        if contract.get("editable") and (
            contract.get("audit_required") is not True
            or not contract.get("previous_value_strategy")
            or not contract.get("new_value_strategy")
        ):
            editable_no_audit.append(code)
        if not contract.get("validation_codes"):
            fields_without_validation.append(code)

    checks = {
        "fields_without_contract": missing,
        "unexpected_field_contracts": unexpected,
        "duplicate_field_codes": duplicates,
        "fields_without_visibility_rule": missing_visibility,
        "fields_without_editability_rule": missing_editability,
        "pii_fields_without_classification": pii_no_classification,
        "pii_fields_with_analytics_allowed": pii_analytics,
        "pii_fields_with_logs_allowed_without_rule": pii_logs,
        "editable_fields_without_audit_strategy": editable_no_audit,
        "fields_without_validation_mapping": fields_without_validation,
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "fields", f"Repair field codes: {values}")
        for key, values in checks.items() if values
    ]
    evidence = {
        "screen_fields_count": len(declared),
        "field_contracts_count": len(contracts),
        "checks": checks,
        "input_path": str(args.input),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
