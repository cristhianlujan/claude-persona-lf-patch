# IG M10.13 — CP2 final material current-main parity

This is a no-migration, read-only evidence request for the existing `lf-migration-merge-train` M10.13 full-state parity step. It follows the material PASS at Train 39705974170 and exact live Git↔Supabase Edge content readback (six of six files) against `main` at `8052deeee06d4cc8f3ba31cbd561e3b308047ae7`.

Expected evidence: same official runner, current `main` exact SHA, all post-baseline Git and migration-ledger records, pinned historical exceptions, the four Git blob pointers and full read-only parity PASS. Do not replay DDL, mutate the ledger, deploy Edge Functions, activate production, or change per-PR governance. Do not mark the checkpoint `DONE` without verified material evidence and a canonical transition.
