"""Detect PII leakage and analytics/observability/audit plane mixing for J09."""
from __future__ import annotations

from lf_common import (
    add_common_input, emit, failure, load_json, main_guard, parser,
    require_object, result_object, utc_now,
)

JUDGE = "J09_ANALYTICS_OBSERVABILITY"
PII = {"PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}


def run() -> int:
    started_at = utc_now()
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--judge-version", required=True)
    cli.add_argument("--executor-identity", required=True)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")
    fields = [item for item in pack.get("fields", []) if isinstance(item, dict)]
    sensitive_codes = {
        item.get("field_code") for item in fields if item.get("pii_classification") in PII
    }

    field_policy_leaks = sorted(
        item.get("field_code") for item in fields
        if item.get("pii_classification") in PII and item.get("analytics_allowed") is not False
    )
    log_policy_leaks = sorted(
        item.get("field_code") for item in fields
        if item.get("pii_classification") in PII
        and item.get("logs_allowed")
        and not item.get("masking_rule")
    )

    analytics_raw = pack.get("analytics")
    analytics = [item for item in analytics_raw if isinstance(item, dict)] if isinstance(analytics_raw, list) else []
    event_property_leaks = []
    no_correlation = []
    audit_mixed = []
    events_without_code = []
    for index, event in enumerate(analytics):
        code = event.get("event_code", "<missing>")
        if not event.get("event_code"):
            events_without_code.append(f"analytics[{index}]")
        properties = set(event.get("properties", [])) if isinstance(event.get("properties"), list) else set()
        overlap = sorted(properties & sensitive_codes)
        if overlap or event.get("pii_free") is not True:
            event_property_leaks.append({"event_code": code, "fields": overlap})
        if event.get("correlation_id_required") is not True:
            no_correlation.append(code)
        if event.get("audit_event") or str(code).startswith("AUDIT-"):
            audit_mixed.append(code)

    observability_raw = pack.get("observability")
    observability = observability_raw if isinstance(observability_raw, dict) else {}
    critical_errors = [
        item for item in pack.get("errors", [])
        if isinstance(item, dict) and item.get("severity") == "CRITICAL"
    ]
    alerts = observability.get("alerts", []) if isinstance(observability.get("alerts"), list) else []
    missing_alert_decision = [] if not critical_errors or alerts else [
        item.get("error_code") for item in critical_errors
    ]

    checks = {
        "analytics_section_missing": [] if isinstance(analytics_raw, list) else ["analytics"],
        "analytics_events_missing": [] if analytics else ["analytics"],
        "analytics_events_without_code": events_without_code,
        "observability_contract_missing": [] if isinstance(observability_raw, dict) else ["observability"],
        "analytics_events_with_pii": field_policy_leaks + event_property_leaks,
        "logs_with_pii_without_contract": log_policy_leaks,
        "operations_without_correlation_id": no_correlation,
        "audit_events_mixed_with_analytics": audit_mixed,
        "critical_failures_without_alert_decision": missing_alert_decision,
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "analytics" if "analytics" in key or "audit_events" in key else "observability",
                f"Repair findings: {values}")
        for key, values in checks.items() if values
    ]
    evidence = {
        "sensitive_field_codes": sorted(code for code in sensitive_codes if code),
        "analytics_event_count": len(analytics),
        "log_count": len(observability.get("logs", [])) if isinstance(observability.get("logs"), list) else 0,
        "metric_count": len(observability.get("metrics", [])) if isinstance(observability.get("metrics"), list) else 0,
        "alert_count": len(alerts),
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
