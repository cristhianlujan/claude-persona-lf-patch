# S30 — EXECUTION_RECONCILIATION_LF candidate

This package classifies incomplete executions before any replay, close, backfill or repair.

## Frozen live finding — 2026-09-14

Supabase readback found 22 `IN_PROGRESS` executions with zero recorded steps across 12 operations.

Additional evidence:

- active effect-guard rows across the 22 executions: **0**;
- active leases: **0**;
- checkpoint sequence > 0: **0**;
- 13 executions belong to operations with no active `init_execution` topology;
- 9 belong to operations with active init, but only 2 of those operation topologies are structurally complete;
- those two historical rows still fail replay precheck because one lacks request identity and the other operation remains `OP_CANDIDATE`.

Therefore the frozen fleet has **0 automatic replay candidates**.

## Decision model

The read-only classifier preserves the reason instead of collapsing everything into `STALE` or `ABANDONED`:

- `CONFLICT_EFFECT_EVIDENCE`
- `CONFLICT_ACTIVE_LEASE`
- `CONFLICT_CHECKPOINT_WITH_ZERO_STEPS`
- `LEGACY_NO_INIT_TOPOLOGY`
- `OWNER_REVIEW_TOPOLOGY_INCOMPLETE`
- `OWNER_REVIEW_OPERATION_NOT_OPERATIONAL`
- `OWNER_REVIEW_REQUEST_IDENTITY_MISSING`
- `REPLAY_CANDIDATE_PRECHECK_ONLY`

`REPLAY_CANDIDATE_PRECHECK_ONLY` is not replay authorization. It only means static prerequisites exist; owner/currentness and business-effect review still precede mutation.

## Boundary with OPERATION_BOOTSTRAP_LF

`OPERATION_BOOTSTRAP_LF` prevents new zero-step reservations once an operation is admitted to the governed bootstrap policy.

`EXECUTION_RECONCILIATION_LF` handles historical fleet debt. It must never rewrite a legacy execution to pretend it was created under newer bootstrap semantics.

## Claim ceiling

Classification only. No Supabase mutation, status close, step backfill, lease manipulation, effect replay, runtime/production activation, Golden or merge-main authorization.
