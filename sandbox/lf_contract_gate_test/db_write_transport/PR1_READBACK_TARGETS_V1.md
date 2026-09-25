# PR1_READBACK_TARGETS_V1

Readback must bind one execution to:

- Git target path.
- Git head SHA.
- Git blob SHA1.
- source SHA256.
- Supabase ledger version.
- Supabase ledger name.
- canonical parity status.

No closure is valid unless all identities refer to the same migration and `lf_migration_persist_verify.py` returns `CONSISTENT`.
