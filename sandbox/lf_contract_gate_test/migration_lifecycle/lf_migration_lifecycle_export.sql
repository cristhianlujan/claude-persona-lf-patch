\set ON_ERROR_STOP on

-- Hydrate a bounded migration-ledger slice for MIGRATION_LIFECYCLE_LF.
-- Required psql variables:
--   owner_prefix  e.g. s30_
--   min_version   empty or YYYYMMDDHHMMSS
--   max_version   empty or YYYYMMDDHHMMSS
--
-- Output: exactly one JSON array suitable for lf_migration_lifecycle_reconcile.py.
-- This is read-only. It neither changes DDL nor mutates schema_migrations.

with scoped as (
  select
    version,
    name,
    cardinality(statements) as statement_count,
    array_to_string(statements, E'\n') as source_sql
  from supabase_migrations.schema_migrations
  where left(name, length(:'owner_prefix')) = :'owner_prefix'
    and (nullif(:'min_version', '') is null or version >= :'min_version')
    and (nullif(:'max_version', '') is null or version <= :'max_version')
), hydrated as (
  select
    version,
    name,
    statement_count,
    replace(encode(convert_to(source_sql, 'UTF8'), 'base64'), E'\n', '') as source_base64,
    encode(
      extensions.digest(
        convert_to('blob ' || octet_length(convert_to(source_sql, 'UTF8'))::text, 'UTF8')
        || decode('00', 'hex')
        || convert_to(source_sql, 'UTF8'),
        'sha1'
      ),
      'hex'
    ) as source_git_blob_sha1,
    encode(extensions.digest(convert_to(source_sql, 'UTF8'), 'sha256'), 'hex') as source_sha256
  from scoped
)
select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'version', version,
      'name', name,
      'statement_count', statement_count,
      'source_base64', source_base64,
      'source_git_blob_sha1', source_git_blob_sha1,
      'source_sha256', source_sha256
    )
    order by version
  ),
  '[]'::jsonb
)::text
from hydrated;
