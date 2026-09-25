# PR1_TEST_MATRIX_V1

- Git not durable -> BLOCK_GIT_SOURCE_NOT_DURABLE.
- Git durable, Supabase not applied -> READY_TO_APPLY.
- Supabase applied but readback missing -> BLOCK_SUPABASE_READBACK_MISSING.
- Ledger identity mismatch -> fail closed.
- Parity not PASS -> BLOCK_DUAL_SURFACE_PARITY_NOT_PASS.
- Git durable + exact ledger readback + parity PASS -> CONSISTENT.
- Historical source-only repair uses existing Supabase apply/readback and must keep `ddl_replayed=false`.
