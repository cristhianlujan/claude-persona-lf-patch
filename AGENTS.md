# Agent Instructions

Follow [CLAUDE.md](CLAUDE.md), including **Mandatory database migration route — HARD BLOCK**, before any write. That rule applies to all agents and tools regardless of provider, runtime, or route.

Agents MUST NOT create or modify workflows that read `LF_SUPABASE_DB_PASSWORD` or any DB credential. All database migration changes go through PR + `ready-to-merge` + the authorized Merge Train. Unauthorized database writes are `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`.

Before naming a migration, apply **Migration naming** in [CLAUDE.md](CLAUDE.md): the Merge Train rejects migration names that are not classified in `sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py`.

Every database write starts at the Router (ACT-0001) with an `ACTUALIZACION_DB_LF` execution and ends in the Merge Train; see **Router first for every database write** in [CLAUDE.md](CLAUDE.md).

The Router (ACT-0001) is the authority: resolve with `lf_router_resolve_v1` before any database work, and treat read-only or permission denials as intentional (go to the Merge Train, never another route).
