# MIGRATION_PERSIST_VERIFY_V1

Extends existing DB_WRITE_TRANSPORT/ACTUALIZACION_DB_LF with a deterministic dual-surface state gate. No new authority, table, operation, runtime, merge, or live DB apply. Supports new migrations and source-only historical repair without DDL replay. Closure requires exact Git source readback + exact Supabase ledger readback + canonical MIGRATION_SOURCE_PARITY PASS.
