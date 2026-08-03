-- PR #93 / LOTE-E.8 dependency and execution-context preflight. SELECT-only.
-- Execute before PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql.

with dependencies as (
  select
    pg_catalog.to_regprocedure(
      'extensions.digest(pg_catalog.bytea,pg_catalog.text)'
    ) is not null as primary_digest_available,
    pg_catalog.to_regprocedure(
      'pg_catalog.sha256(pg_catalog.bytea)'
    ) is not null as core_sha256_available,
    pg_catalog.to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
      is not null as binder_available,
    pg_catalog.to_regrole('lf_governance_owner_v3') is not null
      as governance_owner_available,
    pg_catalog.to_regclass('private.lf_gate_test_runs_v3') is not null
      as gate_table_available
),
execution_context as (
  select
    pg_catalog.current_setting('search_path')::pg_catalog.text
      as effective_search_path,
    pg_catalog.current_setting('transaction_read_only')::pg_catalog.text
      as transaction_read_only,
    pg_catalog.current_setting('transaction_isolation')::pg_catalog.text
      as transaction_isolation,
    pg_catalog.current_setting('server_version_num')::pg_catalog.text
      as server_version_num,
    pg_catalog.version()::pg_catalog.text as server_version,
    current_user::pg_catalog.text as current_user_name,
    pg_catalog.pg_backend_pid()::pg_catalog.int4 as backend_pid,
    pg_catalog.transaction_timestamp() as transaction_started_at,
    (pg_catalog.current_setting('search_path')
      OPERATOR(pg_catalog.=) 'pg_catalog'::pg_catalog.text)
      as search_path_is_pg_catalog,
    (pg_catalog.current_setting('transaction_read_only')
      OPERATOR(pg_catalog.=) 'on'::pg_catalog.text)
      as transaction_is_read_only
)
select pg_catalog.jsonb_build_object(
  'primary_digest_available',dependencies.primary_digest_available,
  'core_sha256_available',dependencies.core_sha256_available,
  'binder_available',dependencies.binder_available,
  'governance_owner_available',dependencies.governance_owner_available,
  'gate_table_available',dependencies.gate_table_available,
  'execution_context',pg_catalog.jsonb_build_object(
    'effective_search_path',execution_context.effective_search_path,
    'search_path_is_pg_catalog',execution_context.search_path_is_pg_catalog,
    'transaction_read_only',execution_context.transaction_read_only,
    'transaction_is_read_only',execution_context.transaction_is_read_only,
    'transaction_isolation',execution_context.transaction_isolation,
    'server_version_num',execution_context.server_version_num,
    'server_version',execution_context.server_version,
    'current_user',execution_context.current_user_name,
    'backend_pid',execution_context.backend_pid,
    'transaction_started_at',execution_context.transaction_started_at
  ),
  'all_present',(
    dependencies.primary_digest_available
    and dependencies.core_sha256_available
    and dependencies.binder_available
    and dependencies.governance_owner_available
    and dependencies.gate_table_available
  ),
  'preflight_ready',(
    dependencies.primary_digest_available
    and dependencies.core_sha256_available
    and dependencies.binder_available
    and dependencies.governance_owner_available
    and dependencies.gate_table_available
    and execution_context.search_path_is_pg_catalog
    and execution_context.transaction_is_read_only
  )
) as pr93_lote_e8_dependency_preflight
from dependencies
cross join execution_context;
