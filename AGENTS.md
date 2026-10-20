# Agent Instructions

Follow [CLAUDE.md](CLAUDE.md), including **Mandatory database migration route — HARD BLOCK**, before any write. That rule applies to all agents and tools regardless of provider, runtime, or route.

Agents MUST NOT create or modify workflows that read `LF_SUPABASE_DB_PASSWORD` or any DB credential. All database migration changes go through PR + `ready-to-merge` + the authorized Merge Train. Unauthorized database writes are `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`.

Before naming a migration, apply **Migration naming** in [CLAUDE.md](CLAUDE.md): the Merge Train rejects migration names that are not classified in `sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py`.

Merge every PR to `main`, with or without migrations, only through the Train queue (`ready-to-merge`); never merge directly while a Train run is in flight. See **One merge path to `main`: the Train queue** in [CLAUDE.md](CLAUDE.md).

Every database write starts at the Router (ACT-0001) with an `ACTUALIZACION_DB_LF` execution and ends in the Merge Train; see **Router first for every database write** in [CLAUDE.md](CLAUDE.md).

The Router (ACT-0001) is the authority for database writes: resolve with `lf_router_resolve_v1` before each write and follow `ACTUALIZACION_DB_LF` through the Merge Train. Read-only database inspection through the Supabase RO connector is outside Router routing; limit it to the authorized inspection scope and do not use it to write.

PASE is a required check (activated 2026-10-20, #2947). Read **PASE required check, stale bases and classification** in [CLAUDE.md](CLAUDE.md) before acting on a red PASE result; changes to the `protect-main` ruleset or Train pre-apply checks require the owner's decision and must preserve their parity in the same window.
Before every push to a PR, follow **Classify before you push (changeset manifest)** in [CLAUDE.md](CLAUDE.md#classify-before-you-push-changeset-manifest); include a manifest from the first commit only when paths lack a registered family.
