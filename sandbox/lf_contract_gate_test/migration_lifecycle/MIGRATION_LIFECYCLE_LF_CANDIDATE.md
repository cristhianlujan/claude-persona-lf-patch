# MIGRATION_LIFECYCLE_LF — candidate transversal core

Purpose: turn migration source/ledger drift from an operator procedure into a fail-closed reusable capability.

## Normal path

1. Freeze exact source/version/name in Git.
2. Validate source before remote apply.
3. Apply the same source through an exact-version governed channel.
4. Read back ledger version/name/content representation/cardinality.
5. Require exact-head CI and repository↔ledger parity.
6. Emit a receipt. Merge/production activation remain separate gates.

## Exceptional DB-first recovery

Recovery is not the normal deployment path. The reconciler may materialize remote-only source into the worktree only when all of the following are true:

- ownership is explicitly scoped (`owner_prefix` + optional version window),
- ledger source is hydrated,
- ledger statement cardinality is exactly one,
- exact Git blob SHA-1 proof is present and matches the recovered bytes,
- optional SHA-256 proof also matches,
- the target file does not already exist.

Unknown/multi-statement transport remains blocked. The candidate never replays DDL, never writes `main`, never opens/merges a PR, and never relaxes migration classification.

## Composition target

S30 owns these invariants. S31 should productize the candidate as a versioned capability and compose it with `DESTINATION_RESOLUTION_LF`, the future governed repository-change capability, CI evidence/currentness, and execution receipts.

The current 2026-09-14 S30 migration drift is the first intended real case, but no version list is hard-coded in the reconciler.
