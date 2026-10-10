-- D1-B (candidate, NO MIGRATION): read-only metadata discovery query.
-- Execute only from a trusted server adapter after resolving allowed_schemas,
-- ranking weights, query budget and policy revision from canonical Supabase.
-- GPT MUST NOT supply allowed_schemas, ranking weights or any authority flags.
-- psycopg named parameters: objective, allowed_schemas, max_candidates,
-- weight_name, weight_columns, weight_description.
-- No user rows are accessed. Names/ranks are CANDIDATES only; never authorization.

WITH parameters AS (
  SELECT
    %(objective)s::text AS objective,
    %(allowed_schemas)s::text[] AS allowed_schemas,
    %(max_candidates)s::integer AS max_candidates,
    %(weight_name)s::numeric AS weight_name,
    %(weight_columns)s::numeric AS weight_columns,
    %(weight_description)s::numeric AS weight_description
), admissible AS (
  SELECT * FROM parameters p
  WHERE nullif(btrim(p.objective), '') IS NOT NULL
    AND cardinality(p.allowed_schemas) > 0
    AND p.max_candidates BETWEEN 1 AND 50
    AND p.weight_name >= 0 AND p.weight_columns >= 0
    AND p.weight_description >= 0
), lexical_query AS (
  SELECT regexp_replace(plainto_tsquery('spanish', a.objective)::text,
                        ' +& +', ' | ', 'g')::tsquery AS q
  FROM admissible a
), catalog AS (
  SELECT c.oid, n.nspname, c.relname, c.relkind,
         replace(c.relname, '_', ' ') AS label,
         coalesce(obj_description(c.oid, 'pg_class'), '') AS description,
         coalesce((
           SELECT string_agg(replace(att.attname, '_', ' '), ' ')
           FROM pg_attribute att
           WHERE att.attrelid = c.oid AND att.attnum > 0 AND NOT att.attisdropped
         ), '') AS column_labels
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN admissible a
  WHERE n.nspname = ANY(a.allowed_schemas)
    AND c.relkind IN ('r', 'p', 'v') AND NOT c.relispartition
), scored AS (
  SELECT c.nspname AS source_schema, c.relname AS source_name,
         c.relkind AS source_kind,
         (a.weight_name * ts_rank_cd(to_tsvector('spanish', c.label), q.q)
        + a.weight_columns * ts_rank_cd(to_tsvector('spanish', c.column_labels), q.q)
        + a.weight_description * ts_rank_cd(to_tsvector('spanish', c.description), q.q)) AS relevance_score,
         (
           SELECT count(*) FROM pg_constraint fk
           WHERE fk.contype = 'f'
             AND (fk.conrelid = c.oid OR fk.confrelid = c.oid)
         ) AS fk_connection_count
  FROM catalog c CROSS JOIN lexical_query q CROSS JOIN admissible a
)
SELECT source_schema, source_name, source_kind,
       relevance_score, fk_connection_count,
       false AS data_access_granted
FROM scored
WHERE relevance_score > 0
ORDER BY relevance_score DESC, source_schema, source_name
LIMIT (SELECT max_candidates FROM admissible);

-- IMPORTANT: 0 rows means "no match in this scoped metadata query";
-- never "source absent everywhere" and never "acquisition exhausted".
