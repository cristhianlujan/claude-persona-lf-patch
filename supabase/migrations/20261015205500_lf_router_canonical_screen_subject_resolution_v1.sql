-- LF ACT-0001: screen subject is grounded in existing lf_ops hierarchy, not ADAPTER keywords.
-- Deterministic subject grounding is NOT a semantic scope attestation or an executable screen operation.
-- Canonical route: ACT-0001 -> ACTUALIZACION_DB_LF -> Merge Train.
-- Existing Router remains the only authority; no operation, asset, policy, or screen changes.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM lf_ops.pantallas WHERE codigo='B2B-AUTH-001' AND activa)<>1 THEN
   RAISE EXCEPTION 'LF_SCREEN_ROUTER_TARGET_SOURCE_NOT_CURRENT'; END IF;
 IF (SELECT count(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0 THEN
   RAISE EXCEPTION 'LF_SCREEN_ROUTER_SCREEN_ROUTE_CHANGED'; END IF;
END $pre$;
SAVEPOINT screen_router_probe;
DO $install$
DECLARE
  old_fn text;
  exact_anchor text := $anchor$  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');$anchor$;
  screen_resolution_block text := $new_block$
  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.
  -- A screen reference cannot fall through to ADAPTER keyword scoring. This
  -- is *not* a semantic LLM verdict or authorization to edit a screen.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND v_req ~ '(^| )(pantalla|screen)( |$)'
     AND NOT (
       v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|link)( |$)'
       AND v_req ~ '(^| )(regla|policy)( |$)'
     )
     AND NOT v_req ~ '^(actualiza|actualizar|modifica|modificar|corrige|corregir) (el |la )?(adapter|perfil|profile|skill)( |$)'
  THEN
    DECLARE
      screen_count integer := 0;
      screens jsonb := '[]'::jsonb;
      one_screen jsonb;
      requested_action text;
      screen_route_exists boolean;
      primary_cta_count integer := 0;
      primary_cta_elements jsonb := '[]'::jsonb;
    BEGIN
      WITH grounded AS (
        SELECT
          p.id AS pantalla_id, p.codigo, p.nombre, p.module_code,
          m.app_shell_code, m.is_active AS module_is_active
        FROM lf_ops.pantallas p
        JOIN lf_ops.modulos m ON m.module_id=p.module_id
        JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
        WHERE p.activa
          AND (
            position(
              ' '||btrim(regexp_replace(translate(lower(p.codigo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' '
            )>0
            OR
            position(
              ' '||btrim(regexp_replace(translate(lower(p.nombre),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' '
            )>0
          )
      )
      SELECT count(*),
        coalesce(jsonb_agg(
          jsonb_build_object(
            'pantalla_id',pantalla_id,
            'codigo_activo',codigo,
            'nombre_canonico',nombre,
            'tipo_activo','PANTALLA',
            'module_code',module_code,
            'app_shell_code',app_shell_code,
            'module_is_active',module_is_active
          ) ORDER BY codigo
        ),'[]'::jsonb)
      INTO screen_count, screens
      FROM grounded;

      IF screen_count=0 THEN
        RETURN jsonb_build_object(
          'router','ACT-0001','source','SUPABASE','status','BLOCKED',
          'blocking_code','BLOCK_SCREEN_TARGET_IDENTITY_UNRESOLVED',
          'asset_type','PANTALLA','action_code',null,'operation_code',null,
          'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
          'semantic_resolution_required',true,
          'semantic_gap_code','CANONICAL_SCREEN_TARGET_UNRESOLVED',
          'downstream_execution_allowed',false
        );
      END IF;
      IF screen_count<>1 THEN
        RETURN jsonb_build_object(
          'router','ACT-0001','source','SUPABASE','status','BLOCKED',
          'blocking_code','BLOCK_SCREEN_TARGET_AMBIGUOUS',
          'asset_type','PANTALLA','action_code',null,'operation_code',null,
          'screen_match_count',screen_count,'candidate_screens',screens,
          'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
          'semantic_resolution_required',true,
          'semantic_gap_code','CANONICAL_SCREEN_TARGET_AMBIGUOUS',
          'downstream_execution_allowed',false
        );
      END IF;

      one_screen := screens->0;
      -- Resolve an explicitly named primary button using the canonical
      -- UI element register, independent of scope/effect authorization.
      IF v_req ~ '(^| )boton( |$)'
         AND v_req ~ '(^| )(principal|primario)( |$)'
      THEN
        SELECT count(*),
          coalesce(jsonb_agg(
            jsonb_build_object(
              'element_id',e.element_id,'element_code',e.element_code,
              'element_role',e.element_role,'context_key',e.context_key,
              'semantic_binding_status',e.semantic_binding_status,
              'status',e.status
            ) ORDER BY e.element_id
          ),'[]'::jsonb)
        INTO primary_cta_count,primary_cta_elements
        FROM lf_ops.pantalla_elementos e
        WHERE e.pantalla_id=(one_screen->>'pantalla_id')::integer
          AND e.element_role='PRIMARY_CTA'
          AND e.semantic_binding_status='RESOLVED_ID'
          AND e.required_for_implementation;
      END IF;
      -- The positive action must appear at the start; a verb in a negated
      -- constraint later in the request is not positive action authority.
      requested_action := CASE WHEN v_req ~
        '^(cambiar|cambia|actualizar|actualiza|modificar|modifica|corregir|corrige|editar|edita|ajustar|ajusta|reemplazar|reemplaza)( |$)'
        THEN 'UPDATE' ELSE NULL END;
      SELECT EXISTS (
        SELECT 1 FROM public.lf_router_action_registry r
        WHERE r.asset_type='PANTALLA' AND r.action_code=requested_action AND r.status='ACTIVE'
      ) INTO screen_route_exists;

      RETURN jsonb_build_object(
        'router','ACT-0001','source','SUPABASE','status','BLOCKED',
        'blocking_code',CASE
          WHEN requested_action IS NULL THEN 'BLOCK_SCREEN_ACTION_SEMANTIC_ATTESTATION_REQUIRED'
          WHEN NOT screen_route_exists THEN 'BLOCK_OPERATION_NOT_REGISTERED'
          ELSE 'BLOCK_SCREEN_OPERATION_CONSUMER_NOT_INTEGRATED'
        END,
        'asset_type','PANTALLA','action_code',requested_action,
        'operation_code',null,'asset',one_screen,
        'candidate_asset_code',one_screen->>'codigo_activo',
        'discovery_source','lf_ops.pantallas -> lf_ops.modulos -> lf_ops.app_shells',
        'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
        'target_resolution','CANONICAL_SCREEN_GROUNDED',
        'target_count',1,
        'screen_element',case when primary_cta_count=1 then primary_cta_elements->0 else null end,
        'element_resolution',case when primary_cta_count=1 then 'CANONICAL_ELEMENT_GROUNDED' else 'UNATTESTED' end,
        'semantic_resolution_required',true,
        'semantic_gap_code','EFFECT_SCOPE_ATTESTATION_REQUIRED',
        'semantic_scope_state','UNATTESTED',
        'downstream_execution_allowed',false
      );
    END;
  END IF;
$new_block$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO old_fn;
  IF md5(old_fn)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN
    RAISE EXCEPTION 'LF_SCREEN_ROUTER_SOURCE_DRIFT expected=0c41d9fb4e27c6ddfebbc356a7f22d66 actual=%',md5(old_fn);
  END IF;
  IF (length(old_fn)-length(replace(old_fn,exact_anchor,'')))<>length(exact_anchor) THEN
    RAISE EXCEPTION 'LF_SCREEN_ROUTER_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(old_fn,exact_anchor,exact_anchor||E'\n'||screen_resolution_block);
END $install$;
DO $cases$
DECLARE
  x jsonb;
  item record;
  expected_sha text;
BEGIN
  FOR item IN
    SELECT * FROM (VALUES
      ('original', 'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'::text,'B2B-AUTH-001'::text,'UPDATE'::text),
      ('paraphrase', 'Actualizar solo el texto del botón de la pantalla Iniciar sesión B2B; no alterar la autenticación ni las validaciones.','B2B-AUTH-001','UPDATE'),
      ('another_screen', 'Cambiar el texto principal de la pantalla Recuperar acceso B2B sin tocar contraseña.','B2B-AUTH-002','UPDATE'),
      ('by_code', 'Modificar texto de la pantalla B2B-AUTH-001 sin tocar autenticación.','B2B-AUTH-001','UPDATE')
    ) v(case_code,input_text,screen_code,action_code)
  LOOP
    x := public.lf_router_resolve_v1(item.input_text);
    expected_sha := encode(extensions.digest(convert_to(item.input_text,'UTF8'),'sha256'),'hex');
    IF x->>'status'<>'BLOCKED'
      OR x->>'asset_type'<>'PANTALLA'
      OR x->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED'
      OR x->>'candidate_asset_code' IS DISTINCT FROM item.screen_code
      OR x->>'action_code' IS DISTINCT FROM item.action_code
      OR x->>'operation_code' IS NOT NULL
      OR x->>'request_sha256' IS DISTINCT FROM expected_sha
      OR x->>'target_resolution'<>'CANONICAL_SCREEN_GROUNDED'
      OR x->>'semantic_scope_state'<>'UNATTESTED'
      OR coalesce((x->>'downstream_execution_allowed')::boolean,true)
    THEN
      RAISE EXCEPTION 'LF_SCREEN_ROUTER_POSITIVE_FAIL:%:status=%:type=%:code=%:target=%',
         item.case_code,x->>'status',x->>'asset_type',x->>'blocking_code',x->>'candidate_asset_code';
    END IF;
  END LOOP;

  x:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.');
  IF x#>>'{screen_element,element_code}'<>'B2B_AUTH001_SUBMIT'
     OR x#>>'{screen_element,element_role}'<>'PRIMARY_CTA'
     OR x->>'element_resolution'<>'CANONICAL_ELEMENT_GROUNDED'
     OR x#>>'{asset,module_is_active}'<>'false'
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_PRIMARY_CTA_OR_MODULE_READBACK_MISMATCH'; END IF;

  x:=public.lf_router_resolve_v1('Cambiar el texto de la pantalla que no existe');
  IF x->>'status'<>'BLOCKED'
     OR x->>'asset_type'<>'PANTALLA'
     OR x->>'blocking_code'<>'BLOCK_SCREEN_TARGET_IDENTITY_UNRESOLVED'
     OR coalesce((x->>'downstream_execution_allowed')::boolean,true)
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_UNKNOWN_TARGET_NOT_BLOCKED'; END IF;

  x:=public.lf_router_resolve_v1(
    'Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER'
  );
  IF x->>'status'<>'READY_TO_EXECUTE'
     OR x->>'operation_code'<>'ACTUALIZACION_DB_LF'
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_DB_EXPLICIT_REGRESSION'; END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_UNEXPECTED_SCREEN_ROUTE_ACTIVATION'; END IF;
END $cases$;
ROLLBACK TO SAVEPOINT screen_router_probe;
DO $rollback_proof$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'0c41d9fb4e27c6ddfebbc356a7f22d66'
 THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_ROLLBACK_DDL_RESIDUE'; END IF;
END $rollback_proof$;
RELEASE SAVEPOINT screen_router_probe;
DO $install$
DECLARE
  old_fn text;
  exact_anchor text := $anchor$  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');$anchor$;
  screen_resolution_block text := $new_block$
  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.
  -- A screen reference cannot fall through to ADAPTER keyword scoring. This
  -- is *not* a semantic LLM verdict or authorization to edit a screen.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND v_req ~ '(^| )(pantalla|screen)( |$)'
     AND NOT (
       v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|link)( |$)'
       AND v_req ~ '(^| )(regla|policy)( |$)'
     )
     AND NOT v_req ~ '^(actualiza|actualizar|modifica|modificar|corrige|corregir) (el |la )?(adapter|perfil|profile|skill)( |$)'
  THEN
    DECLARE
      screen_count integer := 0;
      screens jsonb := '[]'::jsonb;
      one_screen jsonb;
      requested_action text;
      screen_route_exists boolean;
      primary_cta_count integer := 0;
      primary_cta_elements jsonb := '[]'::jsonb;
    BEGIN
      WITH grounded AS (
        SELECT
          p.id AS pantalla_id, p.codigo, p.nombre, p.module_code,
          m.app_shell_code, m.is_active AS module_is_active
        FROM lf_ops.pantallas p
        JOIN lf_ops.modulos m ON m.module_id=p.module_id
        JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
        WHERE p.activa
          AND (
            position(
              ' '||btrim(regexp_replace(translate(lower(p.codigo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' '
            )>0
            OR
            position(
              ' '||btrim(regexp_replace(translate(lower(p.nombre),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' '
            )>0
          )
      )
      SELECT count(*),
        coalesce(jsonb_agg(
          jsonb_build_object(
            'pantalla_id',pantalla_id,
            'codigo_activo',codigo,
            'nombre_canonico',nombre,
            'tipo_activo','PANTALLA',
            'module_code',module_code,
            'app_shell_code',app_shell_code,
            'module_is_active',module_is_active
          ) ORDER BY codigo
        ),'[]'::jsonb)
      INTO screen_count, screens
      FROM grounded;

      IF screen_count=0 THEN
        RETURN jsonb_build_object(
          'router','ACT-0001','source','SUPABASE','status','BLOCKED',
          'blocking_code','BLOCK_SCREEN_TARGET_IDENTITY_UNRESOLVED',
          'asset_type','PANTALLA','action_code',null,'operation_code',null,
          'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
          'semantic_resolution_required',true,
          'semantic_gap_code','CANONICAL_SCREEN_TARGET_UNRESOLVED',
          'downstream_execution_allowed',false
        );
      END IF;
      IF screen_count<>1 THEN
        RETURN jsonb_build_object(
          'router','ACT-0001','source','SUPABASE','status','BLOCKED',
          'blocking_code','BLOCK_SCREEN_TARGET_AMBIGUOUS',
          'asset_type','PANTALLA','action_code',null,'operation_code',null,
          'screen_match_count',screen_count,'candidate_screens',screens,
          'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
          'semantic_resolution_required',true,
          'semantic_gap_code','CANONICAL_SCREEN_TARGET_AMBIGUOUS',
          'downstream_execution_allowed',false
        );
      END IF;

      one_screen := screens->0;
      -- Resolve an explicitly named primary button using the canonical
      -- UI element register, independent of scope/effect authorization.
      IF v_req ~ '(^| )boton( |$)'
         AND v_req ~ '(^| )(principal|primario)( |$)'
      THEN
        SELECT count(*),
          coalesce(jsonb_agg(
            jsonb_build_object(
              'element_id',e.element_id,'element_code',e.element_code,
              'element_role',e.element_role,'context_key',e.context_key,
              'semantic_binding_status',e.semantic_binding_status,
              'status',e.status
            ) ORDER BY e.element_id
          ),'[]'::jsonb)
        INTO primary_cta_count,primary_cta_elements
        FROM lf_ops.pantalla_elementos e
        WHERE e.pantalla_id=(one_screen->>'pantalla_id')::integer
          AND e.element_role='PRIMARY_CTA'
          AND e.semantic_binding_status='RESOLVED_ID'
          AND e.required_for_implementation;
      END IF;
      -- The positive action must appear at the start; a verb in a negated
      -- constraint later in the request is not positive action authority.
      requested_action := CASE WHEN v_req ~
        '^(cambiar|cambia|actualizar|actualiza|modificar|modifica|corregir|corrige|editar|edita|ajustar|ajusta|reemplazar|reemplaza)( |$)'
        THEN 'UPDATE' ELSE NULL END;
      SELECT EXISTS (
        SELECT 1 FROM public.lf_router_action_registry r
        WHERE r.asset_type='PANTALLA' AND r.action_code=requested_action AND r.status='ACTIVE'
      ) INTO screen_route_exists;

      RETURN jsonb_build_object(
        'router','ACT-0001','source','SUPABASE','status','BLOCKED',
        'blocking_code',CASE
          WHEN requested_action IS NULL THEN 'BLOCK_SCREEN_ACTION_SEMANTIC_ATTESTATION_REQUIRED'
          WHEN NOT screen_route_exists THEN 'BLOCK_OPERATION_NOT_REGISTERED'
          ELSE 'BLOCK_SCREEN_OPERATION_CONSUMER_NOT_INTEGRATED'
        END,
        'asset_type','PANTALLA','action_code',requested_action,
        'operation_code',null,'asset',one_screen,
        'candidate_asset_code',one_screen->>'codigo_activo',
        'discovery_source','lf_ops.pantallas -> lf_ops.modulos -> lf_ops.app_shells',
        'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
        'target_resolution','CANONICAL_SCREEN_GROUNDED',
        'target_count',1,
        'screen_element',case when primary_cta_count=1 then primary_cta_elements->0 else null end,
        'element_resolution',case when primary_cta_count=1 then 'CANONICAL_ELEMENT_GROUNDED' else 'UNATTESTED' end,
        'semantic_resolution_required',true,
        'semantic_gap_code','EFFECT_SCOPE_ATTESTATION_REQUIRED',
        'semantic_scope_state','UNATTESTED',
        'downstream_execution_allowed',false
      );
    END;
  END IF;
$new_block$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO old_fn;
  IF md5(old_fn)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN
    RAISE EXCEPTION 'LF_SCREEN_ROUTER_SOURCE_DRIFT expected=0c41d9fb4e27c6ddfebbc356a7f22d66 actual=%',md5(old_fn);
  END IF;
  IF (length(old_fn)-length(replace(old_fn,exact_anchor,'')))<>length(exact_anchor) THEN
    RAISE EXCEPTION 'LF_SCREEN_ROUTER_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(old_fn,exact_anchor,exact_anchor||E'\n'||screen_resolution_block);
END $install$;
DO $cases$
DECLARE
  x jsonb;
  item record;
  expected_sha text;
BEGIN
  FOR item IN
    SELECT * FROM (VALUES
      ('original', 'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'::text,'B2B-AUTH-001'::text,'UPDATE'::text),
      ('paraphrase', 'Actualizar solo el texto del botón de la pantalla Iniciar sesión B2B; no alterar la autenticación ni las validaciones.','B2B-AUTH-001','UPDATE'),
      ('another_screen', 'Cambiar el texto principal de la pantalla Recuperar acceso B2B sin tocar contraseña.','B2B-AUTH-002','UPDATE'),
      ('by_code', 'Modificar texto de la pantalla B2B-AUTH-001 sin tocar autenticación.','B2B-AUTH-001','UPDATE')
    ) v(case_code,input_text,screen_code,action_code)
  LOOP
    x := public.lf_router_resolve_v1(item.input_text);
    expected_sha := encode(extensions.digest(convert_to(item.input_text,'UTF8'),'sha256'),'hex');
    IF x->>'status'<>'BLOCKED'
      OR x->>'asset_type'<>'PANTALLA'
      OR x->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED'
      OR x->>'candidate_asset_code' IS DISTINCT FROM item.screen_code
      OR x->>'action_code' IS DISTINCT FROM item.action_code
      OR x->>'operation_code' IS NOT NULL
      OR x->>'request_sha256' IS DISTINCT FROM expected_sha
      OR x->>'target_resolution'<>'CANONICAL_SCREEN_GROUNDED'
      OR x->>'semantic_scope_state'<>'UNATTESTED'
      OR coalesce((x->>'downstream_execution_allowed')::boolean,true)
    THEN
      RAISE EXCEPTION 'LF_SCREEN_ROUTER_POSITIVE_FAIL:%:status=%:type=%:code=%:target=%',
         item.case_code,x->>'status',x->>'asset_type',x->>'blocking_code',x->>'candidate_asset_code';
    END IF;
  END LOOP;

  x:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.');
  IF x#>>'{screen_element,element_code}'<>'B2B_AUTH001_SUBMIT'
     OR x#>>'{screen_element,element_role}'<>'PRIMARY_CTA'
     OR x->>'element_resolution'<>'CANONICAL_ELEMENT_GROUNDED'
     OR x#>>'{asset,module_is_active}'<>'false'
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_PRIMARY_CTA_OR_MODULE_READBACK_MISMATCH'; END IF;

  x:=public.lf_router_resolve_v1('Cambiar el texto de la pantalla que no existe');
  IF x->>'status'<>'BLOCKED'
     OR x->>'asset_type'<>'PANTALLA'
     OR x->>'blocking_code'<>'BLOCK_SCREEN_TARGET_IDENTITY_UNRESOLVED'
     OR coalesce((x->>'downstream_execution_allowed')::boolean,true)
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_UNKNOWN_TARGET_NOT_BLOCKED'; END IF;

  x:=public.lf_router_resolve_v1(
    'Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER'
  );
  IF x->>'status'<>'READY_TO_EXECUTE'
     OR x->>'operation_code'<>'ACTUALIZACION_DB_LF'
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_DB_EXPLICIT_REGRESSION'; END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
  THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_UNEXPECTED_SCREEN_ROUTE_ACTIVATION'; END IF;
END $cases$;
DO $readback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))='0c41d9fb4e27c6ddfebbc356a7f22d66'
 THEN RAISE EXCEPTION 'LF_SCREEN_ROUTER_NOT_APPLIED'; END IF;
END $readback$;
COMMIT;
