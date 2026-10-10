-- D1 dual-channel discovery / READONLY candidate.
-- TECHNICAL TEMPLATE ONLY: no runtime cutover. No permanent DB changes.
-- Parameter values must be materialized from a trusted Supabase-backed runtime:
-- objective is the user's request, but allowed_schemas, expected_policy_sha,
-- and per_family_limit must NOT originate from GPT, user input or Excel.
-- Bind named parameters through psycopg; NEVER interpolate SQL identifiers.
--
-- %(objective)s             :: text
-- %(allowed_schemas)s       :: text[]
-- %(expected_policy_sha)s   :: text
-- %(per_family_limit)s      :: integer
WITH raw_input AS (
 SELECT %(objective)s::text AS objective,
        %(allowed_schemas)s::text[] AS allowed_schemas,
        %(expected_policy_sha)s::text AS expected_policy_sha,
        %(per_family_limit)s::integer AS per_family_limit
), policy_state AS (
 SELECT count(*)::integer AS policy_count,max(policy_sha) AS policy_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
), validated AS (
 SELECT r.*,
        (p.policy_count=1
         AND p.policy_sha=r.expected_policy_sha
         AND r.expected_policy_sha ~ '^[0-9a-f]{64}$'
         AND length(btrim(r.objective)) BETWEEN 2 AND 4000
         AND cardinality(r.allowed_schemas) BETWEEN 1 AND 16
         AND r.per_family_limit BETWEEN 1 AND 20
        ) AS input_valid,
        p.policy_count,p.policy_sha
 FROM raw_input r CROSS JOIN policy_state p
), query_input AS (
 SELECT *,
  regexp_replace(plainto_tsquery('spanish',objective)::text,' +& +',' | ','g')::tsquery AS query_terms
 FROM validated WHERE input_valid
), physical_catalog AS (
 SELECT c.oid,n.nspname,c.relname,c.relkind,
        coalesce(obj_description(c.oid,'pg_class'),'') AS description,
        coalesce((SELECT string_agg(replace(a.attname,'_',' '),' ')
                  FROM pg_attribute a
                  WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'') AS column_terms
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN query_input q
 WHERE n.nspname=ANY(q.allowed_schemas)
   AND c.relkind IN ('r','p','v') AND NOT c.relispartition
), candidates AS (
 SELECT 'SCHEMA_METADATA'::text AS family,
        ('supabase://catalog/'||p.nspname||'/'||p.relname)::text AS candidate_ref,
        'STRUCTURAL_CANDIDATE'::text AS source_class,
        4*ts_rank_cd(to_tsvector('spanish',replace(p.relname,'_',' ')),q.query_terms)
        +ts_rank_cd(to_tsvector('spanish',p.column_terms||' '||p.description),q.query_terms) AS relevance_score
 FROM physical_catalog p CROSS JOIN query_input q
 UNION ALL
 SELECT 'SOURCE_REGISTRY'::text,
        ('supabase://public.lf_activos/'||a.codigo_activo)::text,
        a.tipo_activo::text,
        ts_rank_cd(to_tsvector('spanish',coalesce(a.router_search_text,'')),q.query_terms)
 FROM public.v_lf_fuente_operativa_busqueda a CROSS JOIN query_input q
), ranked AS (
 SELECT *,
 row_number() OVER(PARTITION BY family ORDER BY relevance_score DESC,candidate_ref) AS family_rank
 FROM candidates WHERE relevance_score>0
), bounded AS (
 SELECT family,candidate_ref,source_class,relevance_score FROM ranked
 CROSS JOIN query_input q WHERE family_rank<=q.per_family_limit
), aggregated AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'candidate_ref',candidate_ref,
  'discovery_family',family,
  'source_class',source_class,
  'relevance_score',round(relevance_score::numeric,4),
  'authority_check','NOT_VERIFIED',
  'authorization_check','NOT_VERIFIED',
  'data_access_granted',false
 ) ORDER BY relevance_score DESC,candidate_ref),'[]'::jsonb) AS results
 FROM bounded
)
SELECT jsonb_build_object(
 'schema_version','LF_MULTIFAMILY_SOURCE_DISCOVERY_RESULT_V1',
 'discovery_state',CASE
   WHEN NOT (SELECT input_valid FROM validated) THEN 'ERROR_FAIL_CLOSED'
   WHEN jsonb_array_length(a.results)=0 THEN 'NO_MATCH_IN_SCOPE'
   ELSE 'CANDIDATES_FOUND' END,
 'policy_currentness_checked',(SELECT input_valid FROM validated),
 'candidate_sources',CASE WHEN (SELECT input_valid FROM validated) THEN a.results ELSE '[]'::jsonb END,
 'discovery_exhausted',false,
 'scope_remaining_unknown',true,
 'data_access_granted',false,
 'effects_executed',false
) AS discovery_result
FROM aggregated a;

-- SOURCE_REGISTRY covers assets like DOC/CARD/CAPABILITY:
-- they are references/candidates, not permission to read operational state.
-- This template never uses a table-name guess to grant SQL SELECT.
-- NO_MATCH_IN_SCOPE is not global absence or full discovery exhaustion.
