-- LF D1: canonical metadata-only intent adapter, NOT a new discovery index.
-- Delegates all search to inventory.fn_lookup_v3; no business row reads.
CREATE OR REPLACE FUNCTION private.fn_lf_d1_inventory_candidates_v1(
 p_objective text,p_max_candidates integer DEFAULT 12
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE v_policy_count int;v_policy_sha text;v_policy_version text;
 v_inventory_status text;v_candidates jsonb:='[]'::jsonb;
BEGIN
 IF p_objective IS NULL OR length(btrim(p_objective)) NOT BETWEEN 3 AND 1000
 OR p_max_candidates IS NULL OR p_max_candidates NOT BETWEEN 1 AND 25 THEN
  RETURN pg_catalog.jsonb_build_object('schema_version','LF_D1_CANONICAL_INVENTORY_CANDIDATES_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','OBJECTIVE_OR_BUDGET_INVALID',
   'candidate_sources','[]'::jsonb,'discovery_exhausted',false,
   'data_access_granted',false,'effects_executed',false);
 END IF;
 SELECT count(*)::int,max(policy_sha),max(policy_version)
 INTO v_policy_count,v_policy_sha,v_policy_version FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE';
 IF v_policy_count<>1 OR v_policy_sha IS NULL OR
 v_policy_sha !~ '^[0-9a-f]{64}$' THEN
  RETURN pg_catalog.jsonb_build_object('schema_version','LF_D1_CANONICAL_INVENTORY_CANDIDATES_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','CANONICAL_SOURCE_POLICY_NOT_CURRENT',
   'candidate_sources','[]'::jsonb,'discovery_exhausted',false,
   'data_access_granted',false,'effects_executed',false);
 END IF;
 SELECT metadata->>'inventory_status' INTO v_inventory_status
 FROM public.lf_activos WHERE codigo_activo='LF_GLOBAL_TECHNICAL_INVENTORY_V1'
 AND archived_at IS NULL AND estado_operativo='READ_ONLY';
 IF v_inventory_status IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('schema_version','LF_D1_CANONICAL_INVENTORY_CANDIDATES_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','INVENTORY_ASSET_NOT_CURRENT',
   'candidate_sources','[]'::jsonb,'discovery_exhausted',false,
   'data_access_granted',false,'effects_executed',false);
 END IF;
 -- Generic Spanish singular/plural lexical variants, no domain table routes.
 -- Every match is returned by the existing inventory.fn_lookup_v3.
 WITH tokens AS (
  SELECT DISTINCT lower(x.term) AS term
  FROM pg_catalog.regexp_split_to_table(
   pg_catalog.translate(lower(p_objective),'áéíóúü','aeiouu'),
   '[^[:alpha:][:digit:]]+') AS x(term)
  WHERE length(x.term) BETWEEN 4 AND 35
 ), bounded_tokens AS (
  SELECT term FROM tokens ORDER BY length(term) DESC,term LIMIT 8
 ), variants AS (
  SELECT DISTINCT lookup_term FROM bounded_tokens t
  CROSS JOIN LATERAL (
   SELECT t.term AS lookup_term
   UNION ALL SELECT t.term||'s' WHERE t.term ~ '[aeiou]$'
   UNION ALL SELECT t.term||'es' WHERE t.term ~ '[^aeiou]$'
  ) v
 ), searched AS (
  SELECT v.lookup_term,s.* FROM variants v
  CROSS JOIN LATERAL inventory.fn_lookup_v3(
   v.lookup_term,ARRAY['DB_TABLE','DB_VIEW','DB_FUNCTION','LF_ASSET','CAPABILITY','CONTRACT','OPERATION']::text[],
   20,ARRAY['CURRENT']::text[]) s
 ), matched AS (
  SELECT *,
   CASE match_reason WHEN 'EXACT_REF' THEN 1 WHEN 'EXACT_NAME' THEN 2
    WHEN 'TAG' THEN 3 WHEN 'COLUMN' THEN 4 ELSE 5 END AS match_priority,
   CASE object_type WHEN 'DB_TABLE' THEN 1 WHEN 'LF_ASSET' THEN 2
    WHEN 'CONTRACT' THEN 3 WHEN 'OPERATION' THEN 4
    WHEN 'DB_VIEW' THEN 5 ELSE 6 END AS type_priority
  FROM searched
  WHERE currentness IN ('CURRENT','CATALOG_MANAGED')
   AND status='ACTIVE' AND object_ref IS NOT NULL
 ), dedup AS (
  SELECT DISTINCT ON(object_ref) *
  FROM matched ORDER BY object_ref,match_priority,type_priority,lookup_term
 ), best AS (
  SELECT * FROM dedup ORDER BY match_priority,type_priority,object_ref
  LIMIT p_max_candidates
 )
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'source_ref',object_ref,'source_kind',object_type,
  'source_system',source_system,'schema_name',schema_name,
  'object_name',object_name,'match_reason',match_reason,
  'matched_lookup_term',lookup_term,'inventory_currentness',currentness,
  'source_of_truth_flag',source_of_truth,
  'authority_check','NOT_VERIFIED','authorization_check','NOT_VERIFIED',
  'data_access_granted',false
 ) ORDER BY match_priority,type_priority,object_ref),'[]'::jsonb)
 INTO v_candidates FROM best;
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D1_CANONICAL_INVENTORY_CANDIDATES_V1',
  'discovery_state',CASE WHEN pg_catalog.jsonb_array_length(v_candidates)>0
   THEN 'CANDIDATES_FOUND' ELSE 'NO_MATCH_IN_SCOPE' END,
  'policy_code','POL-LF-SOURCE-RESOLUTION',
  'policy_version',v_policy_version,'policy_sha',v_policy_sha,
  'inventory_asset_code','LF_GLOBAL_TECHNICAL_INVENTORY_V1',
  'inventory_status',v_inventory_status,
  'candidate_sources',v_candidates,
  'candidate_count',pg_catalog.jsonb_array_length(v_candidates),
  'discovery_exhausted',false,'scope_remaining_unknown',true,
  'data_access_granted',false,'effects_executed',false,
  'next_required_gate','CANONICAL_SOURCE_BINDING_AND_ACTOR_AUTHORIZATION');
EXCEPTION WHEN insufficient_privilege THEN
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D1_CANONICAL_INVENTORY_CANDIDATES_V1',
  'discovery_state','ERROR_FAIL_CLOSED','code','INVENTORY_ACL_DENIED',
  'candidate_sources','[]'::jsonb,'discovery_exhausted',false,
  'data_access_granted',false,'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d1_inventory_candidates_v1(text,integer)
 IS 'Candidate-only D1 adapter over inventory.fn_lookup_v3, never business data access.';
REVOKE ALL ON FUNCTION private.fn_lf_d1_inventory_candidates_v1(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.fn_lf_d1_inventory_candidates_v1(text,integer) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d1_inventory_candidates_v1(text,integer) TO service_role;
