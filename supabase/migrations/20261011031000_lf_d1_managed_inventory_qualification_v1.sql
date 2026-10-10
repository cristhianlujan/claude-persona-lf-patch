-- The catalog-drift view is SECURITY INVOKER and requires this exact helper.
-- It calls only pg_catalog.pg_get_function_identity_arguments(oid).
-- No data privileges or client-facing grants are added.
DO $pre$ BEGIN
 IF NOT has_table_privilege('service_role','inventory.v_pg_catalog_drift_v1','SELECT')
 THEN RAISE EXCEPTION 'INVENTORY_DRIFT_VIEW_NOT_READABLE_BY_SERVER'; END IF;
 IF has_function_privilege('anon','inventory.fn_function_identity_args_stable(oid)','EXECUTE')
 OR has_function_privilege('authenticated','inventory.fn_function_identity_args_stable(oid)','EXECUTE')
 THEN RAISE EXCEPTION 'INVENTORY_IDENTITY_HELPER_UNEXPECTED_CLIENT_EXECUTE'; END IF;
END $pre$;
GRANT EXECUTE ON FUNCTION inventory.fn_function_identity_args_stable(oid) TO service_role;

-- LF D1: technical qualification readback only; NOT promotion of the inventory asset.
-- Reuse inventory snapshots, managed currentness, drift view and existing catalogs.
-- Scope: managed DATABASE_AND_REGISTRIES only. External repo/edge are excluded.
CREATE OR REPLACE FUNCTION private.fn_lf_d1_managed_inventory_qualification_v1(
 p_expected_snapshot_code text DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 WITH latest AS (
  SELECT s.snapshot_code,s.status,s.completed_at,s.object_count,s.dependency_count,s.metadata
  FROM inventory.snapshots s
  WHERE s.source_system='INVENTORY_STAGED_REFRESH_V1'
    AND s.scope='DATABASE_AND_REGISTRIES'
  ORDER BY s.completed_at DESC NULLS LAST
  LIMIT 1
 ), inventory_asset AS (
  SELECT count(*)::int AS asset_count,max(a.metadata->>'inventory_status') AS inventory_status
  FROM public.lf_activos a
  WHERE a.codigo_activo='LF_GLOBAL_TECHNICAL_INVENTORY_V1'
    AND a.archived_at IS NULL AND a.estado_operativo='READ_ONLY'
 ), counts AS (
  SELECT
   (SELECT count(*)::bigint FROM inventory.search_index) AS indexed_objects,
   (SELECT count(*)::bigint FROM inventory.dependencies d WHERE d.active) AS active_dependencies,
   (SELECT count(*)::bigint FROM inventory.v_pg_catalog_drift_v1) AS active_catalog_drift,
   (SELECT count(*)::int
    FROM (VALUES ('SUPABASE_PG_CATALOG'),('LF_ACTIVOS'),
                 ('PROGRAMACION_CONTRATOS'),('LF_OPERATION_REGISTRY'))
      v(source_system)
    JOIN latest l ON TRUE
    WHERE inventory.fn_managed_currentness_eval_v1(
       v.source_system,l.completed_at,l.status,
       nullif(l.metadata->>'pg_catalog_drift','')::integer,
       l.metadata#>>'{registries,status}',pg_catalog.clock_timestamp()
    )='CATALOG_MANAGED') AS current_managed_sources
 ), outcome AS (
  SELECT
   l.snapshot_code,l.status,l.completed_at,l.object_count,l.dependency_count,l.metadata,
   a.asset_count,a.inventory_status,
   c.indexed_objects,c.active_dependencies,c.active_catalog_drift,c.current_managed_sources,
   CASE
    WHEN l.snapshot_code IS NULL THEN 'BLOCK_NO_COMPLETED_MANAGED_SNAPSHOT'
    WHEN p_expected_snapshot_code IS NOT NULL
      AND l.snapshot_code IS DISTINCT FROM p_expected_snapshot_code
      THEN 'BLOCK_EXPECTED_SNAPSHOT_MISMATCH'
    WHEN l.status<>'COMPLETED' OR l.completed_at IS NULL
      THEN 'BLOCK_SNAPSHOT_NOT_COMPLETED'
    WHEN l.metadata->>'pg_catalog_drift' IS DISTINCT FROM '0'
      OR c.active_catalog_drift<>0 THEN 'BLOCK_PG_CATALOG_DRIFT'
    WHEN l.metadata#>>'{registries,status}' IS DISTINCT FROM 'COMPLETED'
      THEN 'BLOCK_REGISTRY_REFRESH_INCOMPLETE'
    WHEN l.object_count IS DISTINCT FROM c.indexed_objects
      OR l.dependency_count IS DISTINCT FROM c.active_dependencies
      THEN 'BLOCK_REFRESH_COUNTS_DIVERGED'
    WHEN c.current_managed_sources<>4 THEN 'BLOCK_MANAGED_CURRENTNESS_MISSING'
    WHEN a.asset_count<>1 OR a.inventory_status IS NULL
      THEN 'BLOCK_INVENTORY_AUTHORITY_MISSING'
    ELSE 'MANAGED_METADATA_TECHNICALLY_READY'
   END AS decision
  FROM (SELECT 1 AS singleton) z LEFT JOIN latest l ON TRUE
  CROSS JOIN inventory_asset a CROSS JOIN counts c
 )
 SELECT pg_catalog.jsonb_build_object(
  'schema_version','LF_D1_MANAGED_INVENTORY_QUALIFICATION_V1',
  'scope','DATABASE_AND_REGISTRIES_ONLY',
  'snapshot_code',snapshot_code,
  'snapshot_status',status,'observed_at',completed_at,
  'indexed_objects',indexed_objects,'snapshot_objects',object_count,
  'active_dependencies',active_dependencies,'snapshot_dependencies',dependency_count,
  'catalog_drift',active_catalog_drift,
  'current_managed_source_count',current_managed_sources,
  'inventory_asset_status',inventory_status,
  'technical_readiness',CASE WHEN decision='MANAGED_METADATA_TECHNICALLY_READY'
    THEN 'PASS' ELSE 'BLOCKED' END,
  'decision',decision,
  'inventory_governance_admitted',false,
  'external_repo_and_edge_qualified',false,
  'business_data_read_authorized',false,
  'runtime_cutover_authorized',false,
  'effects_executed',false
 ) FROM outcome;
$fn$;
COMMENT ON FUNCTION private.fn_lf_d1_managed_inventory_qualification_v1(text)
 IS 'Read-only scoped inventory qualification, never promotes a candidate or admits data reads.';
REVOKE ALL ON FUNCTION private.fn_lf_d1_managed_inventory_qualification_v1(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.fn_lf_d1_managed_inventory_qualification_v1(text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d1_managed_inventory_qualification_v1(text) TO service_role;
