-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.1 / CP3
-- Inventory only: Profiles and governed Adapters as consumers of Input Governance.
-- Existing observed paths are preserved. This does NOT claim SQL facade migration
-- or enable runtime, release, permissions or automatic impact.
BEGIN;
DO $m101$
DECLARE
 v_batch constant uuid := 'b4c10510-1a11-4d80-9a00-101100000001'::uuid;
 v_source constant text := 'supabase/migrations/20261012111700_ig_m10_1_profiles_adapters_consumers.sql';
 v_exec constant text := 'IG-CV-V2-M10-1-CONSUMER-INVENTORY';
 v_total integer;
 v_adapters integer;
 v_profiles integer;
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_activos
   WHERE codigo_activo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
     AND archived_at IS NULL AND estado_operativo='READ_ONLY'
 ) THEN RAISE EXCEPTION 'M101_EXECUTION_CONTRACT_NOT_CURRENT'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_activo_relaciones WHERE migration_batch_id=v_batch)
 THEN RAISE EXCEPTION 'M101_BATCH_ALREADY_MATERIALIZED'; END IF;

 WITH eligible AS (
  SELECT DISTINCT a.codigo_activo,a.tipo_activo
  FROM public.lf_activo_relaciones r
  JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo AND a.archived_at IS NULL
  WHERE r.relacionado_codigo IN
   ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')
  AND ((a.tipo_activo='ADAPTER' AND a.metadata ? 'input_governance_binding_contract')
    OR a.codigo_activo LIKE 'EDGE_FN_LF_PROFILES%' OR a.codigo_activo LIKE 'PROFILES_%')
 )
 SELECT count(*),count(*) FILTER (WHERE tipo_activo='ADAPTER'),
        count(*) FILTER (WHERE codigo_activo LIKE '%PROFILES%')
 INTO v_total,v_adapters,v_profiles FROM eligible;
 IF v_total<>4 OR v_adapters<>2 OR v_profiles<>2
 THEN RAISE EXCEPTION 'M101_CONSUMER_BASELINE_DRIFT: %/%/%',v_total,v_adapters,v_profiles; END IF;

 INSERT INTO public.lf_activo_relaciones(
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
  migration_batch_id,created_by_execution_id)
 SELECT DISTINCT a.codigo_activo,'INPUT_GOVERNANCE_EXECUTION_CONTRACT','GOBERNADO_POR',
   'Inventario consumidor actual: '||r.relacionado_codigo||
   '; no implica migracion a fachada SQL ni activacion',
   v_source,v_batch,v_exec
 FROM public.lf_activo_relaciones r
 JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo AND a.archived_at IS NULL
 WHERE r.relacionado_codigo IN
   ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')
 AND ((a.tipo_activo='ADAPTER' AND a.metadata ? 'input_governance_binding_contract')
   OR a.codigo_activo LIKE 'EDGE_FN_LF_PROFILES%' OR a.codigo_activo LIKE 'PROFILES_%');
 GET DIAGNOSTICS v_total=ROW_COUNT;
 IF v_total<>4 THEN RAISE EXCEPTION 'M101_INSERTED_COUNT_DRIFT:%',v_total; END IF;
 IF EXISTS (
   SELECT 1 FROM public.lf_activo_relaciones r
   JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo
   WHERE r.migration_batch_id=v_batch AND a.tipo_activo='ADAPTER'
     AND NOT (a.metadata ? 'input_governance_binding_contract')
 ) THEN RAISE EXCEPTION 'M101_UNBOUND_ADAPTER_ADMITTED'; END IF;
END
$m101$;
SELECT count(*) AS positive_rows,
 count(*) FILTER (WHERE a.tipo_activo='ADAPTER') AS adapters,
 count(*) FILTER (WHERE a.codigo_activo LIKE '%PROFILES%') AS profiles,
 count(*) FILTER (WHERE a.tipo_activo='ADAPTER' AND NOT (a.metadata ? 'input_governance_binding_contract')) AS negative_unbound
FROM public.lf_activo_relaciones r JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo
WHERE r.migration_batch_id='b4c10510-1a11-4d80-9a00-101100000001'::uuid;
COMMIT;