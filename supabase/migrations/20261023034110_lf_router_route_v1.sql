-- LF Router ACT-0001: entrada unica de la etapa 2 (v1). Recibe la salida de la etapa 1 (LF_ROUTER_STAGE1_V1, hecha por el
-- modelo nativo), la valida y decide el paso: respuesta directa, pregunta, sistema no soportado, despacho de capacidad
-- (cuando hay capability_hint), candidato unico, elegir/profundizar entre varios, o nivel 2 (solo con consentimiento).
-- Solo lectura. Reutiliza lf_router_dispatch_v1, lf_router_search_v1 y lf_router_search_nivel2_v1; no crea buscadores nuevos.
-- Ningun resultado autoriza efectos (downstream_execution_allowed=false). Se aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_stage1_validate_v1(p_stage1 jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v_codes text[] := '{}';
  v_es_op jsonb; v_amb jsonb; v_formas jsonb; v_alts jsonb; v_corr jsonb; v_preg jsonb; v_hint jsonb;
  v_orig text; v_el jsonb; v_f text; v_m text[]; v_typed text[];
  v_nformas int := 0; v_nalts int := 0;
  v_code_re constant text := '\y(ACT-[0-9]{3,5}|REG_[A-Z0-9_]+|PERFIL-[A-Z0-9-]+|ADAPTER-[A-Z0-9-]+|SKILL-[A-Z0-9-]+|EDGE_FN_[A-Z0-9_]+)\y';
BEGIN
  IF p_stage1 IS NULL OR jsonb_typeof(p_stage1) <> 'object' THEN
    RETURN jsonb_build_object('valid',false,'codes',to_jsonb(ARRAY['NOT_AN_OBJECT']));
  END IF;
  IF p_stage1->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_STAGE1_V1' THEN v_codes := array_append(v_codes,'BAD_SCHEMA_VERSION'::text); END IF;
  v_orig := CASE WHEN jsonb_typeof(p_stage1->'texto_original')='string' THEN p_stage1->>'texto_original' ELSE '' END;
  IF btrim(v_orig) = '' THEN v_codes := array_append(v_codes,'ORIGINAL_TEXT_REQUIRED'::text); END IF;
  IF p_stage1->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN v_codes := array_append(v_codes,'DOWNSTREAM_EXECUTION_MUST_BE_FALSE'::text); END IF;
  v_es_op := p_stage1->'es_operacion'; v_amb := p_stage1->'ambiguo';
  IF jsonb_typeof(v_es_op) IS DISTINCT FROM 'boolean' THEN v_codes := array_append(v_codes,'ES_OPERACION_BOOL_REQUIRED'::text); END IF;
  IF jsonb_typeof(v_amb) IS DISTINCT FROM 'boolean' THEN v_codes := array_append(v_codes,'AMBIGUO_BOOL_REQUIRED'::text); END IF;

  v_formas := coalesce(p_stage1->'formas_busqueda','[]'::jsonb);
  IF jsonb_typeof(v_formas) <> 'array' OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_formas) e WHERE jsonb_typeof(e)<>'string' OR btrim(e#>>'{}')='') THEN
    v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_INVALID'::text); v_formas := '[]'::jsonb;
  END IF;
  v_alts := coalesce(p_stage1->'alternativas','[]'::jsonb);
  IF jsonb_typeof(v_alts) <> 'array' OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_alts) e WHERE jsonb_typeof(e)<>'string' OR btrim(e#>>'{}')='') THEN
    v_codes := array_append(v_codes,'ALTERNATIVAS_INVALID'::text); v_alts := '[]'::jsonb;
  END IF;
  v_nformas := jsonb_array_length(v_formas); v_nalts := jsonb_array_length(v_alts);
  v_preg := p_stage1->'pregunta_usuario';
  IF v_preg IS NOT NULL AND jsonb_typeof(v_preg) <> 'null' THEN
    IF jsonb_typeof(v_preg) <> 'string' OR btrim(v_preg#>>'{}') = '' THEN v_codes := array_append(v_codes,'PREGUNTA_INVALID'::text);
    ELSIF (length(v_preg#>>'{}') - length(translate(v_preg#>>'{}','?¿',''))) > 2 THEN v_codes := array_append(v_codes,'MORE_THAN_ONE_QUESTION'::text); END IF;
  END IF;
  v_hint := p_stage1->'capability_hint';
  IF v_hint IS NOT NULL AND jsonb_typeof(v_hint) <> 'null' THEN
    IF jsonb_typeof(v_hint) <> 'string' OR (v_hint#>>'{}') !~ '^[A-Z][A-Z0-9_]{2,63}$' THEN v_codes := array_append(v_codes,'CAPABILITY_HINT_INVALID'::text); END IF;
  END IF;
  v_corr := coalesce(p_stage1->'correcciones','[]'::jsonb);
  IF jsonb_typeof(v_corr) <> 'array' OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_corr) e
        WHERE jsonb_typeof(e)<>'object' OR jsonb_typeof(e->'de')<>'string' OR jsonb_typeof(e->'a')<>'string'
           OR btrim(e->>'de')='' OR btrim(e->>'a')='' OR lower(btrim(e->>'de')) = lower(btrim(e->>'a'))) THEN
    v_codes := array_append(v_codes,'CORRECCIONES_INVALID'::text);
  END IF;

  -- no inventar: ningun codigo de activo en las formas si el usuario no lo escribio
  SELECT coalesce(array_agg(DISTINCT upper(m[1])),'{}') INTO v_typed FROM regexp_matches(v_orig, v_code_re, 'gi') m;
  FOR v_f IN SELECT e#>>'{}' FROM jsonb_array_elements(v_formas) e LOOP
    IF EXISTS (SELECT 1 FROM regexp_matches(v_f, v_code_re, 'gi') m WHERE NOT (upper(m[1]) = ANY (v_typed))) THEN
      v_codes := array_append(v_codes,'INVENTED_ASSET_CODE'::text); EXIT;
    END IF;
  END LOOP;
  IF v_nformas > 4 THEN v_codes := array_append(v_codes,'TOO_MANY_FORMAS'::text); END IF;
  IF v_nalts > 3 THEN v_codes := array_append(v_codes,'TOO_MANY_ALTERNATIVAS'::text); END IF;

  IF v_es_op = 'false'::jsonb THEN
    IF p_stage1->'respuesta_directa' IS DISTINCT FROM 'true'::jsonb THEN v_codes := array_append(v_codes,'NON_OPERATION_REQUIRES_DIRECT_ANSWER'::text); END IF;
    IF v_nformas > 0 OR (v_hint IS NOT NULL AND jsonb_typeof(v_hint) <> 'null') THEN v_codes := array_append(v_codes,'NON_OPERATION_MUST_NOT_SEARCH'::text); END IF;
  ELSIF v_es_op = 'true'::jsonb THEN
    IF coalesce(p_stage1->>'sistema','') NOT IN ('LF','SALY','OTRO','DESCONOCIDO') THEN v_codes := array_append(v_codes,'SISTEMA_INVALID'::text); END IF;
    IF NOT (coalesce(btrim(p_stage1->>'sujeto'),'') <> '' OR coalesce(btrim(p_stage1->>'accion'),'') <> '') THEN v_codes := array_append(v_codes,'SUBJECT_OR_ACTION_REQUIRED'::text); END IF;
    IF v_nformas = 0 THEN v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_REQUIRED'::text); END IF;
    IF p_stage1->'respuesta_directa' = 'true'::jsonb THEN v_codes := array_append(v_codes,'OPERATION_CANNOT_BE_DIRECT_ANSWER'::text); END IF;
  END IF;
  IF v_amb = 'true'::jsonb AND NOT (v_nalts BETWEEN 2 AND 3 AND jsonb_typeof(v_preg)='string' AND btrim(v_preg#>>'{}')<>'') THEN
    v_codes := array_append(v_codes,'AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION'::text); END IF;
  IF v_amb = 'false'::jsonb AND v_nalts > 0 THEN v_codes := array_append(v_codes,'ALTERNATIVES_WITHOUT_AMBIGUITY'::text); END IF;

  SELECT coalesce(array_agg(DISTINCT c ORDER BY c),'{}') INTO v_codes FROM unnest(v_codes) c;
  RETURN jsonb_build_object('valid', cardinality(v_codes)=0, 'codes', to_jsonb(v_codes));
END
$f$;

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
  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'exacto')::boolean DESC, (x->>'cobertura')::numeric DESC, (x->>'apariciones')::int DESC, x->>'codigo'),'[]'::jsonb)
    INTO v_cands
    FROM (
      SELECT jsonb_build_object('origen',min(c->>'origen'),'codigo',c->>'codigo','tipo',min(c->>'tipo'),'titulo',min(c->>'titulo'),
               'exacto',bool_or((c->>'exacto')::boolean),
               'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
               'apariciones',count(*)) AS x
        FROM unnest(v_formas) f,
             LATERAL jsonb_array_elements(public.lf_router_search_v1(f,5)->'candidatos') c
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

REVOKE ALL ON FUNCTION public.lf_router_stage1_validate_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_stage1_validate_v1(jsonb) FROM %I',v_role);
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_stage1_validate_v1(jsonb) TO %I',v_role);
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

-- ensayo en la transaccion (aborta si falla); expectativas medidas antes en los datos reales
DO $t$
DECLARE
  r jsonb;
  b jsonb := '{"schema_version":"LF_ROUTER_STAGE1_V1","texto_original":"x","es_operacion":true,"respuesta_directa":false,"sistema":"LF","accion":null,"sujeto":"s","correcciones":[],"formas_busqueda":["f"],"ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,"downstream_execution_allowed":false}'::jsonb;
BEGIN
  r := public.lf_router_route_v1(b || '{"texto_original":"¿qué hora es en Lima?","es_operacion":false,"respuesta_directa":true,"formas_busqueda":[],"sujeto":null}');
  IF r->>'paso' <> 'DIRECT_ANSWER' THEN RAISE EXCEPTION 'ROUTE directo: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"downstream_execution_allowed":true}');
  IF r->>'paso' <> 'INVALID_STAGE1' OR NOT (r->'codigos' ? 'DOWNSTREAM_EXECUTION_MUST_BE_FALSE') THEN RAISE EXCEPTION 'ROUTE invalido: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"formas_busqueda":["ACT-0043"],"texto_original":"el creador"}');
  IF r->>'paso' <> 'INVALID_STAGE1' OR NOT (r->'codigos' ? 'INVENTED_ASSET_CODE') THEN RAISE EXCEPTION 'ROUTE codigo inventado: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"el perfil","ambiguo":true,"alternativas":["perfil de producto","perfil de UI"],"pregunta_usuario":"¿Cual perfil?"}');
  IF r->>'paso' <> 'ASK_USER' THEN RAISE EXCEPTION 'ROUTE ambiguo: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"sistema":"SALY"}');
  IF r->>'paso' <> 'SYSTEM_NOT_SUPPORTED' THEN RAISE EXCEPTION 'ROUTE sistema: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"¿qué hay en curso ahora?","formas_busqueda":["estado en curso"],"capability_hint":"ESTADO_EN_CURSO"}');
  IF r->>'paso' <> 'DISPATCHED' OR r#>>'{despacho,decision}' <> 'PERMITIDO' THEN RAISE EXCEPTION 'ROUTE despacho: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"el creador de skills","formas_busqueda":["creador de skills"]}');
  IF r->>'paso' <> 'CANDIDATO_UNICO' OR r#>>'{candidatos,0,codigo}' <> 'ACT-0043' THEN RAISE EXCEPTION 'ROUTE unico: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"adapter","formas_busqueda":["adaptador","adapter"]}');
  IF r->>'paso' <> 'ELEGIR_O_PROFUNDIZAR' OR jsonb_array_length(r#>'{sondeo_sugerido,leer_juntos}') <> 3 THEN RAISE EXCEPTION 'ROUTE varios: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"spec driving","formas_busqueda":["spec driven","specification driven"]}');
  IF r->>'paso' <> 'NIVEL_2_CONSENTIMIENTO' THEN RAISE EXCEPTION 'ROUTE nivel2 consentimiento: %', r; END IF;
  r := public.lf_router_route_v1(b || '{"texto_original":"spec driving","formas_busqueda":["spec driven","specification driven"]}', '{}'::jsonb, true);
  IF r->>'paso' <> 'NIVEL_2_RESULTADO' OR r->>'resultado' <> 'NO_ENCONTRADO_EN_INDICE' THEN RAISE EXCEPTION 'ROUTE nivel2: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'ROUTE efecto: %', r; END IF;
END
$t$;

COMMIT;
