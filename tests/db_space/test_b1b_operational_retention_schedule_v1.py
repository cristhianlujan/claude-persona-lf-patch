#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SQL=(ROOT/"supabase/migrations/20261005220727_db_space_operational_retention_schedule_v1.sql").read_text(encoding="utf-8")
checks=0

assert SQL.count("cron.schedule(")==1; checks+=1
assert "cron.unschedule" not in SQL; checks+=1
assert "'lf-operational-retention-v1'" in SQL; checks+=1
assert "'43 8 * * *'" in SQL; checks+=1
assert "'select private.fn_operational_retention_v1(true);'" in SQL; checks+=1
assert "BLOCK_B1B_TARGET_JOB_ALREADY_EXISTS" in SQL; checks+=1
assert "BLOCK_B1B_TARGET_JOB_READBACK_FAILED" in SQL; checks+=1
assert "BLOCK_B1B_UNRELATED_CRON_JOB_CHANGED" in SQL; checks+=1
assert "jsonb_agg(to_jsonb(j) order by j.jobid)" in SQL; checks+=1
assert "where j.jobname <> 'lf-operational-retention-v1'" in SQL; checks+=1
assert "private.fn_operational_retention_v1(true)" in SQL; checks+=1
assert SQL.strip().endswith("commit;"); checks+=1

print(f"PASS_DB_SPACE_B1B_CONTRACT={checks}/12")
