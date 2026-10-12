-- IG M10.1 CP3: dynamic, governed read-only consumer inventory.
-- No router mutation, runtime cutover, production activation or external call.
-- Active governed adapters and Profiles are selected from asset metadata, not names.
DO $m101_inventory$
DECLARE
 v_batch uuid := gen_random_uuid();
 v_source text := 'supabase/migrations/20261012133100_ig_m10_1_profiles_adapters_consumers.sql';
 v_expected integer;
 v_pending integer;
 v_added integer;
 v_covered integer;
 v_invalid integer;
 v_duplicates integer;
BEGIN
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_activos
 WHERE codigo_activo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   AND archived_at IS NULL AND estado_operativo='READ_ONLY'
   AND coalesce(metadata->>'production_authorized','false')='false'
 ) THEN RAISE EXCEPTION 'M101_CONTRACT_NOT_SANDBOX_CURRENT'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M10.1'
   AND c.checkpoint_code='PROFILES_ADAPTERS_CONSUMERS'
   AND c.status='PENDING'
   AND u.unit_metadata#>>'{m10_1_consumer_inventory_governance_v1,classification}'
       ='ENGINEERING_SANDBOX_INVENTORY'
 ) THEN RAISE EXCEPTION 'M101_INVENTORY_AUTHORITY_OR_CHECKPOINT_NOT_READY'; END IF;

 WITH eligible AS (
   SELECT DISTINCT a.codigo_activo
   FROM public.lf_activo_relaciones r
   JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo AND a.archived_at IS NULL
   WHERE r.relacionado_codigo IN
    ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')
    AND ((a.tipo_activo='ADAPTER'
           AND nullif(a.metadata->>'input_governance_binding_contract','') IS NOT NULL)
      OR (a.tipo_activo='CAPABILITY'
           AND (a.metadata->>'consumer_domain'='PROFILES'
            OR a.metadata->>'dominio'='GOBERNANZA_PERFILES')))
 ), missing AS (
 SELECT e.codigo_activo FROM eligible e WHERE NOT EXISTS(
 SELECT 1 FROM public.lf_activo_relaciones x
 WHERE x.codigo_activo=e.codigo_activo
 AND x.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
 AND x.relacion_tipo='GOBERNADO_POR'
 ))
 SELECT (SELECT count(*) FROM eligible),(SELECT count(*) FROM missing)
 INTO v_expected,v_pending;
 IF v_expected=0 THEN RAISE EXCEPTION 'M101_NO_GOVERNED_CONSUMERS'; END IF;

 WITH sources AS (
 SELECT a.codigo_activo,
   string_agg(DISTINCT r.relacionado_codigo,',' ORDER BY r.relacionado_codigo) source_refs
 FROM public.lf_activo_relaciones r
 JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo AND a.archived_at IS NULL
 WHERE r.relacionado_codigo IN
   ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')
 AND ((a.tipo_activo='ADAPTER'
       AND nullif(a.metadata->>'input_governance_binding_contract','') IS NOT NULL)
   OR (a.tipo_activo='CAPABILITY'
       AND (a.metadata->>'consumer_domain'='PROFILES'
         OR a.metadata->>'dominio'='GOBERNANZA_PERFILES')))
 GROUP BY a.codigo_activo
 )
 INSERT INTO public.lf_activo_relaciones
 (codigo_activo,relacionado_codigo,relacion_tipo,valor_original,
  fuente,migration_batch_id,created_by_execution_id)
 SELECT s.codigo_activo,'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
        'GOBERNADO_POR',
        'ENGINEERING_SANDBOX_INVENTORY;observed_source='||s.source_refs||
        ';no_facade_migration_or_runtime_activation',
        v_source,v_batch,'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.1/CP3'
 FROM sources s
 WHERE NOT EXISTS (
 SELECT 1 FROM public.lf_activo_relaciones x
 WHERE x.codigo_activo=s.codigo_activo
 AND x.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
 AND x.relacion_tipo='GOBERNADO_POR'
 );
 GET DIAGNOSTICS v_added=ROW_COUNT;
 IF v_added IS DISTINCT FROM v_pending
 THEN RAISE EXCEPTION 'M101_PENDING_DELTA_NOT_MATCHED:%/%',v_added,v_pending; END IF;

 WITH eligible AS (
 SELECT DISTINCT a.codigo_activo
 FROM public.lf_activo_relaciones r
 JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo AND a.archived_at IS NULL
 WHERE r.relacionado_codigo IN
   ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')
 AND ((a.tipo_activo='ADAPTER'
       AND nullif(a.metadata->>'input_governance_binding_contract','') IS NOT NULL)
   OR (a.tipo_activo='CAPABILITY'
       AND (a.metadata->>'consumer_domain'='PROFILES'
          OR a.metadata->>'dominio'='GOBERNANZA_PERFILES')))
 ), linked AS (
 SELECT x.codigo_activo, count(*) AS qty
 FROM public.lf_activo_relaciones x
 WHERE x.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
 AND x.relacion_tipo='GOBERNADO_POR'
 GROUP BY x.codigo_activo
 )
 SELECT
   (SELECT count(*) FROM eligible e JOIN linked l ON e.codigo_activo=l.codigo_activo),
   (SELECT count(*) FROM public.lf_activo_relaciones r
    WHERE r.migration_batch_id=v_batch
      AND NOT EXISTS(SELECT 1 FROM eligible e WHERE e.codigo_activo=r.codigo_activo)),
   (SELECT count(*) FROM linked WHERE qty<>1)
 INTO v_covered,v_invalid,v_duplicates;
 IF v_covered IS DISTINCT FROM v_expected
    OR v_invalid<>0 OR v_duplicates<>0
 THEN RAISE EXCEPTION 'M101_INVENTORY_BAD_COVERAGE:%/% invalid=% duplicates=%',
  v_covered,v_expected,v_invalid,v_duplicates; END IF;
END $m101_inventory$;
