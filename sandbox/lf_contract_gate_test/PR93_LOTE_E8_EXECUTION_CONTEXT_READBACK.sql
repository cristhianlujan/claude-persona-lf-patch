-- PR #93 / LOTE-E.9 execution-context snapshot. SELECT-only.
-- Execute immediately before the inherited primary readback in the same transaction.

select pg_catalog.jsonb_build_object(
  'effective_search_path',
    pg_catalog.current_setting('search_path')::pg_catalog.text,
  'search_path_is_pg_catalog',(
    pg_catalog.current_setting('search_path')
      OPERATOR(pg_catalog.=) 'pg_catalog'::pg_catalog.text
  ),
  'transaction_read_only',
    pg_catalog.current_setting('transaction_read_only')::pg_catalog.text,
  'transaction_is_read_only',(
    pg_catalog.current_setting('transaction_read_only')
      OPERATOR(pg_catalog.=) 'on'::pg_catalog.text
  ),
  'transaction_isolation',
    pg_catalog.current_setting('transaction_isolation')::pg_catalog.text,
  'transaction_isolation_valid',(
    pg_catalog.current_setting('transaction_isolation')
      OPERATOR(pg_catalog.=) 'repeatable read'::pg_catalog.text
    or pg_catalog.current_setting('transaction_isolation')
      OPERATOR(pg_catalog.=) 'serializable'::pg_catalog.text
  ),
  'server_version_num',
    pg_catalog.current_setting('server_version_num')::pg_catalog.text,
  'server_version',pg_catalog.version()::pg_catalog.text,
  'current_user',current_user::pg_catalog.text,
  'backend_pid',pg_catalog.pg_backend_pid()::pg_catalog.int4,
  'transaction_started_at',pg_catalog.transaction_timestamp(),
  'context_valid',(
    pg_catalog.current_setting('search_path')
      OPERATOR(pg_catalog.=) 'pg_catalog'::pg_catalog.text
    and pg_catalog.current_setting('transaction_read_only')
      OPERATOR(pg_catalog.=) 'on'::pg_catalog.text
    and (
      pg_catalog.current_setting('transaction_isolation')
        OPERATOR(pg_catalog.=) 'repeatable read'::pg_catalog.text
      or pg_catalog.current_setting('transaction_isolation')
        OPERATOR(pg_catalog.=) 'serializable'::pg_catalog.text
    )
  )
) as pr93_lote_e9_execution_context_readback;
