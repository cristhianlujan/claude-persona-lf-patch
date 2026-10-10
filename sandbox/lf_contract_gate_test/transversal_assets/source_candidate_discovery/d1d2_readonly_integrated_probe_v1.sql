-- D1 -> D2 read-only integration rehearsal; NOT a runtime entrypoint.
-- Parameters are fixtures ONLY; in production they must be resolved
-- from canonical Supabase identity, policy and scoped execution receipts.
-- This probe never reads LF business rows, invents an admission receipt,
-- grants a source permission or concludes that global discovery is exhausted.
-- %(objective)s::text, %(allowed_schemas)s::text[],
-- %(expected_policy_sha)s::text.
WITH probe_input AS (
 SELECT %(objective)s::text AS objective,
        %(allowed_schemas)s::text[] AS allowed_schemas,
        %(expected_policy_sha)s::text AS expected_policy_sha
), policy_state AS (
 SELECT count(*)::integer AS active_count,max(policy_sha) AS current_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
), guarded AS (
 SELECT i.*,
  (nullif(btrim(i.objective),'') IS NOT NULL
   AND cardinality(i.allowed_schemas) BETWEEN 1 AND 12
   AND p.active_count=1 AND p.current_sha=i.expected_policy_sha
   AND i.expected_policy_sha ~ '^[0-9a-f]{64}$') AS allowed,
  regexp_replace(plainto_tsquery('spanish',i.objective)::text,' +& +',' | ','g')::tsquery AS lexemes
 FROM probe_input i CROSS JOIN policy_state p
), physical_catalog AS (
 SELECT n.nspname,c.relname,
        coalesce(obj_description(c.oid,'pg_class'),'') AS description
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN guarded g
 WHERE g.allowed AND n.nspname=ANY(g.allowed_schemas)
       AND c.relkind IN ('r','p','v') AND NOT c.relispartition
), raw_candidates AS (
 SELECT 'SCHEMA_METADATA'::text AS family,
 ('supabase://catalog/'||p.nspname||'/'||p.relname)::text AS candidate_ref,
 4*ts_rank_cd(to_tsvector('spanish',replace(p.relname,'_',' ')),g.lexemes)
 +ts_rank_cd(to_tsvector('spanish',p.description),g.lexemes) AS relevance
 FROM physical_catalog p CROSS JOIN guarded g
 UNION ALL
 SELECT 'SOURCE_REGISTRY',
 ('supabase://public.lf_activos/'||a.codigo_activo)::text,
 ts_rank_cd(to_tsvector('spanish',coalesce(a.router_search_text,'')),g.lexemes)
 FROM public.v_lf_fuente_operativa_busqueda a CROSS JOIN guarded g
 WHERE g.allowed
), ranked AS (
 SELECT family,candidate_ref,relevance,
 row_number() over(partition by family order by relevance desc,candidate_ref) AS family_rank
 FROM raw_candidates WHERE relevance>0
), bounded AS (
 SELECT family,candidate_ref,relevance FROM ranked WHERE family_rank<=5
), catalog_result AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'source_ref',candidate_ref,'discovery_family',family,
 'authority_check','NOT_VERIFIED','authorization_check','NOT_VERIFIED',
 'data_access_granted',false) ORDER BY relevance DESC,candidate_ref),'[]'::jsonb) AS candidates
 FROM bounded
), binding_evidence AS (
 SELECT count(*)::integer AS current_physical_binding_count
 FROM bounded b
 JOIN public.lf_activos a ON a.metadata->>'canonical_source_ref'=b.candidate_ref
 WHERE a.archived_at IS NULL AND a.metadata->>'admission_status'='VIGENTE'
), planner_input AS (
 SELECT jsonb_build_object(
 'consumer_ref','synthetic://lf-d1d2-metadata-probe',
 'unresolved_reasons',jsonb_build_array('SOURCE_AUTHORITY_UNVERIFIED'),
 'current_evidence',jsonb_build_array(),
 'candidates','[]'::jsonb
 ) AS payload
), planner AS (
 SELECT public.lf_targeted_evidence_acquisition_plan_v1(payload) AS outcome FROM planner_input
)
SELECT jsonb_build_object(
 'schema_version','LF_D1D2_READONLY_INTEGRATION_PROBE_V1',
 'scope_status',CASE WHEN g.allowed THEN 'POLICY_MATCHED' ELSE 'POLICY_OR_SCOPE_BLOCKED' END,
 'discovery_state',CASE WHEN NOT g.allowed THEN 'ERROR_FAIL_CLOSED'
   WHEN jsonb_array_length(c.candidates)>0 THEN 'CANDIDATES_FOUND'
   ELSE 'NO_MATCH_IN_SCOPE' END,
 'candidate_count',CASE WHEN g.allowed THEN jsonb_array_length(c.candidates) ELSE 0 END,
 'candidate_sources',CASE WHEN g.allowed THEN c.candidates ELSE '[]'::jsonb END,
 'current_source_binding_count',CASE WHEN g.allowed THEN b.current_physical_binding_count ELSE 0 END,
 'read_admission','NOT_ADMITTED',
 'admitted_candidate_count',0,
 'planner_state',CASE WHEN g.allowed THEN p.outcome->>'state' ELSE 'NOT_CALLED' END,
 'planner_code',CASE WHEN g.allowed THEN p.outcome->>'code' ELSE 'POLICY_OR_SCOPE_BLOCKED' END,
 'planner_exhaustion_scope','LOCAL_ADMITTED_CANDIDATES_ONLY',
 'next_action',CASE WHEN NOT g.allowed THEN 'BLOCK_POLICY_OR_SCOPE'
    ELSE 'RETURN_TO_SOURCE_DISCOVERY' END,
 'global_discovery_exhausted',false,
 'data_access_granted',false,
 'effects_executed',false,
 'end_to_end_runtime_proven',false
) AS probe_result
FROM guarded g CROSS JOIN catalog_result c CROSS JOIN binding_evidence b
CROSS JOIN planner p;
-- A discovered physical table is not a registered read facade.
-- Even current_physical_binding_count>0 is not tenant/access admission.
