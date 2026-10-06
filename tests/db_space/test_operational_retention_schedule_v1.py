#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SQL=ROOT/"supabase/migrations/20261005222000_db_space_operational_retention_schedule_v1.sql"
text=SQL.read_text(encoding="utf-8")

checks=0
for marker in (
    "lf-operational-retention-v1",
    "'43 8 * * *'",
    "select private.fn_operational_retention_v1(true);",
    "create temporary table _lf_b1b_cron_before",
    "BLOCK_B1B_EXISTING_CRON_DRIFT",
    "BLOCK_B1B_CRON_COUNT_DELTA",
):
    assert marker in text, marker
    checks+=1

assert text.count("cron.schedule(")==1
checks+=1
assert "cron.unschedule" not in text
checks+=1
assert "update cron.job" not in text.lower()
checks+=1
assert "delete from cron.job" not in text.lower()
checks+=1

print(f"PASS_DB_SPACE_B1B_SCHEDULE_TESTS={checks}/{checks}")
