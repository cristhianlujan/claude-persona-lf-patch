-- LF Router ACT-0001: lf_router_route_v1 ya no deja la modificacion en callejon sin salida.
-- Hallazgo: para "cambiar el texto del boton de Iniciar sesion B2B" lf_router_resolve_v1 resuelve la pantalla B2B-AUTH-001 y
-- propone PERFIL-UI-ARCHITECT (READ_ONLY), pero termina en BLOCKED/BLOCK_EXECUTOR_CAPABILITY_UNATTESTED sin decir que hacer,
-- y la continuacion semantica rechaza pantallas (BLOCK_SEMANTIC_RESUME_TARGET_NOT_CANONICAL_ASSET).
-- Ahora route_v1 devuelve paso PROPUESTA_PERFIL con el paquete para que el perfil trabaje en modo PROPUESTA (solo lectura).
-- No cambia resolve_v1 ni la continuacion semantica; downstream_execution_allowed sigue false. CREATE OR REPLACE conserva permisos.
-- Se aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_route_v1(p_stage1 jsonb, p_caller jsonb DEFAULT '{}'::jsonb, p_nivel2_consentido boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v_rs jsonb; v jsonb; v_formas text[]; v_hint text; v_cands jsonb; v_n int; v_l2 jsonb; v_d jsonb;
  v_base jsonb := jsonb_build_object('schema_version','LF_ROUTER_ROUTE_V1','router','ACT-0001','downstream_execution_allowed',false);
BEGIN
  v := public.lf_router_stage1_validate_v1(p_stage1);
  IF (v->>'valid')::boolean IS NOT TRUE THEN
    RETURN v_base || jsonb_build_object('paso','INVALID_STAGE1','codigos',v->'codes',
      'motivo_es','La salida de la etapa 1 no cumple el contrato; no se busca ni se despacha nada.',
      'siguiente_paso_es','Rehacer la etapa 1 corrigiendo los codigos indicados.');
  END IF;
  IF (p_stage1->>'es_operacion')::boolean IS FALSE THEN
    RETURN v_base || jsonb_build_object('paso','DIRECT_ANSWER','motivo_es','No es una operacion: se responde sin inventario.',
      'siguiente_paso_es','Responder directamente al usuario.');
  END IF;
  IF (p_stage1->>'ambiguo')::boolean IS TRUE THEN
    RETURN v_base || jsonb_build_object('paso','ASK_USER','pregunta_usuario',p_stage1->'pregunta_usuario','alternativas',p_stage1->'alternativas',
      'motivo_es','La solicitud tiene mas de una lectura posible.','siguiente_paso_es','Hacer esa unica pregunta y repetir la etapa 1 con la respuesta.');
  END IF;
  IF p_stage1->>'sistema' <> 'LF' THEN
    RETURN v_base || jsonb_build_object('paso','SYSTEM_NOT_SUPPORTED','sistema',p_stage1->'sistema',
      'motivo_es','Por ahora el Router solo atiende LF.','siguiente_paso_es','Informar al usuario; no se busca ni se despacha.');
  END IF;

  v_hint := nullif(p_stage1->>'capability_hint','');
  IF v_hint IS NOT NULL THEN
    v_d := public.lf_router_dispatch_v1(p_stage1->>'texto_original', v_hint, coalesce(p_caller,'{}'::jsonb));
    RETURN v_base || jsonb_build_object('paso','DISPATCHED','despacho',v_d,
      'motivo_es','La etapa 1 indico una capacidad; el despacho responde con el contrato uniforme.',
      'siguiente_paso_es','Seguir lo que indica el despacho (permisos, pasos, siguiente paso).');
  END IF;

  -- Modificaciones: si el Router ya resuelve el sujeto y el unico bloqueo es que el perfil candidato es de solo lectura,
  -- no se devuelve un callejon sin salida: el perfil trabaja en modo PROPUESTA (solo lectura) y aplicar queda en la ruta gobernada.
  IF coalesce(p_stage1->>'accion','') ~* '(cambi|modific|actualiz|edit|correg|renombr|update|change|modify|edit|fix|rename)' THEN
    v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
    IF v_rs->>'subject_binding_state' = 'RESOLVED'
       AND jsonb_array_length(coalesce(v_rs->'executor_candidates','[]'::jsonb)) > 0
       AND v_rs->>'blocking_code' = 'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED' THEN
      RETURN v_base || jsonb_build_object('paso','PROPUESTA_PERFIL',
        'sujeto', v_rs->'subject_candidates',
        'perfil_candidato', v_rs#>'{executor_candidates,0}',
        'modo','PROPUESTA_SOLO_LECTURA',
        'instruccion_literal', p_stage1->>'texto_original',
        'alcance_permitido', (SELECT coalesce(jsonb_agg(s->>'screen_code'),'[]'::jsonb) FROM jsonb_array_elements(v_rs->'subject_candidates') s),
        'respeta_literalmente', 'Todo lo que la instruccion dice que NO se toque queda fuera de alcance.',
        'router_resolve', jsonb_build_object('status',v_rs->>'status','blocking_code',v_rs->>'blocking_code','semantic_gap_code',v_rs->>'semantic_gap_code','request_sha256',v_rs->>'request_sha256'),
        'aplicar_requiere','Ejecucion gobernada del perfil (EJECUCION_PERFIL_LF) y la operacion de cambio autorizada; esta propuesta no aplica nada.',
        'motivo_es','El sujeto esta resuelto y el perfil candidato es de solo lectura: el perfil debe trabajarlo y devolver una propuesta, no se detiene en bloqueo.',
        'siguiente_paso_es','Entregar este paquete al perfil candidato en modo PROPUESTA; devolver al usuario el cambio propuesto para su aprobacion.');
    END IF;
  END IF;

  SELECT array_agg(e#>>'{}') INTO v_formas FROM jsonb_array_elements(p_stage1->'formas_busqueda') e;

  -- Nivel 1: union de las formas, sin duplicados; orden: exacto, cobertura, apariciones, codigo
  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'exacto')::boolean DESC, (x->>'cobertura')::numeric DESC, (x->>'apariciones')::int DESC, (x->>'mejor_posicion')::int ASC, x->>'codigo'),'[]'::jsonb)
    INTO v_cands
    FROM (
      SELECT jsonb_build_object('origen',min(c->>'origen'),'codigo',c->>'codigo','tipo',min(c->>'tipo'),'titulo',min(c->>'titulo'),
               'exacto',bool_or((c->>'exacto')::boolean),
               'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
               'apariciones',count(*),'mejor_posicion',min(pos)) AS x
        FROM unnest(v_formas) f,
             LATERAL jsonb_array_elements(public.lf_router_search_v1(f,5)->'candidatos') WITH ORDINALITY AS t(c,pos)
       GROUP BY c->>'codigo'
    ) s;
  v_n := jsonb_array_length(v_cands);
  IF v_n = 1 OR (v_n > 1 AND (v_cands->0->>'exacto')::boolean IS TRUE AND (v_cands->1->>'exacto')::boolean IS NOT TRUE) THEN
    RETURN v_base || jsonb_build_object('paso','CANDIDATO_UNICO','candidatos',jsonb_build_array(v_cands->0),
      'motivo_es','El nivel 1 dio un solo candidato (o una coincidencia exacta de codigo). Es una pista, no una decision.',
      'siguiente_paso_es','Quien decide confirma el candidato y, si corresponde, pide el despacho de la capacidad.');
  ELSIF v_n > 1 THEN
    RETURN v_base || jsonb_build_object('paso','ELEGIR_O_PROFUNDIZAR','candidatos',v_cands,
      'sondeo_sugerido',jsonb_build_object('leer_juntos',(SELECT jsonb_agg(x->>'codigo') FROM (SELECT x FROM jsonb_array_elements(v_cands) x LIMIT 3) t),
         'max_sondeos_por_duda',3,'cuarto_sondeo_requiere_autorizacion_del_propietario',true,'solo_lectura',true),
      'motivo_es','El nivel 1 dio varios candidatos validos.',
      'siguiente_paso_es','Quien decide elige uno, o pide leer el detalle de los 3 primeros; si sigue la duda, hacer una sola pregunta al usuario.');
  END IF;

  -- Nivel 1 vacio: nivel 2 solo con consentimiento
  IF NOT coalesce(p_nivel2_consentido,false) THEN
    RETURN v_base || jsonb_build_object('paso','NIVEL_2_CONSENTIMIENTO','candidatos','[]'::jsonb,
      'pregunta_usuario','Busque en el inventario y no lo encuentro. ¿Busco fuera del inventario (repo y tablas, solo lectura)? Si puedes, dime un detalle: donde esta, como se llama mas o menos o que hace.',
      'motivo_es','El nivel 1 no dio candidatos; buscar fuera del inventario requiere avisar y recibir consentimiento.',
      'siguiente_paso_es','Hacer esa pregunta; con el si, volver a llamar con consentimiento (y el detalle del usuario en la etapa 1).');
  END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'coinciden')::int DESC, x->>'ref'),'[]'::jsonb) INTO v_l2
    FROM (SELECT DISTINCT ON (c->>'ref') c AS x
            FROM unnest(v_formas) f, LATERAL jsonb_array_elements(public.lf_router_search_nivel2_v1(f,5)->'candidatos') c
           ORDER BY c->>'ref', (c->>'coinciden')::int DESC) d;
  RETURN v_base || jsonb_build_object('paso','NIVEL_2_RESULTADO',
    'resultado', CASE WHEN jsonb_array_length(v_l2)>0 THEN 'ENCONTRADO_FUERA_DE_INVENTARIO' ELSE 'NO_ENCONTRADO_EN_INDICE' END,
    'candidatos', (SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM (SELECT x FROM jsonb_array_elements(v_l2) x LIMIT 5) t),
    'hueco_inventario_sugerido', jsonb_array_length(v_l2)>0,
    'tambien_buscar_en_repo', true,
    'motivo_es','Son pistas fuera del inventario de gobierno: evidencia de que algo existe, no permiso ni decision.',
    'siguiente_paso_es','Si no es lo que buscas o no hay resultados, pedir un detalle al usuario y repetir; el indice no cubre todo el repo, buscar tambien directamente en el repo.');
