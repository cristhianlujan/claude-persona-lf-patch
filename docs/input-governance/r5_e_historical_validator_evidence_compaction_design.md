# R5-E — historical Validator evidence compaction

Status: **DRAFT / DESIGN ONLY / DO NOT APPLY**

Dependencies already live:

- R5-C STORAGE_COMPACTION transition.
- CONTRACT-5.13.1 logical evidence representation contract.
- R5-D compact new Validator writes.

R5-E is only for historical terminal Validator receipts that still store inline `assertions`.

## Live sizing snapshot

Snapshot immediately after R5-D:

- `programacion.input_family_assessments`: 11,045 rows total.
- historical terminal inline rows eligible for R5-E: **10,131**.
- compact rows: **0**.
- eligible runs: **216**.
- eligibility distribution:
  - COMPLETED + invalidated: 7,896 rows;
  - COMPLETED + current: 2,068;
  - BLOCKED + invalidated: 47;
  - BLOCKED + current: 120.
- assertion-set catalog: 3,379 sets.
- `input_family_assessments` physical total: **156 MiB**.
- heap: about 20 MiB.
- TOAST: about **134 MiB**.
- indexes: about 1.9 MiB.
- assertion-set catalog physical total: about 30 MiB.
- database total: about **572 MiB**.

The accepted physical simulation for the assessment relation was approximately
**154.80 MiB -> 59.61 MiB**, or about **95 MiB reclaimable** after a rewrite.

## Eligibility

A row is eligible only when all conditions are true:

```sql
validator_outcome <> 'PENDING'
and validator_evidence ? 'assertions'
and not (validator_evidence ? 'assertion_set_sha256')
and validator_sha256 is not null
```

R5-E does not depend on run invalidation state. COMPLETED and BLOCKED terminal receipts are immutable receipts whose only allowed mutation is the R5-C STORAGE_COMPACTION representation transition.

Runs 22 and 309 are PENDING/orphan branches and therefore have no eligible rows.

## Fail-closed preflight

Before the first batch, freeze/read back:

- contract revision = `5.13.1`;
- contract SHA =
  `dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516`;
- `fn_guard_input_family_assessment_update()` = reviewed R5-C final MD5;
- `fn_input_validator_evidence_rehydrate_v1(jsonb)` = reviewed rehydrator MD5;
- assertion-set catalog cardinality >= 3,379;
- every eligible inline assertion array resolves to exactly one catalog row whose content-address SHA equals the key;
- no row already contains both `assertions` and `assertion_set_sha256`;
- record the exact starting eligible count and max assessment id.

Any mismatch stops the run for human review.

## Batch model

Default batch size: **100 assessments** ordered by `input_family_assessments.id`.

At the current count, that is **102 batches**:
101 full batches plus one final batch of 31.

If lock latency or trigger latency is material, reduce to 50 rows without changing semantics.

Only one R5-E runner may execute at once. The implementation should take one transaction-scoped advisory lock for the compaction process so two operators cannot advance the same checkpoint concurrently.

Use keyset progression, never OFFSET:

```sql
where id > :last_verified_id
  and validator_outcome <> 'PENDING'
  and validator_evidence ? 'assertions'
  and not (validator_evidence ? 'assertion_set_sha256')
order by id
limit :batch_size
```

## Per-row transition

For every candidate row, while holding the row lock:

1. Capture:
   - assessment id;
   - old `validator_evidence`;
   - old `validator_sha256`.
2. Compute:
   `assertion_set_sha256 = fn_v09_sha256_jsonb(old.validator_evidence->'assertions')`.
3. Require exactly one row in `input_validator_assertion_sets_v1` with:
   - that SHA;
   - assertions exactly equal to the inline array;
   - content-address recomputation equal to the stored SHA.
4. Construct:
   ```sql
   new_evidence =
     (old_evidence - 'assertions')
     || jsonb_build_object('assertion_set_sha256', assertion_set_sha256)
   ```
5. Execute an ordinary UPDATE changing **only** `validator_evidence`.
   - no trigger disabling;
   - no direct bypass;
   - `validator_sha256` is not assigned.
6. R5-C must accept the update as STORAGE_COMPACTION.
7. Immediately read back and require:
   - `validator_sha256 = old_validator_sha256`;
   - `fn_input_validator_evidence_rehydrate_v1(new_evidence) = old_evidence`;
   - inline `assertions` absent;
   - `assertion_set_sha256` present and exact.
8. Add the row receipt to the batch receipt.

Any row failure aborts the **whole current batch transaction**. Previous verified batches remain committed.

## Checkpoint / resumability

The implementation should introduce a small governed checkpoint relation rather than inferring progress from elapsed time.

Suggested immutable identity:
`R5_E_HISTORICAL_VALIDATOR_EVIDENCE_V1`.

Checkpoint state:

- execution id;
- baseline contract SHA;
- baseline eligible count;
- baseline max assessment id;
- last verified assessment id;
- total rows compacted;
- batch number;
- last batch row count;
- SHA-256 of the ordered per-row receipts;
- started/updated timestamps;
- status: RUNNING / VERIFIED / FAILED.

A batch advances the checkpoint in the **same transaction** as its row updates.

Restart behavior:

- if a row is already compact and rehydrates/hash-checks correctly, it is idempotently treated as verified;
- rows still inline remain candidates;
- checkpoint never advances past a failed row/batch;
- a resumed run rechecks the baseline identity and continues with keyset `id > last_verified_assessment_id`.

