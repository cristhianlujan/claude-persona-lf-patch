# Proposal: PSQL exact apply as the Train's official path

Status: proposal only; do not merge or apply until the owner chooses the contract.

## Proposed receipt semantics

A successful source-first exact SQL apply reports `code=EXACT_APPLIED`, `apply_path=PSQL_EXACT`, and `fallback_used=false`. `executor=PSQL_EXACT` identifies the material writer. The exact migration bytes and ledger row remain committed together, followed by an exact ledger readback. The existing `train:<version>:<blob>` reservation key remains the execution idempotency boundary.

The Supabase CLI dry-run remains a nonblocking diagnostic. Its numeric exit code and filtered final output are recorded, but its pending-set result does not select or block application. A Postgres `ERROR:` stops after the single exact apply attempt; no retry occurs. A connection failure also stops with a failure receipt and no second writer attempt.

The receipt reader maps historical `FALLBACK_APPLIED_EXACT` plus `fallback_used=true` to `apply_path=PSQL_EXACT` for display, while retaining the original fields. Historical CLI-primary receipts retain their CLI executor identity.

## Required updates before production merge

- **PASE-F07-X01 receipt contract:** define `EXACT_APPLIED`, `apply_path=PSQL_EXACT`, diagnostic fields, and compatibility rules for legacy `FALLBACK_APPLIED_EXACT` receipts.
- **Terminal Train receipt writer:** add `apply_path`, `dry_run_exit_code`, and `dry_run_tail` from the guarded apply receipt to the terminal event. The deployed V1 writer currently projects a fixed subset, so this needs a governed schema migration.
- **DB_WRITE_TRANSPORT:** declare `PSQL_EXACT` as the official migration executor, retain the existing CLI dry-run as diagnostic only, and specify no-retry behavior for both Postgres and connection failures.
- **CLAUDE.md / AGENTS.md:** retain the Train-only write route, clarify that psql is used only inside the Train's governed exact-apply wrapper, and remove descriptions that imply `supabase db push` is the authoritative apply path.
- **`docs/migrations/POLICY_MIGRATION_APPLY_V1.md`:** replace CLI-primary/fallback wording with exact PSQL as primary and CLI diagnostic semantics.
- **Merge Train workflow and checks:** assert canonical fields and exact ledger identity; remove any gate that treats dry-run output as proof of pending-set correctness. Keep exact-head, write-ahead, parity, readback, and merge ordering.
- **F3 drift monitor:** accept both historical and new receipt shapes; treat `PSQL_EXACT` as the normal path and keep legacy `fallback_used` interpretable. The current repository snapshot did not contain an identifiable F3 monitor source file, so its owner/path must be supplied before changing it.
- **Tests:** cover exact apply success, already-applied readback, Postgres error with no retry, connection error with no retry, legacy receipt normalization, and `REPLAY` under the unchanged `train:<version>:<blob>` key.

## Recommendation on dry-run

Keep it as a nonblocking diagnostic for now. It preserves visibility into how CLI history reconciliation evolves without putting the known-divergent ledger ahead of the exact source operation. Removal can be reconsidered after the drift monitor and receipt consumers no longer depend on the diagnostic.
