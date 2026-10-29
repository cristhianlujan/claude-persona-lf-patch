-- ACT-0001: retirar la excepcion GESTION_ACTIVOS_IA del Stage1/Stage2/transiciones.
-- Operaciones de perfil/skill permanecen en lf_router_action_registry.
-- Esta migracion solo debe aplicarse mediante LF Migration Merge Train.
-- Fail closed contra drift de los 3 cuerpos de funcion; sin cambios de ACL.
BEGIN;

DO $retire$
DECLARE
  v_fn text;
  v_old text;
  v_new text;
BEGIN
  v_fn := pg_get_functiondef('public.lf_router_stage1_validate_v2(jsonb)'::regprocedure);
  IF md5(v_fn) <> 'b1a76e64645401871646658d5ee3826d' THEN
    RAISE EXCEPTION 'BLOCK_STAGE1_SOURCE_DRIFT';
  END IF;
  v_old := $old$    IF v_transversal IS NOT NULL THEN
      IF v_transversal<>'GESTION_ACTIVOS_IA' OR v_channel IS NOT NULL THEN
        v_codes := array_append(v_codes,'RUTA_TRANSVERSAL_INVALIDA');
      END IF;
    ELSIF v_channel IS NULL OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES') THEN
      v_codes := array_append(v_codes,'CANAL_NO_RECONOCIDO');
    END IF;$old$;
  v_new := $new$    IF v_transversal IS NOT NULL THEN
      v_codes := array_append(v_codes,'RUTA_TRANSVERSAL_INVALIDA');
    END IF;
    IF v_channel IS NULL OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES') THEN
      v_codes := array_append(v_codes,'CANAL_NO_RECONOCIDO');
    END IF;$new$;
  IF (length(v_fn)-length(replace(v_fn,v_old,''))) <> length(v_old) THEN
    RAISE EXCEPTION 'BLOCK_STAGE1_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_fn,v_old,v_new);

  v_fn := pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  IF md5(v_fn) <> '045a1ae1b541d31b6e626c56bb907a85' THEN
    RAISE EXCEPTION 'BLOCK_STAGE2_SOURCE_DRIFT';
  END IF;
  v_old := $old$    IF v_transversal='GESTION_ACTIVOS_IA' THEN
      v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
      RETURN v_base || jsonb_build_object(
        'paso','RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA',
        'router_resolve',v_rs,
        'motivo_es','Gestionar el propio perfil o skill es una ruta transversal, no un cuarto canal.',
        'siguiente_paso_es','Seguir la operacion gobernada exacta que determine ACT-0001.'
      );
    END IF;

$old$;
  IF (length(v_fn)-length(replace(v_fn,v_old,''))) <> length(v_old) THEN
    RAISE EXCEPTION 'BLOCK_STAGE2_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_fn,v_old,'');

  v_fn := pg_get_functiondef('public.lf_router_route_transition_resolve_v1(jsonb)'::regprocedure);
  IF md5(v_fn) <> '64b2f867be6c1410eb35abcfee6c7ae8' THEN
    RAISE EXCEPTION 'BLOCK_TRANSITION_SOURCE_DRIFT';
  END IF;
  v_old := $old$    WHEN 'RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA' THEN
      v_transition_code:='TRANSVERSAL_GOVERNED_OPERATION_REQUIRED';
      v_transition_class:='HANDOFF';
      v_next_step:='transversal_governed_operation';
$old$;
  IF (length(v_fn)-length(replace(v_fn,v_old,''))) <> length(v_old) THEN
    RAISE EXCEPTION 'BLOCK_TRANSITION_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_fn,v_old,'');

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('lf_router_stage1_validate_v2','lf_router_route_v1','lf_router_route_transition_resolve_v1')
      AND pg_get_functiondef(p.oid) LIKE '%GESTION_ACTIVOS_IA%'
  ) THEN
    RAISE EXCEPTION 'BLOCK_RETIRED_ROUTE_STILL_REFERENCED';
  END IF;
END
$retire$;

DO $verify$
DECLARE
  v_sample jsonb := jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Actualizar el perfil de ejemplo agregando una regla',
    'es_operacion',true,'ambiguo',false,'respuesta_directa',false,
    'sujeto','perfil de ejemplo','formas_busqueda',jsonb_build_array('perfil de ejemplo'),
    'alternativas','[]'::jsonb,'correcciones','[]'::jsonb,
    'negocios_afectados','[]'::jsonb,'negocio_codigo','LF',
    'razon_seleccion','Caso negativo para ruta retirada',
    'downstream_execution_allowed',false
  );
  v_result jsonb;
  v_channel text;
BEGIN
  v_result := public.lf_router_stage1_validate_v2(
    v_sample || jsonb_build_object('ruta_transversal','GESTION_ACTIVOS_IA')
  );
  IF v_result->>'valid' <> 'false'
     OR NOT (v_result->'codes' ? 'RUTA_TRANSVERSAL_INVALIDA') THEN
    RAISE EXCEPTION 'BLOCK_RETIRED_ROUTE_NOT_REJECTED_%',v_result;
  END IF;
  FOR v_channel IN SELECT unnest(ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']) LOOP
    v_result := public.lf_router_stage1_validate_v2(
      v_sample || jsonb_build_object('canal_candidato',v_channel,'ruta_transversal',null)
    );
    IF v_result->>'valid' <> 'true' THEN
      RAISE EXCEPTION 'BLOCK_CHANNEL_REGRESSION_%_%',v_channel,v_result;
    END IF;
  END LOOP;
  v_result := public.lf_router_route_transition_resolve_v1(
    jsonb_build_object('schema_version','LF_ROUTER_ROUTE_V1',
                       'router','ACT-0001','paso','RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA')
  );
  IF v_result->>'status' <> 'BLOCKED'
     OR v_result->>'blocking_code' <> 'BLOCK_ROUTER_ROUTE_STEP_UNMAPPED' THEN
    RAISE EXCEPTION 'BLOCK_RETIRED_TRANSITION_NOT_CLOSED_%',v_result;
  END IF;
  -- La retirada de Stage1 no debe borrar la operacion PROFILE_UPDATE.
  IF NOT EXISTS(
     SELECT 1 FROM public.lf_router_action_registry
     WHERE asset_type='PERFIL' AND action_code='PROFILE_UPDATE'
       AND operation_code='ACTUALIZACION_PERFIL_LF' AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'BLOCK_PROFILE_UPDATE_REGISTRY_DRIFT';
  END IF;
END
$verify$;
COMMIT;
