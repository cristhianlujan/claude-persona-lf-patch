-- PR #93 / LOTE-E.12 optional system-identifier probe. SELECT-only.
-- Execute only after the safe capability check reports true.
-- This file is intentionally not part of the mandatory degraded path.

with cluster_identity as (
  select
    (pg_catalog.pg_control_system()).system_identifier::pg_catalog.text
      as system_identifier,
    pg_catalog.current_database()::pg_catalog.text as database_name,
    (
      select d.oid::pg_catalog.text
      from pg_catalog.pg_database d
      where d.datname OPERATOR(pg_catalog.=) pg_catalog.current_database()
    ) as database_oid,
    pg_catalog.current_setting('server_version_num')::pg_catalog.text
      as server_version_num,
    pg_catalog.pg_postmaster_start_time() as postmaster_started_at,
    pg_catalog.inet_server_addr()::pg_catalog.text as server_address,
    pg_catalog.inet_server_port()::pg_catalog.text as server_port,
    pg_catalog.pg_backend_pid()::pg_catalog.int4 as backend_pid,
    pg_catalog.transaction_timestamp() as transaction_started_at,
    pg_catalog.current_setting('search_path')::pg_catalog.text
      as effective_search_path,
    pg_catalog.current_setting('transaction_read_only')::pg_catalog.text
      as transaction_read_only,
    pg_catalog.current_setting('transaction_isolation')::pg_catalog.text
      as transaction_isolation
),
fingerprints as (
  select
    cluster_identity.*,
    pg_catalog.encode(
      pg_catalog.sha256(
        pg_catalog.convert_to(
          pg_catalog.concat_ws(
            '|'::pg_catalog.text,
            'SYSTEM_IDENTIFIER_OPTIONAL_NOT_USED'::pg_catalog.text,
            cluster_identity.database_name,
            cluster_identity.database_oid,
            cluster_identity.server_version_num,
            cluster_identity.postmaster_started_at::pg_catalog.text,
            coalesce(
              cluster_identity.server_address,
              'UNIX_SOCKET'::pg_catalog.text
            ),
            coalesce(cluster_identity.server_port, ''::pg_catalog.text)
          ),
          'UTF8'
        )
      ),
      'hex'
    ) as runtime_cluster_fingerprint
  from cluster_identity
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
    ) as transaction_correlation_id,
    pg_catalog.encode(
      pg_catalog.sha256(
        pg_catalog.convert_to(
          pg_catalog.concat_ws(
            '|'::pg_catalog.text,
            fingerprints.system_identifier,
            fingerprints.runtime_cluster_fingerprint,
            fingerprints.backend_pid::pg_catalog.text,
            fingerprints.transaction_started_at::pg_catalog.text
          ),
          'UTF8'
        )
      ),
      'hex'
    ) as system_identifier_binding
  from fingerprints
)
select pg_catalog.jsonb_build_object(
  'system_identifier',correlated.system_identifier,
  'cluster_identity_strength','SYSTEM_IDENTIFIER'::pg_catalog.text,
  'system_identifier_binding',correlated.system_identifier_binding,
  'runtime_cluster_fingerprint',correlated.runtime_cluster_fingerprint,
  'transaction_correlation_id',correlated.transaction_correlation_id,
  'database_name',correlated.database_name,
  'database_oid',correlated.database_oid,
  'server_version_num',correlated.server_version_num,
  'postmaster_started_at',correlated.postmaster_started_at,
  'server_address',correlated.server_address,
  'server_port',correlated.server_port,
  'backend_pid',correlated.backend_pid,
  'transaction_started_at',correlated.transaction_started_at,
  'effective_search_path',correlated.effective_search_path,
  'transaction_read_only',correlated.transaction_read_only,
  'transaction_isolation',correlated.transaction_isolation
) as pr93_lote_e12_system_identifier_probe
from correlated;