END
$f$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb, jsonb, boolean) IS
'ETAPA 2 del Router ACT-0001: UNICO punto de entrada. Entrada: salida de la etapa 1 (LF_ROUTER_STAGE1_V1, validada). Orden: validar -> respuesta directa / pregunta / sistema no soportado -> despacho si hay capability_hint -> modificacion con sujeto resuelto y perfil de solo lectura = PROPUESTA_PERFIL -> busqueda nivel 1 -> CANDIDATO_UNICO o ELEGIR_O_PROFUNDIZAR -> nivel 2 solo con p_nivel2_consentido=true. Cada paso trae motivo_es y siguiente_paso_es: seguirlos. Nunca ejecuta nada (downstream_execution_allowed=false); los resultados son pistas, no permiso. Manual: docs/programming-agent/LF_ROUTER_FLOW_V1.md seccion "Manual de uso de la etapa 2".';

DO $t$
DECLARE r jsonb; b jsonb := '{"schema_version":"LF_ROUTER_STAGE1_V1","texto_original":"x","es_operacion":true,"respuesta_directa":false,"sistema":"LF","accion":"cambiar","sujeto":"s","correcciones":[],"formas_busqueda":["f"],"ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,"downstream_execution_allowed":false}'::jsonb;
BEGIN
  r := public.lf_router_route_v1(b || jsonb_build_object('texto_original','Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.','sujeto','botón principal de Iniciar sesión B2B','formas_busqueda',jsonb_build_array('pantalla iniciar sesion B2B')));
  IF r->>'paso' IS DISTINCT FROM 'PROPUESTA_PERFIL' THEN RAISE EXCEPTION 'PROP paso: %', r; END IF;
  IF r#>>'{perfil_candidato,asset_code}' IS DISTINCT FROM 'PERFIL-UI-ARCHITECT' THEN RAISE EXCEPTION 'PROP perfil: %', r; END IF;
  IF r->'alcance_permitido' IS DISTINCT FROM '["B2B-AUTH-001"]'::jsonb THEN RAISE EXCEPTION 'PROP alcance: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'PROP efecto: %', r; END IF;
  -- sin accion de modificacion el flujo anterior no cambia
  r := public.lf_router_route_v1(b || '{"accion":null,"texto_original":"crear history de usuario","formas_busqueda":["historias de usuario","user stories"]}');
  IF r->>'paso' IS DISTINCT FROM 'CANDIDATO_UNICO' THEN RAISE EXCEPTION 'PROP regresion: %', r; END IF;
END
$t$;

COMMIT;
