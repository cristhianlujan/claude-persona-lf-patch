# MIGRATION_PERSIST_VERIFY_REPAIR_INTEGRATION_V1

`MIGRATION_SOURCE_PARITY` must not own an independent Git writer. When parity detects a deterministic source-only repair, it must produce an exact repair request that is consumed by the transversal migration persist/verify procedure owned by `ACTUALIZACION_DB_LF + DB_WRITE_TRANSPORT`.

For an already-applied migration, the procedure enters with `supabase.applied=true`, `supabase.readback=true`, and `ddl_replayed=false`. It must not reapply DDL. The only material repair is to persist the exact historical source in Git through an authorized Git writer, perform Git readback, then rerun canonical parity. Closure is allowed only when the same request identity reaches `CONSISTENT`.

Pilot proof target: `20260923013150_restrict_profile_semantic_judge_trust_validator_acl`, originally applied by superseded PR #1011 and currently repaired source-only by candidate PR #1018. The proof must preserve exact source bytes and no DDL replay.
