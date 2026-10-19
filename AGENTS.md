# Agent Instructions

Follow [CLAUDE.md](CLAUDE.md), including **Mandatory database migration route — HARD BLOCK**, before any write. That rule applies to all agents and tools regardless of provider, runtime, or route.

Agents MUST NOT create or modify workflows that read `LF_SUPABASE_DB_PASSWORD` or any DB credential. All database migration changes go through PR + `ready-to-merge` + the authorized Merge Train. Unauthorized database writes are `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`.

Before naming a migration, apply **Migration naming** in [CLAUDE.md](CLAUDE.md): the Merge Train rejects migration names that are not classified in `sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py`.

Merge every PR to `main`, with or without migrations, only through the Train queue (`ready-to-merge`); never merge directly while a Train run is in flight. See **One merge path to `main`: the Train queue** in [CLAUDE.md](CLAUDE.md).

Every database write starts at the Router (ACT-0001) with an `ACTUALIZACION_DB_LF` execution and ends in the Merge Train; see **Router first for every database write** in [CLAUDE.md](CLAUDE.md).

The Router (ACT-0001) is the authority for database writes: resolve with `lf_router_resolve_v1` before each write and follow `ACTUALIZACION_DB_LF` through the Merge Train. Read-only database inspection through the Supabase RO connector is outside Router routing; limit it to the authorized inspection scope and do not use it to write.

PASE runs in shadow mode. Read **PASE (shadow mode), stale bases and activation hold** in [CLAUDE.md](CLAUDE.md) before acting on a red PASE result; never make PASE required, edit the `protect-main` ruleset, or add PASE to the Train pre-apply checks without the owner's decision.
