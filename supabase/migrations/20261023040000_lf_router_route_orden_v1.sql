-- LF Router ACT-0001: correccion de orden en lf_router_route_v1 (nivel 1).
-- Hallazgo de la prueba en la base real: al unir las formas de busqueda, el desempate alfabetico por codigo ponia
-- delante candidatos peores que los que ya devolvia lf_router_search_v1 (ej. DNI en logs, Yape monto inicial,
-- perfil del director de producto). Ahora el desempate respeta la posicion que dio la busqueda (mejor_posicion).
-- Solo cambia el orden; CREATE OR REPLACE conserva los permisos. Se aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_route_v1(p_stage1 jsonb, p_caller jsonb DEFAULT '{}'::jsonb, p_nivel2_consentido boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v jsonb; v_formas text[]; v_hint text; v_cands jsonb; v_n int; v_l2 jsonb; v_d jsonb;
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

DO $t$
DECLARE r jsonb;
  b jsonb := '{"schema_version":"LF_ROUTER_STAGE1_V1","texto_original":"x","es_operacion":true,"respuesta_directa":false,"sistema":"LF","accion":null,"sujeto":"s","correcciones":[],"formas_busqueda":["f"],"ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,"downstream_execution_allowed":false}'::jsonb;
BEGIN
  r := public.lf_router_route_v1(b || '{"texto_original":"regla para no exponer el DNI en logs","formas_busqueda":["regla para no exponer el DNI en logs"]}');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'REG_SEG_003' THEN RAISE EXCEPTION 'ORDEN dni: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"Yape solo para el monto inicial","formas_busqueda":["Yape solo para el monto inicial"]}');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'REG_CHK_CUO_003' THEN RAISE EXCEPTION 'ORDEN yape: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"el creador de skills","formas_busqueda":["creador de skills","skill creator"]}');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'ACT-0043' THEN RAISE EXCEPTION 'ORDEN creador: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"el perfil del director de producto","formas_busqueda":["perfil del director de producto","product director profile"]}');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF' THEN RAISE EXCEPTION 'ORDEN director: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"crear history de usuario","formas_busqueda":["historias de usuario","user stories"]}');
  IF r->>'paso' IS DISTINCT FROM 'CANDIDATO_UNICO' THEN RAISE EXCEPTION 'ORDEN unico: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'ORDEN efecto: %', r; END IF;
END
$t$;

COMMIT;
