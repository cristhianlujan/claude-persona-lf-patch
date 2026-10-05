#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SQL=ROOT/"supabase/migrations/20261005222100_db_space_db_size_observability_v1.sql"
text=SQL.read_text(encoding="utf-8")

checks=0
for marker in (
    "private.lf_db_size_snapshots_v1",
    "private.fn_capture_db_size_snapshot_v1()",
    "private.v_lf_db_size_growth_v1",
    "ALERT-DB-SIZE-450MB",
    "471859200",
    "'53 8 * * *'",
    "lf-db-size-snapshot-v1",
    "DB_INTERNAL_ONLY",
    "BLOCK_OBS1_EXISTING_CRON_DRIFT",
    "BLOCK_OBS1_ALERT_READBACK_MISMATCH",
):
    assert marker in text, marker
    checks+=1

assert text.count("cron.schedule(")==1
checks+=1
assert "cron.unschedule" not in text
checks+=1
assert "notification_channel,
  enabled" in text
checks+=1
assert "EXTERNAL_HTTP" not in text
checks+=1
assert "grant select on private.v_lf_db_size_growth_v1" in text.lower()
checks+=1

print(f"PASS_DB_SPACE_OBS1_TESTS={checks}/{checks}")
