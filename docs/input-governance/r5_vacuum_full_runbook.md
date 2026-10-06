# R5 final VACUUM FULL runbook — prepared, not authorized

R5-E historical compaction must finish and verify before this procedure.

## Preconditions

- Cristhian explicitly approves a maintenance window.
- R5-C, R5-D and all R5-E batches are complete.
- `input_family_assessments` has zero inline `assertions` for rows selected for compaction.
- Every compact row resolves to an existing content-addressed assertion set.
- Rehydrated logical evidence equals the pre-compaction receipt.
- Stored `validator_sha256` is unchanged.
- No migration-train job is running; use the same `lf-migrations` operational serialization.
- Application owners acknowledge an ACCESS EXCLUSIVE lock on `programacion.input_family_assessments`.

## Window

Recommended initial reservation: **15 minutes**, with an abort threshold agreed with Cristhian before starting. The current physical table is about 156 MiB, so the rewrite is small, but lock acquisition depends on concurrent traffic.

Do not start if long-running transactions touch Input Governance. Check `pg_stat_activity` and lock waiters immediately before the operation.

## Procedure

1. Capture pre-size:
   - heap
   - indexes
   - TOAST heap/total
   - total relation size.
2. Re-run R5 invariants and record counts.
3. Enter the maintenance window / stop new Input Governance writes.
4. Execute outside any migration transaction:
   `VACUUM (FULL, ANALYZE) programacion.input_family_assessments;`
5. Capture post-size and compare with the accepted estimate (~59.6 MiB combined assessments + assertion sets; actual result may differ with subsequent growth).
6. Re-run counts, assertion-set content hashes, rehydration samples/batches and application smoke checks.
7. Exit maintenance window.

## Failure handling

- If lock acquisition is not immediate within the owner-agreed threshold, cancel and reschedule; do not terminate unrelated sessions automatically.
- If VACUUM FULL itself fails, no logical R5 rollback is required: compaction rows remain valid; investigate storage maintenance separately.
- R6 remains out of scope.
