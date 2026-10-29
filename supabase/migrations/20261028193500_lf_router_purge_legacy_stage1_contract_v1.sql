-- ACT-0001: purga total del campo obsoleto en el contrato activo LF_ROUTER_STAGE1_V2.
-- Cambia solo tres funciones vigentes; migraciones anteriores son historicas e inmutables.
-- Solo por LF Migration Merge Train. No direct SQL, no ACL, no schema DDL fuera del Train.
-- Parches fail-closed: md5 exactos del runtime tras PR #3283.
BEGIN;
DO $cleanup$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  v_def := pg_get_functiondef('public.lf_router_stage1_validate_v2(jsonb)'::regprocedure);
  IF md5(v_def) <> 'ce59e03ea955279c4664ec3c5f3619da' THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_DRIFT_lf_router_stage1_validate_v2';
  END IF;
  v_old := $old$  v_transversal text;
$old$;
  v_new := $new$$new$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage1_decl';
  END IF;
  v_def := replace(v_def,v_old,v_new);
  v_old := $old$  v_transversal := nullif(btrim(coalesce(p_stage1->>'ruta_transversal','')),'');
$old$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage1_read';
  END IF;
  v_def := replace(v_def,v_old,'');
  v_old := $old$    IF v_channel IS NOT NULL OR v_business IS NOT NULL OR v_transversal IS NOT NULL THEN$old$;
  v_new := $new$    IF v_channel IS NOT NULL OR v_business IS NOT NULL THEN$new$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage1_noop';
  END IF;
  v_def := replace(v_def,v_old,v_new);
  v_old := $old$    IF v_transversal IS NOT NULL THEN
      v_codes := array_append(v_codes,'RUTA_TRANSVERSAL_INVALIDA');
    END IF;
$old$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage1_special_error';
  END IF;
  v_def := replace(v_def,v_old,'');
  v_old := $old$  IF p_stage1 ? 'sistema' THEN
    v_codes := array_append(v_codes,'CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2');
  END IF;
$old$;
  v_new := $new$  IF p_stage1 ? 'sistema' THEN
    v_codes := array_append(v_codes,'CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2');
  END IF;
  -- Closed schema: all inputs not declared in the active contract fail closed.
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_stage1) AS field(field_name)
    WHERE field.field_name <> ALL (ARRAY[
      'schema_version','texto_original','es_operacion','ambiguo',
      'respuesta_directa','sujeto','accion','formas_busqueda',
      'alternativas','correcciones','pregunta_usuario','capability_hint',
      'downstream_execution_allowed','canal_candidato','negocio_codigo',
      'negocios_afectados','razon_seleccion','alcance'
    ]::text[])
  ) THEN
    v_codes := array_append(v_codes,'CAMPO_NO_PERMITIDO_EN_V2');
  END IF;
$new$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage1_field_schema';
  END IF;
  EXECUTE replace(v_def,v_old,v_new);

  v_def := pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  IF md5(v_def) <> '68a77208303780f240d31c4e505f1502' THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_DRIFT_lf_router_route_v1';
  END IF;
  v_old := $old$  v_transversal text;
$old$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage2_decl';
  END IF;
  v_def := replace(v_def,v_old,'');
  v_old := $old$    v_transversal := nullif(p_stage1->>'ruta_transversal','');
$old$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage2_read';
  END IF;
  v_def := replace(v_def,v_old,'');
  v_old := $old$      'alcance',v_scope,
      'ruta_transversal',v_transversal
$old$;
  v_new := $new$      'alcance',v_scope
$new$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage2_output';
  END IF;
  v_def := replace(v_def,v_old,v_new);
  v_old := $old$Resolver autoridad por negocio antes de habilitar una ruta transversal.$old$;
  v_new := $new$Resolver autoridad por negocio antes de habilitar otras operaciones.$new$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_stage2_message';
  END IF;
  EXECUTE replace(v_def,v_old,v_new);

  v_def := pg_get_functiondef('public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure);
  IF md5(v_def) <> 'd1038f29f9887b4945a0ce54c0d724b0' THEN
    RAISE EXCEPTION 'BLOCK_SOURCE_DRIFT_lf_router_profile_after_selection_v1';
  END IF;
  v_old := $old$     OR nullif(p_stage1->>'ruta_transversal','') IS NOT NULL
$old$;
  IF (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_ANCHOR_NOT_UNIQUE_profile_after_selection';
  END IF;
  EXECUTE replace(v_def,v_old,'');

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'lf_router_stage1_validate_v2','lf_router_route_v1',
      'lf_router_profile_after_selection_v1','lf_router_route_transition_resolve_v1'
    ) AND (pg_get_functiondef(p.oid) ILIKE '%ruta_transversal%'
          OR pg_get_functiondef(p.oid) ILIKE '%GESTION_ACTIVOS_IA%'
          OR pg_get_functiondef(p.oid) ILIKE '%RUTA_TRANSVERSAL_INVALIDA%')
  ) THEN
    RAISE EXCEPTION 'BLOCK_RETIRED_ROUTE_STILL_IN_ACTIVE_FUNCTIONS';
  END IF;
END
$cleanup$;

DO $regression$
DECLARE
  v_base jsonb;
  v_channel text;
  v_r jsonb;
BEGIN
  v_base := jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Consultar un estado de oferta en LF',
    'es_operacion',true,'respuesta_directa',false,'ambiguo',false,
    'sujeto','oferta','formas_busqueda',jsonb_build_array('estado de oferta'),
    'alternativas','[]'::jsonb,'correcciones','[]'::jsonb,
    'negocios_afectados','[]'::jsonb,'negocio_codigo','LF',
    'razon_seleccion','Consulta de estado actual',
    'downstream_execution_allowed',false
  );
  FOR v_channel IN SELECT unnest(ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']) LOOP
    v_r := public.lf_router_stage1_validate_v2(
      v_base || jsonb_build_object('canal_candidato',v_channel)
    );
    IF v_r->>'valid' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'BLOCK_CHANNEL_REGRESSION_%_%',v_channel,v_r;
    END IF;
    v_r := public.lf_router_route_v1(
      v_base || jsonb_build_object('canal_candidato',v_channel),
      '{}'::jsonb,false
    );
    IF v_r ? 'ruta_transversal' THEN
      RAISE EXCEPTION 'BLOCK_RETIRED_FIELD_STILL_IN_OUTPUT_%',v_r;
    END IF;
  END LOOP;
  -- An old field now fails on generic schema validation, never on special-route logic.
  v_r := public.lf_router_stage1_validate_v2(
    v_base || jsonb_build_object('canal_candidato','OPERACIONES',
                                 'ruta_transversal','GESTION_ACTIVOS_IA')
  );
  IF v_r->>'valid' IS DISTINCT FROM 'false'
     OR NOT(v_r->'codes' ? 'CAMPO_NO_PERMITIDO_EN_V2')
     OR v_r->'codes' ? 'RUTA_TRANSVERSAL_INVALIDA' THEN
    RAISE EXCEPTION 'BLOCK_RETIRED_FIELD_NOT_GENERALLY_REJECTED_%',v_r;
  END IF;
  IF NOT EXISTS (
      SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='PERFIL' AND action_code='PROFILE_UPDATE'
        AND operation_code='ACTUALIZACION_PERFIL_LF' AND status='ACTIVE'
  ) OR NOT EXISTS (
      SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='SKILL' AND action_code='SKILL_UPDATE'
        AND operation_code='ACTUALIZACION_SKILL_LF' AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'BLOCK_EXISTING_OPERATION_REGISTRY_DRIFT';
  END IF;
END
$regression$;
COMMIT;
