#!/usr/bin/env python3
"""S36 WP6 live assurance completeness gate.

This gate is intentionally narrow: it only compares the live operational
assurance debt with the exact accepted-debt baseline persisted in S36 snapshot
61. It fails closed on debt growth, BLOCKED live states, or new assurance
activity that still does not reach COVERED.
"""
from __future__ import annotations

import csv
import os
import subprocess

PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"

SQL = r"""
with s as (
  select metadata->'test_assurance_coverage_ci'->'accepted_debt_baseline' as b
  from public.lf_strategy_snapshots
  where id = 61
), baseline as (
  select
    x->>'operation_code' as operation_code,
    x->>'coverage_state' as coverage_state,
    (x->>'required_binding_count')::int as required_binding_count,
    (x->>'observed_run_count')::int as observed_run_count
  from s,
       lateral jsonb_array_elements(coalesce(b->'rows','[]'::jsonb)) x
), live as (
  select *
  from public.lf_s36_operation_assurance_coverage_v1()
  where lifecycle_state_code = 'OP_OPERATIONAL'
    and assurance_obligation = 'REQUIRED'
), issues as (
  select
    l.operation_code,
    l.coverage_state,
    case
      when b.operation_code is null and l.coverage_state <> 'COVERED'
        then 'NEW_REQUIRED_OPERATION_DEBT'
      when l.coverage_state = 'BLOCKED'
        then 'LIVE_BLOCKED'
      when b.operation_code is not null
       and l.coverage_state <> 'COVERED'
       and l.coverage_state <> b.coverage_state
        then 'ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE'
      when b.operation_code is not null
       and l.coverage_state <> 'COVERED'
       and l.required_binding_count > b.required_binding_count
        then 'BINDING_ACTIVITY_WITHOUT_COVERAGE'
      when b.operation_code is not null
       and l.coverage_state <> 'COVERED'
       and l.observed_run_count > b.observed_run_count
        then 'NEW_RUN_ACTIVITY_WITHOUT_COVERAGE'
      else null
    end as issue_code
  from live l
  left join baseline b using (operation_code)
)
select operation_code, coverage_state, issue_code
from issues
where issue_code is not null
order by operation_code;
"""


def main() -> int:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    if not password:
        raise SystemExit("FAIL_S36_COMPLETENESS_DB_PASSWORD_MISSING")

    env = os.environ.copy()
    env.update({
        "PGHOST": POOLER_HOST,
        "PGPORT": "5432",
        "PGUSER": f"postgres.{PROJECT_ID}",
        "PGDATABASE": "postgres",
        "PGSSLMODE": "require",
        "PGPASSWORD": password,
    })

    cmd = [
        "docker", "run", "--rm",
        "-e", "PGHOST", "-e", "PGPORT", "-e", "PGUSER",
        "-e", "PGPASSWORD", "-e", "PGDATABASE", "-e", "PGSSLMODE",
        "postgres:17.6", "psql", "-X", "-v", "ON_ERROR_STOP=1",
        "--csv", "-t", "-c", SQL,
    ]
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr)
        raise SystemExit("FAIL_S36_COMPLETENESS_QUERY")

    rows = list(csv.reader(proc.stdout.splitlines()))
    if rows:
        for row in rows:
            print("S36_COMPLETENESS_ISSUE=" + "|".join(row))
        raise SystemExit(f"FAIL_S36_ASSURANCE_COMPLETENESS issues={len(rows)}")

    print("PASS_S36_ASSURANCE_COMPLETENESS accepted_debt_not_growing=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
