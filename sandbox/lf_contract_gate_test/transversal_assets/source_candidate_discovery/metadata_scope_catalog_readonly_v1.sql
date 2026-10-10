-- D1 metadata scope compiler, READ-ONLY CANDIDATE (not deployed).
-- Populate two bind parameters only from an AUTHORIZED Supabase policy/scope
-- resolver, never from GPT or a spreadsheet.
--   allowed_schemas: %(allowed_schemas)s::text[]
--   catalog_limit:   %(catalog_limit)s::integer
-- This reads pg_catalog metadata ONLY. A source_ref is a candidate locator,
-- not a source-authority binding and not permission to query its rows.

WITH authorized AS (
  SELECT %(allowed_schemas)s::text[] AS allowed_schemas,
         %(catalog_limit)s::integer AS catalog_limit
), guarded AS (
  SELECT * FROM authorized
  WHERE cardinality(allowed_schemas) BETWEEN 1 AND 16
    AND catalog_limit BETWEEN 1 AND 2000
), scope_catalog AS (
  SELECT c.oid,n.nspname,c.relname,c.relkind,
         count(*) OVER() AS objects_in_scope
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN guarded g
  WHERE n.nspname=ANY(g.allowed_schemas)
    AND c.relkind IN ('r','p','v') AND NOT c.relispartition
), objects AS (
  SELECT
    'supabase://catalog/'||s.nspname||'/'||s.relname AS source_ref,
    replace(s.relname,'_',' ') AS label,
    coalesce(obj_description(s.oid,'pg_class'),'') AS description,
    coalesce((
      SELECT array_agg(a.attname ORDER BY a.attnum)
      FROM pg_attribute a
      WHERE a.attrelid=s.oid AND a.attnum>0 AND NOT a.attisdropped
    ),array[]::text[]) AS columns,
    coalesce((
      SELECT array_agg(DISTINCT 'supabase://catalog/'||t.nspname||'/'||t.relname)
      FROM pg_constraint f
      JOIN scope_catalog t
        ON t.oid=CASE WHEN f.conrelid=s.oid THEN f.confrelid ELSE f.conrelid END
      WHERE f.contype='f'
        AND (f.conrelid=s.oid OR f.confrelid=s.oid)
        AND t.oid<>s.oid
    ),array[]::text[]) AS relation_refs,
    array[]::text[] AS aliases,
    s.relkind AS source_kind,
    s.objects_in_scope,
    false AS authority_verified,
    false AS data_access_granted
  FROM scope_catalog s
)
SELECT source_ref,label,description,columns,relation_refs,aliases,source_kind,
       objects_in_scope,authority_verified,data_access_granted
FROM objects
ORDER BY source_ref
LIMIT (SELECT catalog_limit FROM guarded);

-- If objects_in_scope exceeds delivered source count, scope is incomplete.
-- Even if complete, exhaustion of *discovery* requires an independent Supabase
-- authority receipt and must never be inferred from an empty response alone.
-- Actual lookup must use authorized tools/RLS and a separate read admission.
