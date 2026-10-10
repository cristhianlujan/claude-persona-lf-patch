-- LF D1 relation expansion: reuse existing inventory.objects/dependencies.
-- Metadata only. No new graph, no row SELECT of business sources.
CREATE OR REPLACE FUNCTION private.fn_lf_d1_inventory_neighbors_v1(
 p_source_ref text,p_max_related integer DEFAULT 12
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE v_policy_count integer;v_policy_sha text;v_seed_matches integer;
 v_neighbors jsonb:='[]'::jsonb;
BEGIN
 IF p_source_ref IS NULL OR length(btrim(p_source_ref)) NOT BETWEEN 8 AND 300
 OR p_max_related IS NULL OR p_max_related NOT BETWEEN 1 AND 25 THEN
  RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_D1_CANONICAL_INVENTORY_NEIGHBORS_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','SOURCE_OR_BUDGET_INVALID',
   'related_sources','[]'::jsonb,'data_access_granted',false,
   'discovery_exhausted',false,'effects_executed',false);
 END IF;
 SELECT count(*)::int,max(policy_sha) INTO v_policy_count,v_policy_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE';
 IF v_policy_count<>1 OR v_policy_sha !~ '^[0-9a-f]{64}$' THEN
  RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_D1_CANONICAL_INVENTORY_NEIGHBORS_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','SOURCE_POLICY_NOT_CURRENT',
   'related_sources','[]'::jsonb,'data_access_granted',false,
   'discovery_exhausted',false,'effects_executed',false);
 END IF;
 SELECT count(*)::int INTO v_seed_matches
 FROM inventory.fn_lookup_v3(p_source_ref,ARRAY['DB_TABLE']::text[],2,
                             ARRAY['CURRENT']::text[]) s
 WHERE s.object_ref=p_source_ref AND s.match_reason='EXACT_REF'
   AND s.currentness IN ('CURRENT','CATALOG_MANAGED');
 IF v_seed_matches<>1 THEN
  RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_D1_CANONICAL_INVENTORY_NEIGHBORS_V1',
   'discovery_state','ERROR_FAIL_CLOSED','code','SEED_NOT_CANONICAL_CURRENT',
   'related_sources','[]'::jsonb,'data_access_granted',false,
   'discovery_exhausted',false,'effects_executed',false);
 END IF;
 WITH seed AS (
  SELECT object_id FROM inventory.objects
  WHERE object_ref=p_source_ref AND active AND object_type='DB_TABLE'
 ), candidate_edges AS (
  SELECT o.object_ref AS related_ref,
   CASE WHEN d.source_object_id=s.object_id THEN 'OUTBOUND_FK'
        ELSE 'INBOUND_FK' END AS direction,
   d.confidence
  FROM seed s
  JOIN inventory.dependencies d
   ON (d.source_object_id=s.object_id OR d.target_object_id=s.object_id)
  JOIN inventory.objects o
   ON o.object_id=CASE WHEN d.source_object_id=s.object_id
      THEN d.target_object_id ELSE d.source_object_id END
  WHERE d.active AND d.relation_type='FK_TO'
   AND d.evidence_type='PG_CONSTRAINT' AND d.confidence>=0.99
   AND o.active AND o.object_type='DB_TABLE'
   AND o.object_ref<>p_source_ref
 ), dedup AS (
  SELECT DISTINCT ON (related_ref) related_ref,direction,confidence
  FROM candidate_edges ORDER BY related_ref,direction
 ), selected AS (
  SELECT * FROM dedup ORDER BY related_ref LIMIT p_max_related
 )
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'source_ref',related_ref,'relation_direction',direction,
  'relation_type','FK_TO','evidence_type','PG_CONSTRAINT',
  'confidence',confidence,'authority_check','NOT_VERIFIED',
  'authorization_check','NOT_VERIFIED','data_access_granted',false)
  ORDER BY related_ref),'[]'::jsonb)
 INTO v_neighbors FROM selected;
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D1_CANONICAL_INVENTORY_NEIGHBORS_V1',
  'discovery_state',CASE WHEN pg_catalog.jsonb_array_length(v_neighbors)>0
       THEN 'RELATED_CANDIDATES_FOUND' ELSE 'NO_RELATED_MATCH_IN_SCOPE' END,
  'seed_ref',p_source_ref,'policy_sha',v_policy_sha,
  'related_sources',v_neighbors,
  'related_count',pg_catalog.jsonb_array_length(v_neighbors),
  'discovery_exhausted',false,'scope_remaining_unknown',true,
  'data_access_granted',false,'effects_executed',false,
  'next_required_gate','CANONICAL_SOURCE_BINDING_AND_ACTOR_AUTHORIZATION');
EXCEPTION WHEN insufficient_privilege THEN
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D1_CANONICAL_INVENTORY_NEIGHBORS_V1',
  'discovery_state','ERROR_FAIL_CLOSED','code','INVENTORY_ACL_DENIED',
  'related_sources','[]'::jsonb,'data_access_granted',false,
  'discovery_exhausted',false,'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d1_inventory_neighbors_v1(text,integer)
IS 'Candidate-only D1 FK graph expansion using the existing inventory; no business row reads.';
REVOKE ALL ON FUNCTION private.fn_lf_d1_inventory_neighbors_v1(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.fn_lf_d1_inventory_neighbors_v1(text,integer) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d1_inventory_neighbors_v1(text,integer) TO service_role;
