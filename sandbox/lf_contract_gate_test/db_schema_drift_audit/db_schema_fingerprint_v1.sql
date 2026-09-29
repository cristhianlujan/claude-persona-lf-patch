\set ON_ERROR_STOP on
begin read only;

with custom_namespaces as (
  select n.oid, n.nspname
  from pg_namespace n
  where n.nspname !~ '^(pg_|information_schema$|_analytics$|_realtime$|_supavisor$|auth$|etl$|extensions$|pgbouncer$|realtime$|storage$|supabase_functions$|supabase_migrations$|cron$|dbdev$|graphql$|graphql_public$|net$|pgmq$|pgsodium$|pgsodium_masks$|pgtle$|repack$|tiger$|tiger_data$|timescaledb_|_timescaledb_|topology$|vault$)'
), fingerprint_rows as (
  select
    'SCHEMA'::text as kind,
    quote_ident(n.nspname) as identity,
    jsonb_build_object('name', n.nspname) as definition
  from custom_namespaces n

  union all

  select
    'RELATION',
    format('%I.%I', n.nspname, c.relname),
    jsonb_build_object(
      'relkind', c.relkind,
      'rowsecurity', c.relrowsecurity,
      'forcerowsecurity', c.relforcerowsecurity,
      'persistence', c.relpersistence
    )
  from pg_class c
  join custom_namespaces n on n.oid = c.relnamespace
  where c.relkind in ('r','p','v','m','f','S')

  union all

  select
    'COLUMN',
    format('%I.%I.%I', n.nspname, c.relname, a.attname),
    jsonb_build_object(
      'ordinal', a.attnum,
      'type', format_type(a.atttypid, a.atttypmod),
      'not_null', a.attnotnull,
      'identity', a.attidentity,
      'generated', a.attgenerated,
      'default', pg_get_expr(ad.adbin, ad.adrelid)
    )
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join custom_namespaces n on n.oid = c.relnamespace
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where a.attnum > 0 and not a.attisdropped and c.relkind in ('r','p','v','m','f')

  union all

  select
    'CONSTRAINT',
    format('%I.%I.%I', n.nspname, c.relname, con.conname),
    jsonb_build_object(
      'type', con.contype,
      'definition', pg_get_constraintdef(con.oid, true),
      'validated', con.convalidated,
      'deferrable', con.condeferrable,
      'deferred', con.condeferred
    )
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join custom_namespaces n on n.oid = c.relnamespace

  union all

  select
    'INDEX',
    format('%I.%I', n.nspname, idx.relname),
    jsonb_build_object(
      'definition', pg_get_indexdef(i.indexrelid),
      'valid', i.indisvalid,
      'unique', i.indisunique,
      'primary', i.indisprimary
    )
  from pg_index i
  join pg_class idx on idx.oid = i.indexrelid
  join pg_class tbl on tbl.oid = i.indrelid
  join custom_namespaces n on n.oid = tbl.relnamespace

  union all

  select
    'VIEW_DEFINITION',
    format('%I.%I', n.nspname, c.relname),
    jsonb_build_object('definition', pg_get_viewdef(c.oid, true))
  from pg_class c
  join custom_namespaces n on n.oid = c.relnamespace
  where c.relkind in ('v','m')

  union all

  select
    'FUNCTION',
    format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
    jsonb_build_object(
      'kind', p.prokind,
      'result', pg_get_function_result(p.oid),
      'language', l.lanname,
      'volatility', p.provolatile,
      'security_definer', p.prosecdef,
      'definition', pg_get_functiondef(p.oid)
    )
  from pg_proc p
  join custom_namespaces n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  where p.prokind in ('f','p')

  union all

  select
    'TRIGGER',
    format('%I.%I.%I', n.nspname, c.relname, t.tgname),
    jsonb_build_object('definition', pg_get_triggerdef(t.oid, true), 'enabled', t.tgenabled)
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join custom_namespaces n on n.oid = c.relnamespace
  where not t.tgisinternal

  union all

  select
    'POLICY',
    format('%I.%I.%I', n.nspname, c.relname, p.polname),
    jsonb_build_object(
      'permissive', p.polpermissive,
      'command', p.polcmd,
      'roles', p.polroles::text,
      'using', pg_get_expr(p.polqual, p.polrelid),
      'check', pg_get_expr(p.polwithcheck, p.polrelid)
    )
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join custom_namespaces n on n.oid = c.relnamespace

  union all

  select
    'ENUM',
    format('%I.%I.%s', n.nspname, t.typname, e.enumsortorder),
    jsonb_build_object('label', e.enumlabel)
  from pg_enum e
  join pg_type t on t.oid = e.enumtypid
  join custom_namespaces n on n.oid = t.typnamespace

  union all

  select
    'SEQUENCE',
    format('%I.%I', n.nspname, c.relname),
    jsonb_build_object(
      'type', format_type(s.seqtypid, null),
      'start', s.seqstart,
      'increment', s.seqincrement,
      'min', s.seqmin,
      'max', s.seqmax,
      'cache', s.seqcache,
      'cycle', s.seqcycle
    )
  from pg_sequence s
  join pg_class c on c.oid = s.seqrelid
  join custom_namespaces n on n.oid = c.relnamespace
)
select jsonb_build_object(
  'kind', kind,
  'identity', identity,
  'definition', definition
)::text
from fingerprint_rows
order by kind, identity;

commit;
