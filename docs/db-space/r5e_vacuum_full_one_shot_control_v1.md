# R5-E VACUUM FULL — versioned one-shot transport

Status: **DRAFT / INSTALLATION MECHANISM ONLY / DO NOT APPLY**

This unit is separate from R5-E compaction because the migration train accepts one migration per PR and VACUUM FULL cannot execute inside the train transaction.

## Verified project capability

Read-only live verification:

- PostgreSQL 17.6.
- pg_cron 1.6.4.
- `cron.use_background_workers=off`.
- operational cron jobs execute as `postgres`.
- Supabase Cron documentation supports a cron job whose command is plain `VACUUM`.
- this project's pg_cron exposes only:
  - `cron.schedule(text,text)`;
  - `cron.schedule(text,text,text)`.
- there is no native timestamp/one-shot schedule overload.

Therefore the one-shot guarantee is implemented as a recurring-syntax job plus a finalizer that unschedules it after its first terminal run.

## What the Draft migration installs

Migration:

`20261006223500_r5e_vacuum_full_one_shot_control_v1.sql`

It creates:

- `private.lf_r5e_vacuum_checkpoint_v1`;
- `private.fn_r5e_vacuum_finalize_v1()`;
- cron job `lf-r5e-vacuum-full-once-v1`;
- cron job `lf-r5e-vacuum-finalizer-v1`.

Both jobs are installed with `active=false`.

The VACUUM command is exactly:

`VACUUM (FULL, ANALYZE) programacion.input_family_assessments`

The placeholder schedule is irrelevant while inactive and is replaced by the later window-activation migration.

## Why SET lock_timeout cannot be prepended to the VACUUM command

The cron VACUUM job must be one top-level VACUUM statement.

A command shaped as:

`SET lock_timeout='5s'; VACUUM ...`

would submit multiple statements as one simple-query unit and places VACUUM in a transaction context, which PostgreSQL rejects.

The project also has `cron.use_background_workers=off`, so the job opens a fresh DB connection under its configured username.

## Versioned lock-timeout strategy

When Cristhian chooses the window, a **later activation migration through the train** will execute immediately before that window:

1. read and persist pre-size metrics in the checkpoint:
   - assessment total;
   - heap;
   - indexes;
   - TOAST;
   - full DB bytes;
2. persist exact `scheduled_for`;
3. set checkpoint `status='ARMED'`;
4. `ALTER ROLE postgres SET lock_timeout='5s'`;
5. replace the inactive VACUUM job schedule with the exact minute/day/month and set `active=true`;
6. set the finalizer job to `* * * * *` and `active=true`.

Because pg_cron lacks a year field, the schedule itself is technically recurrent. The finalizer removes both job rows after the first terminal execution, making it operationally one-shot.

The activation migration must be applied only shortly before the maintenance window. The temporary role setting affects **all new postgres sessions** during that short period, so it must not be armed hours in advance.

If that blast radius is not accepted, do not use an automatic lock timeout. Instead perform blocker readback immediately before arming and let VACUUM use the normal session setting.

## Finalizer

The finalizer runs once per minute only while armed.

Before the scheduled time it returns WAITING.

After the scheduled time it reads `cron.job_run_details` for the VACUUM job:

- running/no end time -> checkpoint RUNNING, keep waiting;
- succeeded -> record all post-size metrics, checkpoint VERIFIED;
- failed -> record return message, checkpoint FAILED;
- no run observed within 10 minutes -> checkpoint MISSED.

On VERIFIED / FAILED / MISSED it:

- runs `ALTER ROLE postgres RESET lock_timeout`;
- unschedules the VACUUM job;
- unschedules itself;
- falls back to `active=false` if an unschedule operation errors.

## Readback

Pre and post fields are retained in the checkpoint:

- relation bytes;
- heap bytes;
- index bytes;
- TOAST bytes;
- DB bytes;
- pg_cron run id/status;
- error text if any.

After a successful VACUUM the operator also verifies:

- R5-E checkpoint remains VERIFIED;
- historical inline eligible count remains zero;
- compact receipt count unchanged;
- rehydration/hash sample still passes;
- crons 28 and 29 remain active.

## Expected maintenance shape

Current assessment relation reference before R5-E physical rewrite:

- around 156 MiB total;
- around 134 MiB TOAST;
- accepted simulated post-rewrite target: about 59.61 MiB;
- estimated reclaim: about 95 MiB.

Allocate a 15-minute exclusive maintenance window. Expected rewrite remains roughly 2–8 minutes, but this is an estimate, not a benchmark.

VACUUM FULL takes ACCESS EXCLUSIVE on `programacion.input_family_assessments` for the rewrite. Curator/Validator activity should be quiescent.

## Not in this Draft

- no exact maintenance timestamp;
- no `ALTER ROLE ... SET lock_timeout` executed;
- no active cron job;
- no VACUUM execution;
- no REINDEX;
- no DELETE.

The exact window activation is intentionally a later owner-approved migration.
