# Agent Instructions

Follow [CLAUDE.md](CLAUDE.md), including **Mandatory database migration route — HARD BLOCK**, before any write. That rule applies to all agents and tools regardless of provider, runtime, or route.

Agents MUST NOT create or modify workflows that read `LF_SUPABASE_DB_PASSWORD` or any DB credential. All database migration changes go through PR + `ready-to-merge` + the authorized Merge Train. Unauthorized database writes are `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`.
