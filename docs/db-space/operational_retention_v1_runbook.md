# DB-SPACE — OPERATIONAL RETENTION v1 runbook

Status: PREPARED ONLY. Do not execute DELETE, VACUUM FULL, schedule a cron job, merge or deploy without explicit owner approval for that step.

## Preconditions

1. Confirm PR-B1 migration has been applied only after approval.
2. Confirm `private.fn_operational_retention_v1(false)` reports `pg_notify_preflight.safe=true`.
3. Confirm no `private.lf_architecture_notification_attempts_v4` or `private.lf_architecture_notification_receipts_v4` row references a `PG_NOTIFY` outbox row.
4. Capture `pg_database_size(current_database())`.
5. Capture `cron.job` schedules/active flags and the current latest monitor row.

## First supervised execution

### A. Dry-run

```sql
select private.fn_operational_retention_v1(false);
```

Review candidate rows and estimated reclaim MB for all four relations. STOP if counts differ materially from the reviewed policy.

### B. Apply once, supervised

Only after explicit owner approval:

```sql
select private.fn_operational_retention_v1(true);
```

Record the returned `deleted_rows` for each relation.

### C. Mandatory readback

Cron status for every job:

```sql
select
  j.jobid,
  j.jobname,
  private.fn_latest_cron_status_v3(j.jobname) as latest_status
from cron.job j
order by j.jobid;
```

Architecture closure:

```sql
select *
from public.v_lf_architecture_closure_v4;
```

Non-terminal profile queue:

```sql
select status,count(*)::bigint
from private.lf_profile_runtime_queue_v1
where status in ('PENDING','BLOCKED','FAILED')
group by status
order by status;
```

Cron configuration:

```sql
select jobid,jobname,schedule,active,command
from cron.job
order by jobid;
```

STOP if latest cron semantics, latest monitor/closure, non-terminal queue states, or any existing cron schedule/active flag changed.

## Physical reclaim

DELETE makes pages reusable but does not by itself shrink the database files. VACUUM FULL is a separate, explicitly destructive/locking maintenance action and requires owner approval.

Run one table at a time, measuring before and after:

```sql
select pg_database_size(current_database()) as before_bytes;
vacuum full cron.job_run_details;
select pg_database_size(current_database()) as after_bytes;
```

Then, separately:

```sql
vacuum full private.lf_architecture_monitor_runs_v4;
vacuum full private.lf_architecture_notification_outbox_v4;
vacuum full private.lf_profile_runtime_queue_v1;
```

For every table:
1. capture `pg_database_size` immediately before;
2. execute only that one `VACUUM FULL`;
3. capture `pg_database_size` after;
4. rerun the mandatory readback;
5. STOP on any unexpected semantic drift or insufficient disk headroom.

## PR-B1b — schedule only after supervised closure

PR-B1 deliberately does **not** schedule retention.

After the supervised first apply + readback + physical reclaim has passed, prepare a separate small migration (PR-B1b) that schedules:

```sql
select cron.schedule(
  'lf-operational-retention-v1',
  '43 8 * * *',
  $$select private.fn_operational_retention_v1(true);$$
);
```

PR-B1b must snapshot every pre-existing `cron.job` row before scheduling and verify after scheduling that no pre-existing job changed `schedule`, `active`, or `command`. The only allowed delta is the new `lf-operational-retention-v1` job.
