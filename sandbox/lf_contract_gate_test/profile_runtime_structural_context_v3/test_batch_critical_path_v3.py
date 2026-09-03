#!/usr/bin/env python3
"""Pin the observed critical path of B2B-CARGA-001 profile batch 33596749435.

This is a telemetry regression, not a parallelism=3 recommendation. It proves where
wall time is spent before any concurrency change is considered.
"""
from datetime import datetime, timedelta

FMT = "%Y-%m-%dT%H:%M:%S.%fZ"
UI_START = datetime.strptime("2026-09-02T06:02:43.064062Z", FMT)
PRODUCT_START = datetime.strptime("2026-09-02T06:02:43.064292Z", FMT)
QUALITY_START = datetime.strptime("2026-09-02T06:08:31.746631Z", FMT)
UI_MS = 672_969
PRODUCT_MS = 348_682
QUALITY_MS = 439_227
BATCH_TOTAL_MS = 787_911

def finish(start, duration_ms):
    return start + timedelta(milliseconds=duration_ms)

def main() -> int:
    product_end = finish(PRODUCT_START, PRODUCT_MS)
    ui_end = finish(UI_START, UI_MS)
    quality_end = finish(QUALITY_START, QUALITY_MS)
    slot_handoff_ms = (QUALITY_START - product_end).total_seconds() * 1000
    critical_path_ms = PRODUCT_MS + QUALITY_MS
    assert abs(slot_handoff_ms) < 1.0, slot_handoff_ms
    assert abs(BATCH_TOTAL_MS - critical_path_ms) <= 5
    assert ui_end < quality_end
    # It would be unsafe to infer a realized improvement from a hypothetical third slot.
    theoretical_p3_floor_ms = max(UI_MS, PRODUCT_MS, QUALITY_MS)
    assert theoretical_p3_floor_ms == UI_MS
    print(
        "BATCH_CRITICAL_PATH_V3_PASS "
        f"slot_handoff_ms={slot_handoff_ms:.3f} "
        f"critical_path_ms={critical_path_ms} batch_total_ms={BATCH_TOTAL_MS} "
        f"critical_path_delta_ms={BATCH_TOTAL_MS-critical_path_ms} "
        f"ui_finish={ui_end.isoformat()} quality_finish={quality_end.isoformat()} "
        f"theoretical_parallelism3_floor_ms={theoretical_p3_floor_ms} "
        "parallelism3_actual_improvement=NOT_TESTED"
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
