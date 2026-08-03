-- PR #93 / LOTE-E.11 optional system-identifier probe. SELECT-only.
-- Execute only after the safe capability check reports true.
-- This file is intentionally not part of the mandatory degraded path.

select pg_catalog.jsonb_build_object(
  'system_identifier',
    (pg_catalog.pg_control_system()).system_identifier::pg_catalog.text,
  'cluster_identity_strength','SYSTEM_IDENTIFIER'::pg_catalog.text,
  'database_name',pg_catalog.current_database()::pg_catalog.text,
  'server_version_num',
    pg_catalog.current_setting('server_version_num')::pg_catalog.text,
  'postmaster_started_at',pg_catalog.pg_postmaster_start_time(),
  'backend_pid',pg_catalog.pg_backend_pid()::pg_catalog.int4,
  'transaction_started_at',pg_catalog.transaction_timestamp(),
  'effective_search_path',
    pg_catalog.current_setting('search_path')::pg_catalog.text,
  'transaction_read_only',
    pg_catalog.current_setting('transaction_read_only')::pg_catalog.text,
  'transaction_isolation',
    pg_catalog.current_setting('transaction_isolation')::pg_catalog.text
) as pr93_lote_e11_system_identifier_probe;
