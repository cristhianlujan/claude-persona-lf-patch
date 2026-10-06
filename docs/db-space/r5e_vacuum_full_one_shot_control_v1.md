# R5-E VACUUM FULL — versioned one-shot transport v2

Status: **DRAFT / INSTALLATION MECHANISM ONLY / DO NOT APPLY**

## Decision on the maintenance-role proposal

The preferred `lf_maintenance_v1 NOLOGIN` design is **not viable in this Supabase project**.

Read-only verification established:

- PostgreSQL 17.6;
- pg_cron 1.6.4;
- `cron.use_background_workers=off`;
- `cron.timezone=GMT` and the database session timezone is UTC;
- the project `postgres` role has `rolsuper=false`;
- `cron.schedule_in_database(..., username ...)` is installed, but pg_cron's implementation requires the caller to be a **superuser** to schedule a job for another role;
- with `cron.use_background_workers=off`, cron opens a libpq connection as the job username, so a `NOLOGIN` role could not be that connection identity anyway.

Therefore this Draft uses the explicitly accepted fallback: short-lived role-level `postgres.lock_timeout`, plus an independent safety reset and an explicit clean-setting readback.

No role setting is changed by this Draft. The setting is only part of the later activation migration.

## Scope

Three physical rewrites, each as its own top-level SQL statement:

1. `VACUUM (FULL, ANALYZE) programacion.input_family_assessments`
2. `VACUUM (FULL, ANALYZE) inventory.objects`
3. `VACUUM (FULL, ANALYZE) inventory.search_index`

They are deliberately separate cron jobs because VACUUM cannot be wrapped in a database function or a transaction block.

## Current physical baselines

Read-only snapshot at design time:

| Relation | Heap | Indexes | TOAST/aux | Total |
|---|---:|---:|---:|---:|
| input_family_assessments | 20.08 MiB | 1.85 MiB | 134.07 MiB | **156.00 MiB** |
| inventory.objects | 23.15 MiB | 13.75 MiB | 0.40 MiB | **37.30 MiB** |
| inventory.search_index | 14.85 MiB | 12.16 MiB | 0.22 MiB | **27.23 MiB** |

Expected post-rewrite sizing is an estimate, not an acceptance threshold:

- `input_family_assessments`: accepted simulation **~59.61 MiB** after R5-E compaction;
- `inventory.objects`: approximately **18–23 MiB** with current indexes, or roughly **10–16 MiB** if the separately reviewed metadata GIN drop lands first;
- `inventory.search_index`: approximately **18–21 MiB** with current indexes, or roughly **14–18 MiB** if the separately reviewed tags/columns GIN drops land first.

The checkpoint records actual pre/post values per table; these estimates are never used to decide success.

## Objects installed by the Draft migration

Migration:

`20261006223500_r5e_vacuum_full_one_shot_control_v1.sql`

It creates:

- `private.lf_r5e_vacuum_control_v1`;
- `private.lf_r5e_vacuum_table_receipts_v1`;
- `private.fn_r5e_postgres_lock_timeout_clean_v1()`;
- `private.fn_r5e_vacuum_capture_size_v1(regclass)`;
- `private.fn_r5e_vacuum_disable_jobs_v1()`;
- `private.fn_r5e_vacuum_finalize_v1()`;
- `private.fn_r5e_vacuum_safety_reset_v1()`.

Five jobs are installed **inactive**:

- `lf-r5e-vacuum-assessments-v1`;
- `lf-r5e-vacuum-inventory-objects-v1`;
- `lf-r5e-vacuum-inventory-search-index-v1`;
- `lf-r5e-vacuum-finalizer-v1`;
- `lf-r5e-vacuum-safety-reset-v1`.

The installation postcheck requires all five jobs to be inactive and requires no persisted `postgres.lock_timeout` role setting.

## Future activation migration

Only after R5-E checkpoint is VERIFIED and Cristhian approves the maintenance window, a separate train migration will:

1. verify R5-E VERIFIED;
2. verify no Curator/Validator activity that would touch the target relation;
3. snapshot pre-size metrics for all three target tables and current DB size into `lf_r5e_vacuum_table_receipts_v1`;
4. set the control to ARMED;
5. set:
   `ALTER ROLE postgres SET lock_timeout='5s'`;
6. set `safety_deadline = clock_timestamp() + interval '30 minutes'`;
7. arm only the assessments VACUUM job for the next exact cron minute;
8. activate the finalizer and safety-reset jobs.

The other two VACUUM jobs remain inactive until the previous target succeeds.

This limits the role-level setting to the coordinated maintenance window instead of applying it ahead of time.

## Sequential execution

The finalizer observes `cron.job_run_details`.

For the current target:

- no run yet -> wait;
- running -> receipt RUNNING;
- failed -> record failure, reset lock timeout, disable all jobs, STOP;
- succeeded -> capture actual post table/heap/index/TOAST/DB sizes, mark target VERIFIED.

Only after a target is VERIFIED does the finalizer arm the next target for the next exact cron minute.

Thus the jobs are serial:

`input_family_assessments -> inventory.objects -> inventory.search_index`

and cannot intentionally overlap.

After the third success, the next finalizer tick:

- runs `ALTER ROLE postgres RESET lock_timeout`;
- verifies through `pg_db_role_setting` that no persisted `lock_timeout=` remains for postgres;
- sets global control VERIFIED;
- disables and unschedules every maintenance job.

A failed clean-setting readback converts the maintenance control to FAILED.

## Independent 30-minute safety reset

The separate job `lf-r5e-vacuum-safety-reset-v1` runs once per minute only while the window is armed.

At `safety_deadline`, regardless of which VACUUM/finalizer state is current, it:

1. executes `ALTER ROLE postgres RESET lock_timeout`;
2. reads `pg_db_role_setting`;
3. stores `lock_timeout_clean=true/false`;
4. disables every R5-E maintenance job;
5. marks the maintenance FAILED so human review is mandatory.

This is intentionally independent from the normal finalizer path.

## Per-table receipt

For each of the three targets the checkpoint retains:

- relation and job identity;
- cron run id/status/message/start/end;
- pre total/heap/index/TOAST bytes;
- pre DB bytes;
- post total/heap/index/TOAST bytes;
- post DB bytes.

The physical size estimate is informational only. Success is based on successful VACUUM execution plus readback, not on reaching an exact byte target.

## Lock behavior

Each `VACUUM FULL` takes ACCESS EXCLUSIVE on its target relation.

The 5-second lock timeout is meant to fail the job rather than wait behind unexpected activity.

Because the fallback uses `postgres`, other **new postgres sessions** during the window inherit that 5-second role setting. That is why:

- the activation migration must be executed only at the agreed window;
- the safety deadline is 30 minutes;
- both terminal paths RESET it;
- persisted role-setting readback is mandatory.

## Not performed by this Draft

- no role creation;
- no `ALTER ROLE ... SET`;
- no active job;
- no VACUUM;
- no DELETE;
- no DISABLE TRIGGER;
- no REINDEX.