No DELETE is involved.

## Batch verification receipt

Each committed batch should record at least:

- first/last assessment id;
- candidate count;
- compacted count;
- already-compact verified count;
- failures = 0;
- aggregate old-validator-SHA digest;
- aggregate post-validator-SHA digest;
- aggregate logical-evidence digest before/after;
- assertion-set reference digest.

Required equality:

```
old validator_sha256 digest = post validator_sha256 digest
old logical evidence digest = rehydrated post evidence digest
```

## Final verification

R5-E is complete only if:

- eligible inline rows = 0;
- compact historical rows = starting eligible count;
- every compact row resolves to exactly one valid assertion set;
- every compact row rehydrates successfully;
- all historical `validator_sha256` values equal their checkpointed pre-compaction values;
- no run status, blocked_reason, contract pin, curator receipt, gap proposal, or chunk timing changed.

R5-E does **not** delete inline history tables, runs, proposals, or assertion sets.

## Operational estimate

At 10,131 rows and batches of 100:

- **102 transactions**.
- Operational execution budget: approximately **10–20 minutes** if batches complete in the expected low-single-digit seconds.
- Reserve a **30-minute compaction window** for observation, checkpoint verification, and any fail-closed stop.
- This is an operational estimate, not a production benchmark. The first batch is the timing calibration point. If the first 100-row batch exceeds the chosen latency/lock threshold, stop and reduce to 50.

Because each batch commits independently, R5-E does not require one long transaction.

## VACUUM FULL plan — separate coordinated step

Do **not** run VACUUM FULL as part of R5-E.

Target table:
`programacion.input_family_assessments` only.

Why:

- that table/TOAST contains the space made reclaimable by removing inline assertion arrays;
- `input_validator_assertion_sets_v1` is not being deleted or compacted and should not be VACUUM FULL'ed;
- `VACUUM FULL` rewrites the table and rebuilds its indexes, so a separate REINDEX is unnecessary.

Expected physical result, based on the accepted simulation:

- assessment relation roughly **154.80 MiB -> 59.61 MiB**;
- reclaim roughly **95 MiB**;
- database may fall from about 572 MiB toward roughly **477 MiB**, subject to concurrent growth and relation overhead.

Lock semantics:

`VACUUM FULL programacion.input_family_assessments` takes an
**ACCESS EXCLUSIVE** lock for the rewrite. Reads and writes against that table are blocked for the duration.

Recommended coordinated maintenance window:

- allocate **15 minutes**;
- expected rewrite for the current ~156 MiB relation: roughly **2–8 minutes**, but treat 15 minutes as the safe operational window;
- stop/avoid Curator and Validator activity during the window;
- verify there is no active long transaction touching the table before starting;
- use a short `lock_timeout` so the maintenance does not wait indefinitely for the exclusive lock;
- if the lock cannot be obtained cleanly, cancel and reschedule rather than forcing sessions.

Command shape for the coordinated session:

```sql
set lock_timeout = '5s';
vacuum (full, analyze) programacion.input_family_assessments;
```

`VACUUM FULL` cannot run inside a transaction block.

Afterward read back:

- assessment relation total/heap/TOAST/index sizes;
- database size;
- row counts;
- compact count;
- rehydration/hash verification sample and aggregate;
- cron jobs 28/29 still active.

No REINDEX, DELETE, trigger disabling, or archival is part of this plan.

## R5-D first real validation watch

Do not provoke a validation solely for this watch.

Until R5-E begins, the first compact assessment row is by definition post-R5-D because compact_rows was zero immediately after the R5-D apply and after the rollback-only P2.

Ready-to-run query:

```sql
with compact as (
  select
    a.*, r.status run_status, r.blocked_reason, r.source_snapshot_sha256,
    case
      when a.validator_evidence ? 'analysis_revision'
        then 'fn_input_governance_validate_v2'
      when a.validator_evidence ? 'bootstrap_classifier_sha256'
        then 'fn_input_governance_bootstrap_validate_v1'
      else 'fn_input_governance_validator_rebind_v1'
    end writer,
    programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence) logical_evidence
  from programacion.input_family_assessments a
  join programacion.input_readiness_runs r on r.id=a.run_id
  where a.validator_evidence ? 'assertion_set_sha256'
),
checked as (
  select *,
    validator_sha256 = programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'curator_sha256',curator_sha256,
      'semantic_depth_sha256',semantic_depth_sha256,
      'source_snapshot_sha256',source_snapshot_sha256,
      'validator_outcome',validator_outcome,
      'validator_findings',validator_findings,
      'validator_evidence',logical_evidence,
      'validator_identity',validator_identity,
      'validator_assessed_at',validator_assessed_at
    )) as receipt_hash_ok
  from compact
)
select
  run_id,
  writer,
  min(validator_assessed_at) first_assessed_at,
  count(*) compact_rows,
  bool_and(jsonb_typeof(logical_evidence->'assertions')='array') rehydrate_has_assertions,
  bool_and(receipt_hash_ok) receipt_hash_ok,
  run_status,
  blocked_reason
from checked
group by run_id,writer,run_status,blocked_reason
order by first_assessed_at,run_id
limit 1;
```

Expected healthy first result:

- compact_rows > 0;
- `rehydrate_has_assertions=true`;
- `receipt_hash_ok=true`;
- run not BLOCKED and no new blocked_reason.

At this Draft's creation, this query returns no row: first real R5-D validation is still pending.
