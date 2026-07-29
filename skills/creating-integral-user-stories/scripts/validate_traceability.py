"""Check source -> rule -> criterion -> test -> evidence traceability for J07/J10."""
from __future__ import annotations

from lf_common import (
    add_common_input, duplicate_values, emit, failure, load_json, main_guard,
    parser, require_object, result_object, utc_now,
)

JUDGE = "J07_AUDIT_TRACEABILITY"


def run() -> int:
    started_at = utc_now()
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--judge-version", required=True)
    cli.add_argument("--executor-identity", required=True)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")

    criteria = [
        item for item in pack.get("core", {}).get("acceptance_criteria", [])
        if isinstance(item, dict)
    ]
    validations = [item for item in pack.get("validations", []) if isinstance(item, dict)]
    tests = [item for item in pack.get("tests", []) if isinstance(item, dict)]
    audit_raw = pack.get("audit")
    audit = audit_raw if isinstance(audit_raw, dict) else {}
    audit_events = [item for item in audit.get("events", []) if isinstance(item, dict)]
    audit_reason = audit.get("reason")
    criterion_ids = {item.get("criterion_code") for item in criteria if item.get("criterion_code")}
    rule_ids = {item.get("validation_code") for item in validations if item.get("validation_code")}
    rule_ids.update(
        item.get("error_code") for item in pack.get("errors", [])
        if isinstance(item, dict) and item.get("error_code")
    )
    rule_ids.update(
        item.get("observation_code") for item in pack.get("observations", [])
        if isinstance(item, dict) and item.get("observation_code")
    )
    rule_ids.update(
        item.get("audit_event_code")
        for item in audit_events
        if item.get("audit_event_code")
    )
    rule_ids.update(
        item.get("event_code") for item in pack.get("analytics", [])
        if isinstance(item, dict) and item.get("event_code")
    )
    sec = pack.get("security_privacy", {})
    if isinstance(sec, dict):
        if sec.get("cross_tenant_policy") == "DENY":
            rule_ids.add("SEC-CROSS-TENANT-DENY")
        if sec.get("idempotency_required") is True:
            rule_ids.add("SEC-IDEMPOTENCY-REQUIRED")

    audit_contract_missing = []
    if not isinstance(audit_raw, dict) or (not audit_events and not audit_reason):
        audit_contract_missing = ["audit"]
    audit_events_without_source = sorted(
        item.get("audit_event_code", "<missing>")
        for item in audit_events
        if not item.get("source_ref")
    )
    audit_events_without_code = [
        f"audit.events[{index}]"
        for index, item in enumerate(audit_events)
        if not item.get("audit_event_code")
    ]
    criteria_without_source = sorted(
        item.get("criterion_code") for item in criteria if not item.get("source_ref")
    )
    rules_without_source = sorted(
        item.get("validation_code") for item in validations if not item.get("source_ref")
    )
    covered_criteria = {
        item.get("criterion_ref") for item in tests if item.get("criterion_ref") in criterion_ids
    }
    covered_rules = {
        item.get("rule_ref") for item in tests if item.get("rule_ref") in rule_ids
    }
    orphan_tests = [
        item.get("test_code") for item in tests
        if item.get("criterion_ref") not in criterion_ids
        and item.get("rule_ref") not in rule_ids
    ]
    tests_without_evidence = [
        item.get("test_code") for item in tests if not item.get("evidence_path")
    ]
    duplicate_test_codes = duplicate_values(
        item.get("test_code") for item in tests if item.get("test_code")
    )

    checks = {
        "audit_contract_missing": audit_contract_missing,
        "audit_events_without_code": audit_events_without_code,
        "audit_events_without_source_reference": audit_events_without_source,
        "criteria_without_source_reference": criteria_without_source,
        "rules_without_source_reference": rules_without_source,
        "criteria_without_test_reference": sorted(criterion_ids - covered_criteria),
        "critical_rules_without_test": sorted(
            item.get("validation_code") for item in validations
            if item.get("critical") and item.get("validation_code") not in covered_rules
        ),
        "tests_without_story_reference": orphan_tests,
        "tests_without_evidence_path": tests_without_evidence,
        "duplicate_test_codes": duplicate_test_codes,
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(
            key,
            "audit" if key.startswith("audit_") else ("tests" if "test" in key else "validations"),
            f"Repair references: {values}",
        )
        for key, values in checks.items() if values
    ]
    evidence = {
        "audit_event_count": len(audit_events),
        "audit_reason_present": bool(audit_reason),
        "criterion_count": len(criterion_ids),
        "rule_count": len(rule_ids),
        "test_count": len(tests),
        "covered_criteria_count": len(covered_criteria),
        "covered_rules_count": len(covered_rules),
        "traceability_breaks": sum(len(values) for values in checks.values()),
        "checks": checks,
        "input_path": str(args.input),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
        judge_version=args.judge_version,
        executor_identity=args.executor_identity,
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
