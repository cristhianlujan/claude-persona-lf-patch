"""Detect PII leaking into analytics or logs. J09 support."""
import sys

from lf_common import argv_path, emit, load

PII_LEVELS = ("PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL")


def main():
    pack = load(argv_path(1))
    fields = pack.get("fields", [])
    pii_fields = {f.get("field_code"): f for f in fields
                  if f.get("pii_classification") in PII_LEVELS}
    analytics_leaks, log_leaks = [], []
    for code, field in pii_fields.items():
        if field.get("analytics_allowed"):
            analytics_leaks.append(code)
        if field.get("logs_allowed") and not field.get("masking_rule"):
            log_leaks.append(code)
    events = pack.get("analytics", [])
    no_correlation = [e.get("event_code") for e in events
                      if not e.get("correlation_id_required")]
    mixed = [e.get("event_code") for e in events if e.get("audit_event")]
    failed = []
    if analytics_leaks:
        failed.append("analytics_events_with_pii=%d" % len(analytics_leaks))
    if log_leaks:
        failed.append("logs_with_pii_without_contract=%d" % len(log_leaks))
    if no_correlation:
        failed.append("operations_without_correlation_id=%d" % len(no_correlation))
    if mixed:
        failed.append("audit_events_mixed_with_analytics=%d" % len(mixed))
    evidence = {
        "pii_fields": sorted(pii_fields),
        "analytics_leaks": analytics_leaks,
        "log_leaks": log_leaks,
        "analytics_events": len(events),
    }
    return emit("J09_ANALYTICS_OBSERVABILITY", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
