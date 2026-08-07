# PR93 V7 · Static Resume from Applied-4 State

Purpose: resume the V7 migration chain from the exact LF_SUPABASE_SANDBOX state where the first four V7 source migrations are already committed.

## Required starting state

Exactly these four migration versions must already exist in `supabase_migrations.schema_migrations` with their immutable Git blob idempotency keys:

- `20260801175950`
- `20260801175955`
- `20260801180000`
- `20260801180005`

The generated SQL package performs this preflight before any write. The preflight was independently executed against `LF_SUPABASE_SANDBOX` and returned `PR93_V7_STATIC_RESUME_PREFLIGHT_PASS`.

## Forward-only correction

`20260801180005` remains immutable applied history. New migration `20260801180010_prepare_quarantine_owner_context.sql` restores only the temporary governance owner context required by PostgreSQL for the subsequent quarantine-table ownership transfer. `20260801180150_trusted_v7_readback_grants.sql` removes the temporary schema `CREATE` privilege afterward.

## Package

- SQL: `PR93_V7_STATIC_RESUME_FROM_4.sql`
- SHA-256: see `PR93_V7_STATIC_RESUME_FROM_4.sha256.txt`
- Execution model: literal SQL, no dynamic source download, no global transaction.
- Each pending migration and its ledger row commit atomically in the same transaction.
- Final source readback expects 18 V7 versions total: the original 17 plus forward-only `20260801180010`.

## Limits

This package does not declare runtime PASS, production readiness, merge authorization, deployment authorization, or production status.
