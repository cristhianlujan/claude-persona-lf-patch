-- PR #93 / LOTE-E.10 correlation probe. SELECT-only.
-- Execute three times inside T1: before snapshot, before preflight and before addendum.

with raw_context as (
  select
    pg_catalog.current_database()::pg_catalog.text as database_name,
    (
      select d.oid::pg_catalog.text
      from pg_catalog.pg_database d
      where d.datname OPERATOR(pg_catalog.=) pg_catalog.current_database()
    ) as database_oid,
    pg_catalog.current_setting('server_version_num')::pg_catalog.text
      as server_version_num,
    pg_catalog.version()::pg_catalog.text as server_version,
    pg_catalog.pg_postmaster_start_time() as postmaster_started_at,
    pg_catalog.inet_server_addr()::pg_catalog.text as server_address,
    pg_catalog.inet_server_port()::pg_catalog.text as server_port,
    current_user::pg_catalog.text as current_user_name,
    pg_catalog.pg_backend_pid()::pg_catalog.int4 as backend_pid,
    pg_catalog.transaction_timestamp() as transaction_started_at,
    pg_catalog.current_setting('search_path')::pg_catalog.text
      as effective_search_path,
    pg_catalog.current_setting('transaction_read_only')::pg_catalog.text
      as transaction_read_only,
    pg_catalog.current_setting('transaction_isolation')::pg_catalog.text
      as transaction_isolation,
    (
      pg_catalog.current_setting('search_path')
        OPERATOR(pg_catalog.=) 'pg_catalog'::pg_catalog.text
    ) as search_path_is_pg_catalog,
    (
      pg_catalog.current_setting('transaction_read_only')
        OPERATOR(pg_catalog.=) 'on'::pg_catalog.text
    ) as transaction_is_read_only,
    (
      pg_catalog.current_setting('transaction_isolation')
        OPERATOR(pg_catalog.=) 'repeatable read'::pg_catalog.text
      or pg_catalog.current_setting('transaction_isolation')
        OPERATOR(pg_catalog.=) 'serializable'::pg_catalog.text
    ) as transaction_isolation_valid,
    (
      pg_catalog.to_regprocedure('pg_catalog.pg_control_system()') is not null
      and pg_catalog.has_function_privilege(
        current_user,
        'pg_catalog.pg_control_system()',
        'EXECUTE'
      )
    ) as system_identifier_available
),
cluster_context as (
  select
    raw_context.*,
    case
      when raw_context.system_identifier_available
        then (pg_catalog.pg_control_system()).system_identifier::pg_catalog.text
      else null::pg_catalog.text
    end as system_identifier
  from raw_context
),
fingerprints as (
  select
    cluster_context.*,
    pg_catalog.encode(
      pg_catalog.sha256(
        pg_catalog.convert_to(
          pg_catalog.concat_ws(
            '|'::pg_catalog.text,
            coalesce(
              cluster_context.system_identifier,
              'SYSTEM_IDENTIFIER_UNAVAILABLE'::pg_catalog.text
            ),
            cluster_context.database_name,
            cluster_context.database_oid,
            cluster_context.server_version_num,
            cluster_context.postmaster_started_at::pg_catalog.text,
            coalesce(
              cluster_context.server_address,
              'UNIX_SOCKET'::pg_catalog.text
            ),
            coalesce(cluster_context.server_port, ''::pg_catalog.text)
          ),
          'UTF8'
        )
      ),
      'hex'
    ) as runtime_cluster_fingerprint
  from cluster_context
),
correlated as (
  select
    fingerprints.*,
    pg_catalog.encode(
      pg_catalog.sha256(
        pg_catalog.convert_to(
          pg_catalog.concat_ws(
            '|'::pg_catalog.text,
            fingerprints.runtime_cluster_fingerprint,
            fingerprints.backend_pid::pg_catalog.text,
            fingerprints.transaction_started_at::pg_catalog.text
          ),
          'UTF8'
        )
      ),
      'hex'
    ) as transaction_correlation_id
  from fingerprints
)
select pg_catalog.jsonb_build_object(
  'database_name',correlated.database_name,
  'database_oid',correlated.database_oid,
  'server_version_num',correlated.server_version_num,
  'server_version',correlated.server_version,
  'postmaster_started_at',correlated.postmaster_started_at,
  'server_address',correlated.server_address,
  'server_port',correlated.server_port,
  'current_user',correlated.current_user_name,
  'system_identifier_available',correlated.system_identifier_available,
  'system_identifier',correlated.system_identifier,
  'runtime_cluster_fingerprint',correlated.runtime_cluster_fingerprint,
  'backend_pid',correlated.backend_pid,
  'transaction_started_at',correlated.transaction_started_at,
  'transaction_correlation_id',correlated.transaction_correlation_id,
  'effective_search_path',correlated.effective_search_path,
  'transaction_read_only',correlated.transaction_read_only,
  'transaction_isolation',correlated.transaction_isolation,
  'context_valid',(
    correlated.search_path_is_pg_catalog
    and correlated.transaction_is_read_only
    and correlated.transaction_isolation_valid
  )
) as pr93_lote_e10_correlation_readback
from correlated;
