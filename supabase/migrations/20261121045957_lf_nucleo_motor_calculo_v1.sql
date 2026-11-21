-- Núcleo de reglas: operaciones de cálculo en el motor (LF y SALY, mismo código).
-- Agrega +, -, *, /, max, min, suma (de una lista, opcionalmente de un campo) y redondeo (piso, techo, normal; decimales por parámetro).
-- Sin datos fijos: los decimales y montos vienen de parámetros; el control 5 detecta literales también dentro de la lista y los decimales.
-- Nuevos códigos de error catalogados; nueva prueba nucleo_autotest_calculo_v1 en ambas instancias.

-- ===== instancia lf_ops =====
CREATE OR REPLACE FUNCTION lf_ops.nucleo_eval_v1(c jsonb, e jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'lf_ops'
AS $function$
DECLARE a jsonb; b jsonb; v jsonb; x numeric; y numeric; d numeric; it jsonb;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NODO_INVALIDO: %', c; END IF;
  IF c ? 'lit' THEN RETURN c->'lit'; END IF;
  IF c ? 'param' THEN
    v := to_jsonb(lf_ops.nucleo_param_valor_v1(c->>'param'));
    IF v IS NULL OR v = 'null'::jsonb THEN RAISE EXCEPTION 'NUCLEO_EVAL_PARAM_INEXISTENTE: %', c->>'param'; END IF;
    RETURN CASE WHEN (v #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN to_jsonb((v #>> '{}')::numeric) ELSE v END;
  END IF;
  IF c ? 'hecho' THEN
    v := e->(c->>'hecho');
    IF v IS NULL THEN RAISE EXCEPTION 'NUCLEO_EVAL_HECHO_SIN_VALOR: %', c->>'hecho'; END IF;
    IF jsonb_typeof(v) = 'object' AND v ? 'param' THEN
      RETURN to_jsonb(lf_ops.nucleo_param_valor_v1(v->>'param')::numeric + COALESCE((v->>'mas')::numeric, 0));
    END IF;
    RETURN v;
  END IF;
  IF c->>'op' IS NULL OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=','+','-','*','/','max','min','suma','redondeo') THEN
    RAISE EXCEPTION 'NUCLEO_EVAL_OPERADOR_INVALIDO: %', c->>'op';
  END IF;
  IF c->>'op' = 'no' THEN RETURN to_jsonb(NOT (lf_ops.nucleo_eval_v1(c->'izq', e))::text::boolean); END IF;
  -- Cálculo: suma de una lista (opcionalmente de un campo de cada elemento)
  IF c->>'op' = 'suma' THEN
    a := lf_ops.nucleo_eval_v1(c->'lista', e);
    IF jsonb_typeof(a) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'NUCLEO_EVAL_LISTA_INVALIDA: %', a; END IF;
    x := 0;
    FOR it IN SELECT value FROM jsonb_array_elements(a) LOOP
      v := CASE WHEN c ? 'campo' THEN it->(c->>'campo') ELSE it END;
      IF jsonb_typeof(v) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: % en la lista', coalesce(v::text, 'ausente'); END IF;
      x := x + (v #>> '{}')::numeric;
    END LOOP;
    RETURN to_jsonb(x);
  END IF;
  a := lf_ops.nucleo_eval_v1(c->'izq', e);
  -- Cálculo: redondeo a los decimales indicados por un parámetro
  IF c->>'op' = 'redondeo' THEN
    b := lf_ops.nucleo_eval_v1(c->'decimales', e);
    IF jsonb_typeof(a) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: %', a; END IF;
    IF jsonb_typeof(b) IS DISTINCT FROM 'number' OR (b #>> '{}')::numeric NOT BETWEEN 0 AND 10
       OR (b #>> '{}')::numeric <> trunc((b #>> '{}')::numeric) THEN
      RAISE EXCEPTION 'NUCLEO_EVAL_DECIMALES_INVALIDOS: %', b;
    END IF;
    x := (a #>> '{}')::numeric; d := power(10::numeric, (b #>> '{}')::int);
    RETURN to_jsonb(round(CASE c->>'modo' WHEN 'piso' THEN floor(x * d) / d WHEN 'techo' THEN ceil(x * d) / d ELSE round(x, (b #>> '{}')::int) END, (b #>> '{}')::int));
  END IF;
  b := lf_ops.nucleo_eval_v1(c->'der', e);
  IF c->>'op' IN ('+','-','*','/','max','min') THEN
    IF jsonb_typeof(a) IS DISTINCT FROM 'number' OR jsonb_typeof(b) IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: % % %', a, c->>'op', b;
    END IF;
    x := (a #>> '{}')::numeric; y := (b #>> '{}')::numeric;
    IF c->>'op' = '/' AND y = 0 THEN RAISE EXCEPTION 'NUCLEO_EVAL_DIVISION_CERO: % / 0', x; END IF;
    RETURN to_jsonb(CASE c->>'op' WHEN '+' THEN x + y WHEN '-' THEN x - y WHEN '*' THEN x * y WHEN '/' THEN x / y
                                  WHEN 'max' THEN greatest(x, y) ELSE least(x, y) END);
  END IF;
  RETURN to_jsonb(CASE c->>'op'
    WHEN 'y'  THEN a::text::boolean AND b::text::boolean
    WHEN 'o'  THEN a::text::boolean OR b::text::boolean
    WHEN '='  THEN a = b
    WHEN '!=' THEN a <> b
    WHEN '>'  THEN (a #>> '{}')::numeric >  (b #>> '{}')::numeric
    WHEN '>=' THEN (a #>> '{}')::numeric >= (b #>> '{}')::numeric
    WHEN '<'  THEN (a #>> '{}')::numeric <  (b #>> '{}')::numeric
    WHEN '<=' THEN (a #>> '{}')::numeric <= (b #>> '{}')::numeric
    END);
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_condicion_problema_v1(c jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE hojas integer;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RETURN 'nodo que no es objeto: ' || coalesce(c::text, 'nulo'); END IF;
  hojas := (c ? 'hecho')::int + (c ? 'param')::int + (c ? 'lit')::int;
  IF hojas > 1 OR (hojas = 1 AND c ? 'op') THEN RETURN 'nodo con más de un tipo: ' || c::text; END IF;
  IF hojas = 1 THEN
    IF (c ? 'hecho' AND jsonb_typeof(c->'hecho') <> 'string') OR (c ? 'param' AND (jsonb_typeof(c->'param') <> 'string' OR c->>'param' !~ '^[A-Z][A-Z0-9_]*\.[A-Z0-9_.]+$'))
      THEN RETURN 'hoja mal escrita: ' || c::text; END IF;
    RETURN NULL;
  END IF;
  IF NOT c ? 'op' OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=','+','-','*','/','max','min','suma','redondeo') THEN RETURN 'operador desconocido o ausente: ' || c::text; END IF;
  IF c->>'op' = 'no' THEN RETURN lf_ops.nucleo_condicion_problema_v1(c->'izq'); END IF;
  IF c->>'op' = 'suma' THEN
    IF c ? 'campo' AND (jsonb_typeof(c->'campo') <> 'string' OR btrim(c->>'campo') = '') THEN RETURN 'suma con campo mal escrito: ' || c::text; END IF;
    RETURN lf_ops.nucleo_condicion_problema_v1(c->'lista');
  END IF;
  IF c->>'op' = 'redondeo' THEN
    IF c->>'modo' IS NULL OR c->>'modo' NOT IN ('piso','techo','normal') THEN RETURN 'redondeo sin modo piso, techo o normal: ' || c::text; END IF;
    RETURN COALESCE(lf_ops.nucleo_condicion_problema_v1(c->'izq'), lf_ops.nucleo_condicion_problema_v1(c->'decimales'));
  END IF;
  RETURN COALESCE(lf_ops.nucleo_condicion_problema_v1(c->'izq'), lf_ops.nucleo_condicion_problema_v1(c->'der'));
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_nodos_condicion_v1(c jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH RECURSIVE t(n) AS (
    SELECT c WHERE jsonb_typeof(c) = 'object'
    UNION ALL
    SELECT x FROM t, LATERAL (VALUES (t.n->'izq'), (t.n->'der'), (t.n->'lista'), (t.n->'decimales')) y(x)
     WHERE x IS NOT NULL AND jsonb_typeof(x) = 'object')
  SELECT n FROM t
$function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_datos_v1()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE v_raiz text := (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'GLOBAL');
BEGIN
  IF v_raiz IS NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_SIN_RAIZ'; END IF;
  INSERT INTO lf_ops.nucleo_familias (codigo, dominio, origen, descripcion, estado, min_pruebas, tipo) VALUES
    ('ZZT_FAM','BACKEND','NUEVA','Familia de prueba del núcleo (autotest)','ACTIVA',2,'TECNICA'),
    ('ZZT_FAM_MANUAL','BACKEND','NUEVA','Familia de prueba que siempre pide decisión humana (autotest)','ACTIVA',2,'TECNICA');
  INSERT INTO lf_ops.nucleo_hechos (codigo, tipo_dato, unidad, descripcion) VALUES
    ('zzt_intentos','integer','veces','Intentos de prueba del núcleo (autotest)'),
    ('zzt_inactividad','integer','segundos','Inactividad de prueba del núcleo (autotest)');
  INSERT INTO lf_ops.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_intentos','CURADO'), ('ZZT_FAM_MANUAL','zzt_inactividad','CURADO');
  INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MAX_INTENTOS','3','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)'),
    ('ZZT','INACTIVIDAD_MAX','900','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)');
  INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion) VALUES ('ZZT-Q','POLITICA','Autoridad de prueba del núcleo (autotest)');
  INSERT INTO lf_ops.nucleo_nodos (codigo, padre, nivel) VALUES
    ('ZZT-AMB', v_raiz, 'AMBITO'), ('ZZT-BACK', v_raiz, 'AMBITO'), ('ZZT-MOD-1', 'ZZT-AMB', 'MODULO'), ('ZZT-MOD-2', 'ZZT-AMB', 'MODULO');
  UPDATE public.lf_global_config g SET config_value = (g.config_value::jsonb || to_jsonb(x.extra))::text
    FROM (VALUES ('AMBITOS_PANTALLA','ZZT-AMB'), ('AMBITOS_BACKEND','ZZT-BACK')) x(clave, extra)
   WHERE g.scope = 'NUCLEO' AND g.config_key = x.clave
     AND g.valid_from = (SELECT max(valid_from) FROM public.lf_global_config WHERE scope = 'NUCLEO' AND config_key = x.clave AND valid_from <= now());
  UPDATE public.lf_global_config g SET config_value = (g.config_value::jsonb || '["ZZT_FAM_MANUAL"]')::text
   WHERE g.scope = 'NUCLEO_EVAL' AND g.config_key = 'FAMILIAS_SIEMPRE_MANUAL'
     AND g.valid_from = (SELECT max(valid_from) FROM public.lf_global_config WHERE scope = 'NUCLEO_EVAL' AND config_key = 'FAMILIAS_SIEMPRE_MANUAL' AND valid_from <= now());
  -- Datos de prueba para operaciones de cálculo
  INSERT INTO lf_ops.nucleo_hechos (codigo, tipo_dato, unidad, descripcion) VALUES
    ('zzt_monto','decimal','soles','Monto de prueba del núcleo (autotest de cálculo)'),
    ('zzt_items','json','ninguna','Lista de montos de prueba del núcleo (autotest de cálculo)');
  INSERT INTO lf_ops.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_monto','CURADO'), ('ZZT_FAM','zzt_items','CURADO');
  INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MONTO_BASE','100.555','DECIMAL','REAL','Monto de prueba del núcleo (autotest de cálculo)'),
    ('ZZT','DECIMALES','2','INTEGER','REAL','Decimales de prueba del núcleo (autotest de cálculo)');
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  ctl jsonb := '[]'::jsonb;
  v_fam record; v_falta text; v_txt text; v_n integer; v_ok boolean;
  v_clase text := upper(p->>'clase'); v_nat text := upper(p->>'naturaleza'); v_alc text := p->>'alcance';
  v_ambito text; v_nivel text; v_clasif text := 'NUEVA'; v_prueba jsonb; v_res jsonb; v_bloq integer;
  v_lits jsonb; v_efectos jsonb;
  v_tipo text := upper(COALESCE(p->>'tipo','NUEVA')); v_r0 record; v_nodo0 text; v_ultima record; v_ver integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_proponer:' || coalesce(p->>'clave', ''), 0));

  -- 0 identidad: NUEVA exige código libre; CAMBIO exige la regla existente con la misma identidad y alcance, sin otra candidata
  IF v_tipo = 'NUEVA' THEN
    v_ok := p->>'codigo' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nucleo_reglas WHERE codigo = p->>'codigo');
    ctl := ctl || jsonb_build_object('n',0,'control','Código libre','ok',v_ok,'bloqueante',true,
      'detalle', CASE WHEN v_ok THEN '' ELSE 'El código ya existe o falta: use otro código o proponga un CAMBIO de la regla existente.' END);
  ELSIF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_r0 FROM nucleo_reglas WHERE codigo = p->>'codigo';
    SELECT nodo INTO v_nodo0 FROM nucleo_aplicaciones WHERE regla = p->>'codigo' ORDER BY nodo LIMIT 1;
    v_txt := CASE
      WHEN v_r0.codigo IS NULL THEN 'La regla ' || COALESCE(p->>'codigo','(vacía)') || ' no existe: proponga una regla NUEVA.'
      WHEN v_r0.estado NOT IN ('CANDIDATA','VIGENTE') THEN 'La regla está ' || v_r0.estado || ' y no admite cambios.'
      WHEN v_r0.clave <> p->>'clave' OR v_r0.familia <> p->>'familia' OR v_r0.naturaleza <> v_nat THEN 'Un cambio no altera clave, familia ni naturaleza: eso es una regla nueva.'
      WHEN v_nodo0 IS DISTINCT FROM v_alc THEN 'Un cambio no altera el alcance (' || COALESCE(v_nodo0,'-') || '): eso es una regla nueva o una especialización.'
      WHEN EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado = 'CANDIDATA') THEN 'Ya hay una versión candidata abierta: promuévala o descártela antes de otro cambio.'
      END;
    ctl := ctl || jsonb_build_object('n',0,'control','Regla a cambiar','ok',v_txt IS NULL,'bloqueante',true,'detalle',COALESCE(v_txt,''));
  ELSE
    ctl := ctl || jsonb_build_object('n',0,'control','Tipo de propuesta','ok',false,'bloqueante',true,'detalle','El tipo debe ser NUEVA o CAMBIO.');
  END IF;

  -- 1 familia existe
  SELECT * INTO v_fam FROM nucleo_familias WHERE codigo = p->>'familia';
  v_ok := FOUND AND v_fam.estado <> 'RETIRADA';
  ctl := ctl || jsonb_build_object('n',1,'control','Familia existe','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'familia' ELSE 'La familia ' || coalesce(p->>'familia','(vacía)') || ' no existe o está retirada: elija una de lf_ops.nucleo_familias.' END);

  -- 2 campos del contrato (global + extensión de la familia)
  SELECT string_agg(k.campo, ', ' ORDER BY k.campo) INTO v_falta FROM nucleo_contrato_campos k
   WHERE (k.familia IS NULL OR k.familia = p->>'familia')
     AND (NOT p ? k.campo OR jsonb_typeof(p->k.campo) = 'null' OR btrim(p->>k.campo) = '' OR p->k.campo IN ('[]'::jsonb, '{}'::jsonb));
  ctl := ctl || jsonb_build_object('n',2,'control','Campos obligatorios','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Faltan o están vacíos: ' || v_falta END);

  v_txt := nucleo_condicion_problema_v1(p->'condicion');
  ctl := ctl || jsonb_build_object('n',2,'control','Condición bien formada','ok',v_txt IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=; para cálculos +, -, *, /, max, min, suma (lista, campo) y redondeo (modo piso|techo|normal, decimales).' END);

  v_ok := jsonb_typeof(p->'origen') = 'object' AND p->'origen'->>'tipo' IN ('IG','CHAT','PERSONA','MIGRACION')
          AND length(btrim(COALESCE(p->'origen'->>'ref',''))) >= 3 AND length(btrim(COALESCE(p->'origen'->>'solicitante',''))) >= 3;
  ctl := ctl || jsonb_build_object('n',2,'control','Origen del cambio','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'El origen debe indicar tipo (IG, CHAT, PERSONA o MIGRACION), referencia y solicitante.' END);
  v_ok := upper(p->>'impacto') IN ('NINGUNO','REVISAR','IMPLEMENTAR') AND NOT (v_tipo = 'NUEVA' AND upper(p->>'impacto') = 'NINGUNO')
          AND (p->'plazo_dias' IS NULL OR (jsonb_typeof(p->'plazo_dias') = 'number' AND (p->>'plazo_dias')::numeric >= 0 AND (p->>'plazo_dias')::numeric = trunc((p->>'plazo_dias')::numeric)));
  ctl := ctl || jsonb_build_object('n',18,'control','Impacto declarado','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'Impacto NINGUNO, REVISAR o IMPLEMENTAR (una regla nueva no puede ser NINGUNO); plazo_dias entero no negativo.' END);

  -- 3 alcance existe
  SELECT nivel INTO v_nivel FROM nucleo_nodos WHERE codigo = v_alc;
  ctl := ctl || jsonb_build_object('n',3,'control','Alcance existe','ok',v_nivel IS NOT NULL,'bloqueante',true,
    'detalle', CASE WHEN v_nivel IS NOT NULL THEN v_alc ELSE 'El alcance ' || coalesce(v_alc,'(vacío)') || ' no es un nodo del árbol (lf_ops.v_nucleo_nodos).' END);

  -- 4 datos dentro del vocabulario de la familia
  SELECT string_agg(DISTINCT x->>'hecho', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'hecho' AND NOT EXISTS (SELECT 1 FROM nucleo_familia_vocabulario v WHERE v.familia = p->>'familia' AND v.hecho = x->>'hecho');
  ctl := ctl || jsonb_build_object('n',4,'control','Datos dentro del vocabulario','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Datos fuera del vocabulario de la familia: ' || v_falta || '. Use un hecho de lf_ops.v_nucleo_vocabulario o regístrelo primero.' END);

  -- 5 sin datos fijos (literales permitidos en NUCLEO.LITERALES_PERMITIDOS)
  v_lits := COALESCE(nucleo_param_valor_v1('NUCLEO.LITERALES_PERMITIDOS')::jsonb, '[]'::jsonb);
  SELECT string_agg(x->>'lit', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'number' AND NOT v_lits @> jsonb_build_array(x->'lit');
  ctl := ctl || jsonb_build_object('n',5,'control','Sin datos fijos','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Valores fijos en la condición: ' || v_falta || '. Reemplácelos por {"param":"SCOPE.CLAVE"} de lf_global_config.' END);
  SELECT string_agg(x->>'lit', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'string';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',5,'control','Textos fijos en la condición','ok',false,'bloqueante',false,
      'detalle','Verifique que sean valores de una lista del vocabulario: ' || v_txt);
  END IF;

  -- 6 parámetros existen
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND nucleo_param_valor_v1(x->>'param') IS NULL;
  ctl := ctl || jsonb_build_object('n',6,'control','Parámetros existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Parámetros inexistentes en lf_global_config: ' || v_falta END);

  -- 13 unidades compatibles (hecho comparado con un parámetro registrado en nucleo_parametros)
  SELECT string_agg(format('%s (%s) vs %s (%s)', hi.codigo, hi.unidad, pa.scope || '.' || pa.config_key, hp.unidad), '; ') INTO v_falta
    FROM nucleo_nodos_condicion_v1(p->'condicion') x
    JOIN nucleo_hechos hi ON hi.codigo = COALESCE(x->'izq'->>'hecho', x->'der'->>'hecho')
    JOIN nucleo_parametros pa ON pa.scope || '.' || pa.config_key = COALESCE(x->'der'->>'param', x->'izq'->>'param')
    JOIN nucleo_hechos hp ON hp.codigo = pa.hecho
   WHERE x->>'op' IN ('>','>=','<','<=','=','!=') AND hi.unidad IS DISTINCT FROM hp.unidad;
  ctl := ctl || jsonb_build_object('n',13,'control','Unidades compatibles','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Unidades distintas: ' || v_falta END);
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND NOT EXISTS (SELECT 1 FROM nucleo_parametros pa WHERE pa.scope || '.' || pa.config_key = x->>'param');
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',13,'control','Parámetro sin metadatos','ok',false,'bloqueante',false,
      'detalle','Registre en lf_ops.nucleo_parametros el dato y la unidad de: ' || v_txt || ' (sin eso no se puede verificar la unidad).');
  END IF;

  -- 14 parámetro real (no de muestra)
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM public.lf_global_config g WHERE g.scope || '.' || g.config_key = x->>'param' AND g.value_status <> 'REAL');
  ctl := ctl || jsonb_build_object('n',14,'control','Parámetros con valor real','ok',v_txt IS NULL,'bloqueante',false,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'Usan valor de muestra (no bloquea el desarrollo, sí la producción): ' || v_txt END);

  -- 7 pruebas mínimas de la familia
  v_n := CASE WHEN jsonb_typeof(p->'pruebas') = 'array' THEN jsonb_array_length(p->'pruebas') ELSE 0 END;
  v_ok := v_fam.codigo IS NOT NULL AND v_n >= v_fam.min_pruebas;
  ctl := ctl || jsonb_build_object('n',7,'control','Pruebas mínimas de la familia','ok',v_ok,'bloqueante',true,
    'detalle', format('%s de %s', v_n, coalesce(v_fam.min_pruebas::text,'?')));

  SELECT string_agg(DISTINCT t->>'casuistica', ', ') INTO v_falta
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t
   WHERE t ? 'casuistica' AND NOT EXISTS (SELECT 1 FROM nucleo_casuisticas k WHERE k.codigo = t->>'casuistica' AND k.estado = 'ACTIVA'
         AND k.naturaleza = v_nat AND (k.familia IS NULL OR k.familia = p->>'familia'));
  ctl := ctl || jsonb_build_object('n',7,'control','Casuísticas conocidas','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Casuísticas que no existen para esta familia y naturaleza: ' || v_falta || ' (ver lf_ops.nucleo_casuisticas).' END);

  -- 8 pruebas relativas al parámetro (ningún valor numérico fijo como entrada)
  SELECT count(*) INTO v_n FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t,
       jsonb_each(COALESCE(t->'entrada','{}'::jsonb)) kv
   WHERE jsonb_typeof(kv.value) = 'number' AND NOT v_lits @> jsonb_build_array(kv.value);
  ctl := ctl || jsonb_build_object('n',8,'control','Pruebas relativas al parámetro','ok',v_n = 0,'bloqueante',true,
    'detalle', CASE WHEN v_n = 0 THEN '' ELSE v_n || ' entradas con valor fijo: use {"param":"SCOPE.CLAVE","mas":n}.' END);

  -- 15 las pruebas se ejecutan y pasan
  v_falta := NULL;
  IF jsonb_typeof(p->'pruebas') = 'array' THEN
    FOR v_prueba IN SELECT value FROM jsonb_array_elements(p->'pruebas') LOOP
      BEGIN
        v_res := nucleo_eval_v1(p->'condicion', v_prueba->'entrada');
        IF v_res IS DISTINCT FROM v_prueba->'esperado' THEN
          v_falta := concat_ws('; ', v_falta, format('entrada %s dio %s y se esperaba %s', v_prueba->'entrada', v_res, v_prueba->'esperado'));
        END IF;
      EXCEPTION WHEN others THEN
        v_falta := concat_ws('; ', v_falta, 'error al evaluar: ' || SQLERRM);
      END;
    END LOOP;
  END IF;
  ctl := ctl || jsonb_build_object('n',15,'control','Pruebas se ejecutan y pasan','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', coalesce(v_falta,''));

  -- 16 autoridad registrada y vigente
  v_ok := EXISTS (SELECT 1 FROM nucleo_autoridades WHERE codigo = p->>'autoridad' AND estado = 'VIGENTE');
  ctl := ctl || jsonb_build_object('n',16,'control','Autoridad vigente','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'autoridad' ELSE 'La autoridad ' || coalesce(p->>'autoridad','(vacía)') || ' no está en lf_ops.nucleo_autoridades o no está vigente.' END);

  -- 17 dependencias existen (no vigentes: aviso, frenan la promoción)
  SELECT string_agg(d, ', ') INTO v_falta FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   WHERE NOT EXISTS (SELECT 1 FROM nucleo_reglas r WHERE r.codigo = d);
  ctl := ctl || jsonb_build_object('n',17,'control','Dependencias existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Dependencias inexistentes: ' || v_falta END);
  SELECT string_agg(d, ', ') INTO v_txt FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   JOIN nucleo_reglas r ON r.codigo = d WHERE r.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',17,'control','Depende de reglas no vigentes','ok',false,'bloqueante',false,
      'detalle','Entra como candidata, pero no podrá promoverse hasta que estén vigentes: ' || v_txt);
  END IF;

  -- 18 efecto coherente con la naturaleza
  v_efectos := COALESCE(nucleo_param_valor_v1(CASE v_nat WHEN 'DEFINICION' THEN 'NUCLEO.EFECTOS_DEFINICION' ELSE 'NUCLEO.EFECTOS_CONDUCTA' END)::jsonb, '[]');
  v_ok := v_nat IN ('CONDUCTA','DEFINICION') AND v_efectos @> jsonb_build_array(upper(p->>'efecto'));
  ctl := ctl || jsonb_build_object('n',18,'control','Efecto coherente con la naturaleza','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Una regla de %s no puede tener el efecto %s; válidos: %s', coalesce(v_nat,'?'), coalesce(p->>'efecto','?'), v_efectos) END);

  -- 19 clase coherente con el alcance
  WITH RECURSIVE anc(c, nv) AS (
    SELECT codigo, nivel FROM nucleo_nodos WHERE codigo = v_alc
    UNION ALL SELECT n.padre, (SELECT nivel FROM nucleo_nodos WHERE codigo = n.padre)
      FROM nucleo_nodos n JOIN anc ON n.codigo = anc.c WHERE n.padre IS NOT NULL)
  SELECT max(c) FILTER (WHERE nv = 'AMBITO') INTO v_ambito FROM anc;
  v_ok := CASE v_clase
    WHEN 'BACKEND' THEN v_nivel = 'GLOBAL' OR COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_BACKEND')::jsonb, '[]') @> jsonb_build_array(v_ambito)
    WHEN 'PANTALLA' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_PANTALLA')::jsonb, '[]') @> jsonb_build_array(v_ambito)
    WHEN 'TRANSVERSAL' THEN v_nivel IN ('GLOBAL','AMBITO')
    ELSE false END;
  ctl := ctl || jsonb_build_object('n',19,'control','Clase coherente con el alcance','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Clase %s no corresponde al alcance %s (nivel %s, ámbito %s).', coalesce(v_clase,'?'), coalesce(v_alc,'?'), coalesce(v_nivel,'?'), coalesce(v_ambito,'-')) END);

  -- 9 sin conflicto con una regla FIJA superior de la misma clave
  IF v_nivel IS NOT NULL THEN
    SELECT string_agg(e.regla || ' en ' || e.nodo_origen, ', ') INTO v_falta
      FROM nucleo_reglas_efectivas_v1(v_alc) e WHERE e.clave = p->>'clave' AND e.modo = 'FIJA' AND e.distancia > 0;
  END IF;
  ctl := ctl || jsonb_build_object('n',9,'control','Sin conflicto con reglas fijas superiores','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Existe una regla FIJA superior con la misma clave: ' || v_falta END);

  -- 10 clasificación contra lo existente
  SELECT CASE WHEN a.nodo = v_alc AND v.condicion = p->'condicion' THEN 'DUPLICADO_DE ' || r.codigo
              WHEN a.nodo = v_alc THEN 'NUEVA_VERSION_DE ' || r.codigo
              ELSE 'ESPECIALIZA ' || r.codigo END
    INTO v_clasif
    FROM nucleo_reglas r
    JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND r.familia = p->>'familia' AND r.estado NOT IN ('RETIRADA') AND r.codigo IS DISTINCT FROM CASE WHEN v_tipo = 'CAMBIO' THEN p->>'codigo' END
     AND (a.nodo = v_alc OR a.nodo IN (
       WITH RECURSIVE up(c) AS (SELECT padre FROM nucleo_nodos WHERE codigo = v_alc
         UNION ALL SELECT n.padre FROM nucleo_nodos n JOIN up ON n.codigo = up.c WHERE n.padre IS NOT NULL)
       SELECT c FROM up WHERE c IS NOT NULL))
   ORDER BY (a.nodo = v_alc) DESC LIMIT 1;
  v_clasif := COALESCE(v_clasif, 'NUEVA');
  ctl := ctl || jsonb_build_object('n',10,'control','Clasificación contra lo existente',
    'ok', v_clasif NOT LIKE 'DUPLICADO%' AND v_clasif NOT LIKE 'NUEVA_VERSION%','bloqueante',true,
    'detalle', CASE WHEN v_clasif LIKE 'DUPLICADO%' THEN v_clasif || ': ya existe igual en el mismo alcance.'
                    WHEN v_clasif LIKE 'NUEVA_VERSION%' THEN v_clasif || ': es un cambio de una regla existente; use la ruta de versión de esa regla.'
                    ELSE v_clasif END);

  IF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_ultima FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado <> 'DESCARTADA' ORDER BY version DESC LIMIT 1;
    IF v_ultima.version IS NOT NULL
       AND ROW(v_ultima.titulo, v_ultima.descripcion, v_ultima.condicion, v_ultima.efecto, v_ultima.autoridad, v_ultima.impacto)
           IS NOT DISTINCT FROM ROW(p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad', upper(p->>'impacto'))
       AND (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',casuistica,'e',entrada,'x',esperado) ORDER BY n), '[]') FROM nucleo_regla_pruebas
             WHERE regla = v_ultima.regla AND version = v_ultima.version)
           IS NOT DISTINCT FROM (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',t.v->>'casuistica','e',t.v->'entrada','x',t.v->'esperado') ORDER BY t.o), '[]')
             FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) WITH ORDINALITY t(v, o)) THEN
      ctl := ctl || jsonb_build_object('n',10,'control','Cambio con contenido','ok',false,'bloqueante',true,
        'detalle','SIN_CAMBIOS: igual a la versión ' || v_ultima.version || '.');
    END IF;
  END IF;

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto','ok',false,'bloqueante',false,
      'detalle','Ya existe idéntica en otros nodos (' || v_txt || '): considere registrarla una vez en el nodo común y retirar las copias.');
  END IF;

  -- 12 hacia abajo: reglas de la misma clave en los descendientes (aviso)
  WITH RECURSIVE dn(c) AS (SELECT v_alc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
   WHERE r.clave = p->>'clave' AND a.nodo IN (SELECT c FROM dn) AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',12,'control','Impacto hacia abajo','ok',false,'bloqueante',false,
      'detalle', CASE WHEN upper(p->>'modo') = 'FIJA' THEN 'Es FIJA y hay reglas de la misma clave abajo (deben resolverse antes de promover): '
                      ELSE 'Hay reglas de la misma clave abajo (quedan como especialización): ' END || v_txt);
  END IF;

  SELECT count(*) INTO v_bloq FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;

  IF v_bloq = 0 AND p_aplicar THEN
    IF v_tipo = 'NUEVA' THEN
      INSERT INTO nucleo_reglas (codigo, clave, familia, naturaleza, estado)
      VALUES (p->>'codigo', p->>'clave', p->>'familia', v_nat, 'CANDIDATA');
      INSERT INTO nucleo_aplicaciones (regla, nodo, modo) VALUES (p->>'codigo', v_alc, upper(p->>'modo'));
    END IF;
    INSERT INTO nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, plazo_dias)
    VALUES (p->>'codigo', p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad',
            upper(p->>'impacto'), p->'origen', p - 'pruebas', (p->>'plazo_dias')::int)
    RETURNING version INTO v_ver;
    INSERT INTO nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    SELECT p->>'codigo', v_ver, t.ord::int, t.v->>'casuistica', t.v->'entrada', t.v->'esperado'
      FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY t(v, ord);
    INSERT INTO nucleo_relaciones (origen, destino, tipo)
    SELECT p->>'codigo', d, 'DEPENDE' FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
     WHERE NOT EXISTS (SELECT 1 FROM nucleo_relaciones x WHERE x.origen = p->>'codigo' AND x.destino = d AND x.tipo = 'DEPENDE');
  END IF;

  RETURN jsonb_build_object(
    'resultado', CASE WHEN v_bloq > 0 THEN 'RECHAZADA' WHEN p_aplicar THEN 'CANDIDATA' ELSE 'EVALUADA_SIN_ESCRIBIR' END,
    'tipo', v_tipo, 'version', v_ver, 'clasificacion', v_clasif, 'bloqueantes', v_bloq,
    'avisos', (SELECT count(*) FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND NOT (x->>'bloqueante')::boolean),
    'controles', ctl);
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_calculo_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  k record; v_res jsonb; v_err text; v_n integer := 0; r jsonb; v_txt text;
  m jsonb := '{"param":"ZZT.MONTO_BASE"}'; dec jsonb := '{"param":"ZZT.DECIMALES"}'; tres jsonb := '{"param":"ZZT.MAX_INTENTOS"}';
  items jsonb := '[{"monto":10.5},{"monto":4.25},{"monto":0.25}]';
  base jsonb;
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    -- K1-K4 evaluación: resultado esperado o código de error esperado
    FOR k IN SELECT * FROM (VALUES
      ('K1 suma de dos parámetros',   jsonb_build_object('op','+','izq',tres,'der',tres), '{}'::jsonb, '6'::jsonb, NULL::text),
      ('K1 resta',                    jsonb_build_object('op','-','izq',m,'der',tres), '{}', '97.555', NULL),
      ('K1 producto',                 jsonb_build_object('op','*','izq',tres,'der',dec), '{}', '6', NULL),
      ('K1 división',                 jsonb_build_object('op','/','izq',tres,'der',tres), '{}', '1', NULL),
      ('K1 máximo',                   jsonb_build_object('op','max','izq',tres,'der',dec), '{}', '3', NULL),
      ('K1 mínimo',                   jsonb_build_object('op','min','izq',tres,'der',dec), '{}', '2', NULL),
      ('K1 hecho relativo al param',  jsonb_build_object('op','+','izq','{"hecho":"zzt_monto"}'::jsonb,'der',tres), jsonb_build_object('zzt_monto','{"param":"ZZT.MONTO_BASE","mas":1}'::jsonb), '104.555', NULL),
      ('K2 suma de un campo',         jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items',items), '15', NULL),
      ('K2 suma de lista simple',     jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb), jsonb_build_object('zzt_items','[1.5,2.5]'::jsonb), '4', NULL),
      ('K2 suma de lista vacía',      jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items','[]'::jsonb), '0', NULL),
      ('K3 redondeo piso',            jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',dec), '{}', '100.55', NULL),
      ('K3 redondeo techo',           jsonb_build_object('op','redondeo','modo','techo','izq',m,'decimales',dec), '{}', '100.56', NULL),
      ('K3 redondeo normal',          jsonb_build_object('op','redondeo','modo','normal','izq',m,'decimales',dec), '{}', '100.56', NULL),
      ('K3 cálculo dentro de una comparación', jsonb_build_object('op','>','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'),'der',m), jsonb_build_object('zzt_items',items), 'false', NULL),
      ('K4 división entre cero',      jsonb_build_object('op','/','izq',tres,'der',jsonb_build_object('op','-','izq',tres,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DIVISION_CERO'),
      ('K4 lista que no es lista',    jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb), jsonb_build_object('zzt_items','{"monto":1}'::jsonb), NULL, 'NUCLEO_EVAL_LISTA_INVALIDA'),
      ('K4 elemento sin el campo',    jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items','[{"otro":1}]'::jsonb), NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 operando de texto',        jsonb_build_object('op','+','izq',tres,'der','{"lit":"tres"}'::jsonb), '{}', NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 decimales negativos',      jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',jsonb_build_object('op','-','izq',dec,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DECIMALES_INVALIDOS'),
      ('K4 decimales no enteros',     jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',jsonb_build_object('op','/','izq',dec,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DECIMALES_INVALIDOS'),
      ('K4 redondeo de un texto',     jsonb_build_object('op','redondeo','modo','piso','izq','{"lit":"x"}'::jsonb,'decimales',dec), '{}', NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 operador inventado',       '{"op":"potencia","izq":{"lit":1},"der":{"lit":1}}'::jsonb, '{}', NULL, 'NUCLEO_EVAL_OPERADOR_INVALIDO')
    ) t(caso, cond, entrada, esperado, error) LOOP
      v_res := NULL; v_err := NULL;
      BEGIN v_res := lf_ops.nucleo_eval_v1(k.cond, k.entrada); EXCEPTION WHEN others THEN v_err := SQLERRM; END;
      IF k.error IS NULL AND (v_err IS NOT NULL OR v_res IS DISTINCT FROM k.esperado) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % obtuvo % (error %)', k.caso, v_res, v_err;
      END IF;
      IF k.error IS NOT NULL AND (v_err IS NULL OR split_part(v_err, ':', 1) <> k.error) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % debía fallar con % y obtuvo % / %', k.caso, k.error, v_res, v_err;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- K5 forma: rechaza cálculos mal escritos y acepta los bien escritos
    FOR k IN SELECT * FROM (VALUES
      ('K5 suma sin lista',        '{"op":"suma","campo":"monto"}'::jsonb, false),
      ('K5 suma con campo vacío',  '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":""}'::jsonb, false),
      ('K5 suma con campo número', '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":1}'::jsonb, false),
      ('K5 redondeo sin modo',     '{"op":"redondeo","izq":{"hecho":"zzt_monto"},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 redondeo modo raro',    '{"op":"redondeo","modo":"banquero","izq":{"hecho":"zzt_monto"},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 redondeo sin decimales','{"op":"redondeo","modo":"piso","izq":{"hecho":"zzt_monto"}}'::jsonb, false),
      ('K5 operador inventado',    '{"op":"potencia","izq":{"hecho":"zzt_monto"},"der":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 resta sin der',         '{"op":"-","izq":{"hecho":"zzt_monto"}}'::jsonb, false),
      ('K5 suma bien escrita',     '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":"monto"}'::jsonb, true),
      ('K5 redondeo bien escrito', '{"op":"redondeo","modo":"techo","izq":{"op":"*","izq":{"hecho":"zzt_monto"},"der":{"param":"ZZT.MAX_INTENTOS"}},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, true)
    ) t(caso, cond, valida) LOOP
      IF (lf_ops.nucleo_condicion_problema_v1(k.cond) IS NULL) IS DISTINCT FROM k.valida THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % (problema: %)', k.caso, lf_ops.nucleo_condicion_problema_v1(k.cond);
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- K6 puerta: una regla de definición con efecto CALCULAR entra como candidata
    base := jsonb_build_object('codigo','ZZT-K-1','clave','zzt_k_uno','titulo','Total redondeado de prueba',
      'descripcion','Calcula el total de los montos de la lista redondeado hacia abajo a los decimales configurados',
      'familia','ZZT_FAM','naturaleza','DEFINICION','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-BACK','modo','HEREDA',
      'clase','BACKEND','efecto','CALCULAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-calculo','solicitante','autotest'),
      'condicion', jsonb_build_object('op','redondeo','modo','piso','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'),'decimales',dec),
      'pruebas', jsonb_build_array(
        jsonb_build_object('entrada',jsonb_build_object('zzt_items','[{"monto":10.555},{"monto":4.25}]'::jsonb),'esperado',14.80),
        jsonb_build_object('entrada',jsonb_build_object('zzt_items','[]'::jsonb),'esperado',0)));
    r := lf_ops.nucleo_regla_proponer_v1(base, false);
    SELECT string_agg(x->>'control' || ': ' || (x->>'detalle'), '; ') INTO v_txt FROM jsonb_array_elements(r->'controles') x
     WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
    IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 regla de cálculo rechazada: %', v_txt; END IF;
    v_n := v_n + 1;
    -- K7 decimales fijos en el redondeo se detectan como dato fijo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('condicion', jsonb_set(base->'condicion', '{decimales}', '{"lit":2}')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Sin datos fijos' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K7 decimales fijos no detectados';
    END IF;
    v_n := v_n + 1;
    -- K8 un dato fuera del vocabulario dentro de la lista se detecta
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('condicion', jsonb_set(base->'condicion', '{izq,lista}', '{"hecho":"zzt_inactividad"}')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Datos dentro del vocabulario' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 dato fuera de vocabulario en la lista no detectado';
    END IF;
    v_n := v_n + 1;
    -- K9 una regla de cálculo con efecto de conducta se rechaza
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"efecto":"BLOQUEAR"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Efecto coherente con la naturaleza' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K9 efecto incoherente aceptado';
    END IF;
    v_n := v_n + 1;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'CALCULO ' || v_n || '/' || v_n;
END $function$;

INSERT INTO lf_ops.nucleo_errores (codigo, puerta, significado, accion) VALUES
  ('NUCLEO_EVAL_DIVISION_CERO','PROPUESTA','Un cálculo divide entre cero con los valores de la prueba','Revisar el divisor o agregar una condición que lo excluya'),
  ('NUCLEO_EVAL_LISTA_INVALIDA','PROPUESTA','La suma recibió algo que no es una lista','Entregar el dato como lista en la entrada de la prueba'),
  ('NUCLEO_EVAL_NO_NUMERICO','PROPUESTA','Un cálculo recibió un valor que no es número (o un elemento de la lista sin el campo)','Corregir el dato o el campo que se suma'),
  ('NUCLEO_EVAL_DECIMALES_INVALIDOS','PROPUESTA','Los decimales del redondeo no son un entero entre 0 y 10','Corregir el parámetro de decimales');
UPDATE lf_ops.nucleo_errores SET accion = 'Usar y, o, no, =, !=, >, >=, <, <=, +, -, *, /, max, min, suma o redondeo' WHERE codigo = 'NUCLEO_EVAL_OPERADOR_INVALIDO';
REVOKE ALL ON FUNCTION lf_ops.nucleo_autotest_calculo_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_autotest_calculo_v1() TO service_role;
  END IF;
END $g$;

-- ===== instancia saly =====
CREATE OR REPLACE FUNCTION saly.nucleo_eval_v1(c jsonb, e jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE a jsonb; b jsonb; v jsonb; x numeric; y numeric; d numeric; it jsonb;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NODO_INVALIDO: %', c; END IF;
  IF c ? 'lit' THEN RETURN c->'lit'; END IF;
  IF c ? 'param' THEN
    v := to_jsonb(saly.nucleo_param_valor_v1(c->>'param'));
    IF v IS NULL OR v = 'null'::jsonb THEN RAISE EXCEPTION 'NUCLEO_EVAL_PARAM_INEXISTENTE: %', c->>'param'; END IF;
    RETURN CASE WHEN (v #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN to_jsonb((v #>> '{}')::numeric) ELSE v END;
  END IF;
  IF c ? 'hecho' THEN
    v := e->(c->>'hecho');
    IF v IS NULL THEN RAISE EXCEPTION 'NUCLEO_EVAL_HECHO_SIN_VALOR: %', c->>'hecho'; END IF;
    IF jsonb_typeof(v) = 'object' AND v ? 'param' THEN
      RETURN to_jsonb(saly.nucleo_param_valor_v1(v->>'param')::numeric + COALESCE((v->>'mas')::numeric, 0));
    END IF;
    RETURN v;
  END IF;
  IF c->>'op' IS NULL OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=','+','-','*','/','max','min','suma','redondeo') THEN
    RAISE EXCEPTION 'NUCLEO_EVAL_OPERADOR_INVALIDO: %', c->>'op';
  END IF;
  IF c->>'op' = 'no' THEN RETURN to_jsonb(NOT (saly.nucleo_eval_v1(c->'izq', e))::text::boolean); END IF;
  -- Cálculo: suma de una lista (opcionalmente de un campo de cada elemento)
  IF c->>'op' = 'suma' THEN
    a := saly.nucleo_eval_v1(c->'lista', e);
    IF jsonb_typeof(a) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'NUCLEO_EVAL_LISTA_INVALIDA: %', a; END IF;
    x := 0;
    FOR it IN SELECT value FROM jsonb_array_elements(a) LOOP
      v := CASE WHEN c ? 'campo' THEN it->(c->>'campo') ELSE it END;
      IF jsonb_typeof(v) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: % en la lista', coalesce(v::text, 'ausente'); END IF;
      x := x + (v #>> '{}')::numeric;
    END LOOP;
    RETURN to_jsonb(x);
  END IF;
  a := saly.nucleo_eval_v1(c->'izq', e);
  -- Cálculo: redondeo a los decimales indicados por un parámetro
  IF c->>'op' = 'redondeo' THEN
    b := saly.nucleo_eval_v1(c->'decimales', e);
    IF jsonb_typeof(a) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: %', a; END IF;
    IF jsonb_typeof(b) IS DISTINCT FROM 'number' OR (b #>> '{}')::numeric NOT BETWEEN 0 AND 10
       OR (b #>> '{}')::numeric <> trunc((b #>> '{}')::numeric) THEN
      RAISE EXCEPTION 'NUCLEO_EVAL_DECIMALES_INVALIDOS: %', b;
    END IF;
    x := (a #>> '{}')::numeric; d := power(10::numeric, (b #>> '{}')::int);
    RETURN to_jsonb(round(CASE c->>'modo' WHEN 'piso' THEN floor(x * d) / d WHEN 'techo' THEN ceil(x * d) / d ELSE round(x, (b #>> '{}')::int) END, (b #>> '{}')::int));
  END IF;
  b := saly.nucleo_eval_v1(c->'der', e);
  IF c->>'op' IN ('+','-','*','/','max','min') THEN
    IF jsonb_typeof(a) IS DISTINCT FROM 'number' OR jsonb_typeof(b) IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'NUCLEO_EVAL_NO_NUMERICO: % % %', a, c->>'op', b;
    END IF;
    x := (a #>> '{}')::numeric; y := (b #>> '{}')::numeric;
    IF c->>'op' = '/' AND y = 0 THEN RAISE EXCEPTION 'NUCLEO_EVAL_DIVISION_CERO: % / 0', x; END IF;
    RETURN to_jsonb(CASE c->>'op' WHEN '+' THEN x + y WHEN '-' THEN x - y WHEN '*' THEN x * y WHEN '/' THEN x / y
                                  WHEN 'max' THEN greatest(x, y) ELSE least(x, y) END);
  END IF;
  RETURN to_jsonb(CASE c->>'op'
    WHEN 'y'  THEN a::text::boolean AND b::text::boolean
    WHEN 'o'  THEN a::text::boolean OR b::text::boolean
    WHEN '='  THEN a = b
    WHEN '!=' THEN a <> b
    WHEN '>'  THEN (a #>> '{}')::numeric >  (b #>> '{}')::numeric
    WHEN '>=' THEN (a #>> '{}')::numeric >= (b #>> '{}')::numeric
    WHEN '<'  THEN (a #>> '{}')::numeric <  (b #>> '{}')::numeric
    WHEN '<=' THEN (a #>> '{}')::numeric <= (b #>> '{}')::numeric
    END);
END $function$;

CREATE OR REPLACE FUNCTION saly.nucleo_condicion_problema_v1(c jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE hojas integer;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RETURN 'nodo que no es objeto: ' || coalesce(c::text, 'nulo'); END IF;
  hojas := (c ? 'hecho')::int + (c ? 'param')::int + (c ? 'lit')::int;
  IF hojas > 1 OR (hojas = 1 AND c ? 'op') THEN RETURN 'nodo con más de un tipo: ' || c::text; END IF;
  IF hojas = 1 THEN
    IF (c ? 'hecho' AND jsonb_typeof(c->'hecho') <> 'string') OR (c ? 'param' AND (jsonb_typeof(c->'param') <> 'string' OR c->>'param' !~ '^[A-Z][A-Z0-9_]*\.[A-Z0-9_.]+$'))
      THEN RETURN 'hoja mal escrita: ' || c::text; END IF;
    RETURN NULL;
  END IF;
  IF NOT c ? 'op' OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=','+','-','*','/','max','min','suma','redondeo') THEN RETURN 'operador desconocido o ausente: ' || c::text; END IF;
  IF c->>'op' = 'no' THEN RETURN saly.nucleo_condicion_problema_v1(c->'izq'); END IF;
  IF c->>'op' = 'suma' THEN
    IF c ? 'campo' AND (jsonb_typeof(c->'campo') <> 'string' OR btrim(c->>'campo') = '') THEN RETURN 'suma con campo mal escrito: ' || c::text; END IF;
    RETURN saly.nucleo_condicion_problema_v1(c->'lista');
  END IF;
  IF c->>'op' = 'redondeo' THEN
    IF c->>'modo' IS NULL OR c->>'modo' NOT IN ('piso','techo','normal') THEN RETURN 'redondeo sin modo piso, techo o normal: ' || c::text; END IF;
    RETURN COALESCE(saly.nucleo_condicion_problema_v1(c->'izq'), saly.nucleo_condicion_problema_v1(c->'decimales'));
  END IF;
  RETURN COALESCE(saly.nucleo_condicion_problema_v1(c->'izq'), saly.nucleo_condicion_problema_v1(c->'der'));
END $function$;

CREATE OR REPLACE FUNCTION saly.nucleo_nodos_condicion_v1(c jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH RECURSIVE t(n) AS (
    SELECT c WHERE jsonb_typeof(c) = 'object'
    UNION ALL
    SELECT x FROM t, LATERAL (VALUES (t.n->'izq'), (t.n->'der'), (t.n->'lista'), (t.n->'decimales')) y(x)
     WHERE x IS NOT NULL AND jsonb_typeof(x) = 'object')
  SELECT n FROM t
$function$;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_datos_v1()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE v_raiz text := (SELECT codigo FROM saly.nucleo_nodos WHERE nivel = 'GLOBAL');
BEGIN
  IF v_raiz IS NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_SIN_RAIZ'; END IF;
  INSERT INTO saly.nucleo_familias (codigo, dominio, origen, descripcion, estado, min_pruebas, tipo) VALUES
    ('ZZT_FAM','BACKEND','NUEVA','Familia de prueba del núcleo (autotest)','ACTIVA',2,'TECNICA'),
    ('ZZT_FAM_MANUAL','BACKEND','NUEVA','Familia de prueba que siempre pide decisión humana (autotest)','ACTIVA',2,'TECNICA');
  INSERT INTO saly.nucleo_hechos (codigo, tipo_dato, unidad, descripcion) VALUES
    ('zzt_intentos','integer','veces','Intentos de prueba del núcleo (autotest)'),
    ('zzt_inactividad','integer','segundos','Inactividad de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_intentos','CURADO'), ('ZZT_FAM_MANUAL','zzt_inactividad','CURADO');
  INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MAX_INTENTOS','3','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)'),
    ('ZZT','INACTIVIDAD_MAX','900','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion) VALUES ('ZZT-Q','POLITICA','Autoridad de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_nodos (codigo, padre, nivel) VALUES
    ('ZZT-AMB', v_raiz, 'AMBITO'), ('ZZT-BACK', v_raiz, 'AMBITO'), ('ZZT-MOD-1', 'ZZT-AMB', 'MODULO'), ('ZZT-MOD-2', 'ZZT-AMB', 'MODULO');
  UPDATE saly.config_global g SET config_value = (g.config_value::jsonb || to_jsonb(x.extra))::text
    FROM (VALUES ('AMBITOS_PANTALLA','ZZT-AMB'), ('AMBITOS_BACKEND','ZZT-BACK')) x(clave, extra)
   WHERE g.scope = 'NUCLEO' AND g.config_key = x.clave
     AND g.valid_from = (SELECT max(valid_from) FROM saly.config_global WHERE scope = 'NUCLEO' AND config_key = x.clave AND valid_from <= now());
  UPDATE saly.config_global g SET config_value = (g.config_value::jsonb || '["ZZT_FAM_MANUAL"]')::text
   WHERE g.scope = 'NUCLEO_EVAL' AND g.config_key = 'FAMILIAS_SIEMPRE_MANUAL'
     AND g.valid_from = (SELECT max(valid_from) FROM saly.config_global WHERE scope = 'NUCLEO_EVAL' AND config_key = 'FAMILIAS_SIEMPRE_MANUAL' AND valid_from <= now());
  -- Datos de prueba para operaciones de cálculo
  INSERT INTO saly.nucleo_hechos (codigo, tipo_dato, unidad, descripcion) VALUES
    ('zzt_monto','decimal','soles','Monto de prueba del núcleo (autotest de cálculo)'),
    ('zzt_items','json','ninguna','Lista de montos de prueba del núcleo (autotest de cálculo)');
  INSERT INTO saly.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_monto','CURADO'), ('ZZT_FAM','zzt_items','CURADO');
  INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MONTO_BASE','100.555','DECIMAL','REAL','Monto de prueba del núcleo (autotest de cálculo)'),
    ('ZZT','DECIMALES','2','INTEGER','REAL','Decimales de prueba del núcleo (autotest de cálculo)');
END $function$;

CREATE OR REPLACE FUNCTION saly.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  ctl jsonb := '[]'::jsonb;
  v_fam record; v_falta text; v_txt text; v_n integer; v_ok boolean;
  v_clase text := upper(p->>'clase'); v_nat text := upper(p->>'naturaleza'); v_alc text := p->>'alcance';
  v_ambito text; v_nivel text; v_clasif text := 'NUEVA'; v_prueba jsonb; v_res jsonb; v_bloq integer;
  v_lits jsonb; v_efectos jsonb;
  v_tipo text := upper(COALESCE(p->>'tipo','NUEVA')); v_r0 record; v_nodo0 text; v_ultima record; v_ver integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_proponer:' || coalesce(p->>'clave', ''), 0));

  -- 0 identidad: NUEVA exige código libre; CAMBIO exige la regla existente con la misma identidad y alcance, sin otra candidata
  IF v_tipo = 'NUEVA' THEN
    v_ok := p->>'codigo' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nucleo_reglas WHERE codigo = p->>'codigo');
    ctl := ctl || jsonb_build_object('n',0,'control','Código libre','ok',v_ok,'bloqueante',true,
      'detalle', CASE WHEN v_ok THEN '' ELSE 'El código ya existe o falta: use otro código o proponga un CAMBIO de la regla existente.' END);
  ELSIF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_r0 FROM nucleo_reglas WHERE codigo = p->>'codigo';
    SELECT nodo INTO v_nodo0 FROM nucleo_aplicaciones WHERE regla = p->>'codigo' ORDER BY nodo LIMIT 1;
    v_txt := CASE
      WHEN v_r0.codigo IS NULL THEN 'La regla ' || COALESCE(p->>'codigo','(vacía)') || ' no existe: proponga una regla NUEVA.'
      WHEN v_r0.estado NOT IN ('CANDIDATA','VIGENTE') THEN 'La regla está ' || v_r0.estado || ' y no admite cambios.'
      WHEN v_r0.clave <> p->>'clave' OR v_r0.familia <> p->>'familia' OR v_r0.naturaleza <> v_nat THEN 'Un cambio no altera clave, familia ni naturaleza: eso es una regla nueva.'
      WHEN v_nodo0 IS DISTINCT FROM v_alc THEN 'Un cambio no altera el alcance (' || COALESCE(v_nodo0,'-') || '): eso es una regla nueva o una especialización.'
      WHEN EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado = 'CANDIDATA') THEN 'Ya hay una versión candidata abierta: promuévala o descártela antes de otro cambio.'
      END;
    ctl := ctl || jsonb_build_object('n',0,'control','Regla a cambiar','ok',v_txt IS NULL,'bloqueante',true,'detalle',COALESCE(v_txt,''));
  ELSE
    ctl := ctl || jsonb_build_object('n',0,'control','Tipo de propuesta','ok',false,'bloqueante',true,'detalle','El tipo debe ser NUEVA o CAMBIO.');
  END IF;

  -- 1 familia existe
  SELECT * INTO v_fam FROM nucleo_familias WHERE codigo = p->>'familia';
  v_ok := FOUND AND v_fam.estado <> 'RETIRADA';
  ctl := ctl || jsonb_build_object('n',1,'control','Familia existe','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'familia' ELSE 'La familia ' || coalesce(p->>'familia','(vacía)') || ' no existe o está retirada: elija una de saly.nucleo_familias.' END);

  -- 2 campos del contrato (global + extensión de la familia)
  SELECT string_agg(k.campo, ', ' ORDER BY k.campo) INTO v_falta FROM nucleo_contrato_campos k
   WHERE (k.familia IS NULL OR k.familia = p->>'familia')
     AND (NOT p ? k.campo OR jsonb_typeof(p->k.campo) = 'null' OR btrim(p->>k.campo) = '' OR p->k.campo IN ('[]'::jsonb, '{}'::jsonb));
  ctl := ctl || jsonb_build_object('n',2,'control','Campos obligatorios','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Faltan o están vacíos: ' || v_falta END);

  v_txt := nucleo_condicion_problema_v1(p->'condicion');
  ctl := ctl || jsonb_build_object('n',2,'control','Condición bien formada','ok',v_txt IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=; para cálculos +, -, *, /, max, min, suma (lista, campo) y redondeo (modo piso|techo|normal, decimales).' END);

  v_ok := jsonb_typeof(p->'origen') = 'object' AND p->'origen'->>'tipo' IN ('IG','CHAT','PERSONA','MIGRACION')
          AND length(btrim(COALESCE(p->'origen'->>'ref',''))) >= 3 AND length(btrim(COALESCE(p->'origen'->>'solicitante',''))) >= 3;
  ctl := ctl || jsonb_build_object('n',2,'control','Origen del cambio','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'El origen debe indicar tipo (IG, CHAT, PERSONA o MIGRACION), referencia y solicitante.' END);
  v_ok := upper(p->>'impacto') IN ('NINGUNO','REVISAR','IMPLEMENTAR') AND NOT (v_tipo = 'NUEVA' AND upper(p->>'impacto') = 'NINGUNO')
          AND (p->'plazo_dias' IS NULL OR (jsonb_typeof(p->'plazo_dias') = 'number' AND (p->>'plazo_dias')::numeric >= 0 AND (p->>'plazo_dias')::numeric = trunc((p->>'plazo_dias')::numeric)));
  ctl := ctl || jsonb_build_object('n',18,'control','Impacto declarado','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'Impacto NINGUNO, REVISAR o IMPLEMENTAR (una regla nueva no puede ser NINGUNO); plazo_dias entero no negativo.' END);

  -- 3 alcance existe
  SELECT nivel INTO v_nivel FROM nucleo_nodos WHERE codigo = v_alc;
  ctl := ctl || jsonb_build_object('n',3,'control','Alcance existe','ok',v_nivel IS NOT NULL,'bloqueante',true,
    'detalle', CASE WHEN v_nivel IS NOT NULL THEN v_alc ELSE 'El alcance ' || coalesce(v_alc,'(vacío)') || ' no es un nodo del árbol (saly.v_nucleo_nodos).' END);

  -- 4 datos dentro del vocabulario de la familia
  SELECT string_agg(DISTINCT x->>'hecho', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'hecho' AND NOT EXISTS (SELECT 1 FROM nucleo_familia_vocabulario v WHERE v.familia = p->>'familia' AND v.hecho = x->>'hecho');
  ctl := ctl || jsonb_build_object('n',4,'control','Datos dentro del vocabulario','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Datos fuera del vocabulario de la familia: ' || v_falta || '. Use un hecho de saly.v_nucleo_vocabulario o regístrelo primero.' END);

  -- 5 sin datos fijos (literales permitidos en NUCLEO.LITERALES_PERMITIDOS)
  v_lits := COALESCE(nucleo_param_valor_v1('NUCLEO.LITERALES_PERMITIDOS')::jsonb, '[]'::jsonb);
  SELECT string_agg(x->>'lit', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'number' AND NOT v_lits @> jsonb_build_array(x->'lit');
  ctl := ctl || jsonb_build_object('n',5,'control','Sin datos fijos','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Valores fijos en la condición: ' || v_falta || '. Reemplácelos por {"param":"SCOPE.CLAVE"} de config_global.' END);
  SELECT string_agg(x->>'lit', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'string';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',5,'control','Textos fijos en la condición','ok',false,'bloqueante',false,
      'detalle','Verifique que sean valores de una lista del vocabulario: ' || v_txt);
  END IF;

  -- 6 parámetros existen
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND nucleo_param_valor_v1(x->>'param') IS NULL;
  ctl := ctl || jsonb_build_object('n',6,'control','Parámetros existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Parámetros inexistentes en config_global: ' || v_falta END);

  -- 13 unidades compatibles (hecho comparado con un parámetro registrado en nucleo_parametros)
  SELECT string_agg(format('%s (%s) vs %s (%s)', hi.codigo, hi.unidad, pa.scope || '.' || pa.config_key, hp.unidad), '; ') INTO v_falta
    FROM nucleo_nodos_condicion_v1(p->'condicion') x
    JOIN nucleo_hechos hi ON hi.codigo = COALESCE(x->'izq'->>'hecho', x->'der'->>'hecho')
    JOIN nucleo_parametros pa ON pa.scope || '.' || pa.config_key = COALESCE(x->'der'->>'param', x->'izq'->>'param')
    JOIN nucleo_hechos hp ON hp.codigo = pa.hecho
   WHERE x->>'op' IN ('>','>=','<','<=','=','!=') AND hi.unidad IS DISTINCT FROM hp.unidad;
  ctl := ctl || jsonb_build_object('n',13,'control','Unidades compatibles','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Unidades distintas: ' || v_falta END);
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND NOT EXISTS (SELECT 1 FROM nucleo_parametros pa WHERE pa.scope || '.' || pa.config_key = x->>'param');
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',13,'control','Parámetro sin metadatos','ok',false,'bloqueante',false,
      'detalle','Registre en saly.nucleo_parametros el dato y la unidad de: ' || v_txt || ' (sin eso no se puede verificar la unidad).');
  END IF;

  -- 14 parámetro real (no de muestra)
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM saly.config_global g WHERE g.scope || '.' || g.config_key = x->>'param' AND g.value_status <> 'REAL');
  ctl := ctl || jsonb_build_object('n',14,'control','Parámetros con valor real','ok',v_txt IS NULL,'bloqueante',false,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'Usan valor de muestra (no bloquea el desarrollo, sí la producción): ' || v_txt END);

  -- 7 pruebas mínimas de la familia
  v_n := CASE WHEN jsonb_typeof(p->'pruebas') = 'array' THEN jsonb_array_length(p->'pruebas') ELSE 0 END;
  v_ok := v_fam.codigo IS NOT NULL AND v_n >= v_fam.min_pruebas;
  ctl := ctl || jsonb_build_object('n',7,'control','Pruebas mínimas de la familia','ok',v_ok,'bloqueante',true,
    'detalle', format('%s de %s', v_n, coalesce(v_fam.min_pruebas::text,'?')));

  SELECT string_agg(DISTINCT t->>'casuistica', ', ') INTO v_falta
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t
   WHERE t ? 'casuistica' AND NOT EXISTS (SELECT 1 FROM nucleo_casuisticas k WHERE k.codigo = t->>'casuistica' AND k.estado = 'ACTIVA'
         AND k.naturaleza = v_nat AND (k.familia IS NULL OR k.familia = p->>'familia'));
  ctl := ctl || jsonb_build_object('n',7,'control','Casuísticas conocidas','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Casuísticas que no existen para esta familia y naturaleza: ' || v_falta || ' (ver saly.nucleo_casuisticas).' END);

  -- 8 pruebas relativas al parámetro (ningún valor numérico fijo como entrada)
  SELECT count(*) INTO v_n FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t,
       jsonb_each(COALESCE(t->'entrada','{}'::jsonb)) kv
   WHERE jsonb_typeof(kv.value) = 'number' AND NOT v_lits @> jsonb_build_array(kv.value);
  ctl := ctl || jsonb_build_object('n',8,'control','Pruebas relativas al parámetro','ok',v_n = 0,'bloqueante',true,
    'detalle', CASE WHEN v_n = 0 THEN '' ELSE v_n || ' entradas con valor fijo: use {"param":"SCOPE.CLAVE","mas":n}.' END);

  -- 15 las pruebas se ejecutan y pasan
  v_falta := NULL;
  IF jsonb_typeof(p->'pruebas') = 'array' THEN
    FOR v_prueba IN SELECT value FROM jsonb_array_elements(p->'pruebas') LOOP
      BEGIN
        v_res := nucleo_eval_v1(p->'condicion', v_prueba->'entrada');
        IF v_res IS DISTINCT FROM v_prueba->'esperado' THEN
          v_falta := concat_ws('; ', v_falta, format('entrada %s dio %s y se esperaba %s', v_prueba->'entrada', v_res, v_prueba->'esperado'));
        END IF;
      EXCEPTION WHEN others THEN
        v_falta := concat_ws('; ', v_falta, 'error al evaluar: ' || SQLERRM);
      END;
    END LOOP;
  END IF;
  ctl := ctl || jsonb_build_object('n',15,'control','Pruebas se ejecutan y pasan','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', coalesce(v_falta,''));

  -- 16 autoridad registrada y vigente
  v_ok := EXISTS (SELECT 1 FROM nucleo_autoridades WHERE codigo = p->>'autoridad' AND estado = 'VIGENTE');
  ctl := ctl || jsonb_build_object('n',16,'control','Autoridad vigente','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'autoridad' ELSE 'La autoridad ' || coalesce(p->>'autoridad','(vacía)') || ' no está en saly.nucleo_autoridades o no está vigente.' END);

  -- 17 dependencias existen (no vigentes: aviso, frenan la promoción)
  SELECT string_agg(d, ', ') INTO v_falta FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   WHERE NOT EXISTS (SELECT 1 FROM nucleo_reglas r WHERE r.codigo = d);
  ctl := ctl || jsonb_build_object('n',17,'control','Dependencias existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Dependencias inexistentes: ' || v_falta END);
  SELECT string_agg(d, ', ') INTO v_txt FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   JOIN nucleo_reglas r ON r.codigo = d WHERE r.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',17,'control','Depende de reglas no vigentes','ok',false,'bloqueante',false,
      'detalle','Entra como candidata, pero no podrá promoverse hasta que estén vigentes: ' || v_txt);
  END IF;

  -- 18 efecto coherente con la naturaleza
  v_efectos := COALESCE(nucleo_param_valor_v1(CASE v_nat WHEN 'DEFINICION' THEN 'NUCLEO.EFECTOS_DEFINICION' ELSE 'NUCLEO.EFECTOS_CONDUCTA' END)::jsonb, '[]');
  v_ok := v_nat IN ('CONDUCTA','DEFINICION') AND v_efectos @> jsonb_build_array(upper(p->>'efecto'));
  ctl := ctl || jsonb_build_object('n',18,'control','Efecto coherente con la naturaleza','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Una regla de %s no puede tener el efecto %s; válidos: %s', coalesce(v_nat,'?'), coalesce(p->>'efecto','?'), v_efectos) END);

  -- 19 clase coherente con el alcance
  WITH RECURSIVE anc(c, nv) AS (
    SELECT codigo, nivel FROM nucleo_nodos WHERE codigo = v_alc
    UNION ALL SELECT n.padre, (SELECT nivel FROM nucleo_nodos WHERE codigo = n.padre)
      FROM nucleo_nodos n JOIN anc ON n.codigo = anc.c WHERE n.padre IS NOT NULL)
  SELECT max(c) FILTER (WHERE nv = 'AMBITO') INTO v_ambito FROM anc;
  v_ok := CASE v_clase
    WHEN 'BACKEND' THEN v_nivel = 'GLOBAL' OR COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_BACKEND')::jsonb, '[]') @> jsonb_build_array(v_ambito)
    WHEN 'PANTALLA' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_PANTALLA')::jsonb, '[]') @> jsonb_build_array(v_ambito)
    WHEN 'TRANSVERSAL' THEN v_nivel IN ('GLOBAL','AMBITO')
    ELSE false END;
  ctl := ctl || jsonb_build_object('n',19,'control','Clase coherente con el alcance','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Clase %s no corresponde al alcance %s (nivel %s, ámbito %s).', coalesce(v_clase,'?'), coalesce(v_alc,'?'), coalesce(v_nivel,'?'), coalesce(v_ambito,'-')) END);

  -- 9 sin conflicto con una regla FIJA superior de la misma clave
  IF v_nivel IS NOT NULL THEN
    SELECT string_agg(e.regla || ' en ' || e.nodo_origen, ', ') INTO v_falta
      FROM nucleo_reglas_efectivas_v1(v_alc) e WHERE e.clave = p->>'clave' AND e.modo = 'FIJA' AND e.distancia > 0;
  END IF;
  ctl := ctl || jsonb_build_object('n',9,'control','Sin conflicto con reglas fijas superiores','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Existe una regla FIJA superior con la misma clave: ' || v_falta END);

  -- 10 clasificación contra lo existente
  SELECT CASE WHEN a.nodo = v_alc AND v.condicion = p->'condicion' THEN 'DUPLICADO_DE ' || r.codigo
              WHEN a.nodo = v_alc THEN 'NUEVA_VERSION_DE ' || r.codigo
              ELSE 'ESPECIALIZA ' || r.codigo END
    INTO v_clasif
    FROM nucleo_reglas r
    JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND r.familia = p->>'familia' AND r.estado NOT IN ('RETIRADA') AND r.codigo IS DISTINCT FROM CASE WHEN v_tipo = 'CAMBIO' THEN p->>'codigo' END
     AND (a.nodo = v_alc OR a.nodo IN (
       WITH RECURSIVE up(c) AS (SELECT padre FROM nucleo_nodos WHERE codigo = v_alc
         UNION ALL SELECT n.padre FROM nucleo_nodos n JOIN up ON n.codigo = up.c WHERE n.padre IS NOT NULL)
       SELECT c FROM up WHERE c IS NOT NULL))
   ORDER BY (a.nodo = v_alc) DESC LIMIT 1;
  v_clasif := COALESCE(v_clasif, 'NUEVA');
  ctl := ctl || jsonb_build_object('n',10,'control','Clasificación contra lo existente',
    'ok', v_clasif NOT LIKE 'DUPLICADO%' AND v_clasif NOT LIKE 'NUEVA_VERSION%','bloqueante',true,
    'detalle', CASE WHEN v_clasif LIKE 'DUPLICADO%' THEN v_clasif || ': ya existe igual en el mismo alcance.'
                    WHEN v_clasif LIKE 'NUEVA_VERSION%' THEN v_clasif || ': es un cambio de una regla existente; use la ruta de versión de esa regla.'
                    ELSE v_clasif END);

  IF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_ultima FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado <> 'DESCARTADA' ORDER BY version DESC LIMIT 1;
    IF v_ultima.version IS NOT NULL
       AND ROW(v_ultima.titulo, v_ultima.descripcion, v_ultima.condicion, v_ultima.efecto, v_ultima.autoridad, v_ultima.impacto)
           IS NOT DISTINCT FROM ROW(p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad', upper(p->>'impacto'))
       AND (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',casuistica,'e',entrada,'x',esperado) ORDER BY n), '[]') FROM nucleo_regla_pruebas
             WHERE regla = v_ultima.regla AND version = v_ultima.version)
           IS NOT DISTINCT FROM (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',t.v->>'casuistica','e',t.v->'entrada','x',t.v->'esperado') ORDER BY t.o), '[]')
             FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) WITH ORDINALITY t(v, o)) THEN
      ctl := ctl || jsonb_build_object('n',10,'control','Cambio con contenido','ok',false,'bloqueante',true,
        'detalle','SIN_CAMBIOS: igual a la versión ' || v_ultima.version || '.');
    END IF;
  END IF;

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto','ok',false,'bloqueante',false,
      'detalle','Ya existe idéntica en otros nodos (' || v_txt || '): considere registrarla una vez en el nodo común y retirar las copias.');
  END IF;

  -- 12 hacia abajo: reglas de la misma clave en los descendientes (aviso)
  WITH RECURSIVE dn(c) AS (SELECT v_alc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
   WHERE r.clave = p->>'clave' AND a.nodo IN (SELECT c FROM dn) AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',12,'control','Impacto hacia abajo','ok',false,'bloqueante',false,
      'detalle', CASE WHEN upper(p->>'modo') = 'FIJA' THEN 'Es FIJA y hay reglas de la misma clave abajo (deben resolverse antes de promover): '
                      ELSE 'Hay reglas de la misma clave abajo (quedan como especialización): ' END || v_txt);
  END IF;

  SELECT count(*) INTO v_bloq FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;

  IF v_bloq = 0 AND p_aplicar THEN
    IF v_tipo = 'NUEVA' THEN
      INSERT INTO nucleo_reglas (codigo, clave, familia, naturaleza, estado)
      VALUES (p->>'codigo', p->>'clave', p->>'familia', v_nat, 'CANDIDATA');
      INSERT INTO nucleo_aplicaciones (regla, nodo, modo) VALUES (p->>'codigo', v_alc, upper(p->>'modo'));
    END IF;
    INSERT INTO nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, plazo_dias)
    VALUES (p->>'codigo', p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad',
            upper(p->>'impacto'), p->'origen', p - 'pruebas', (p->>'plazo_dias')::int)
    RETURNING version INTO v_ver;
    INSERT INTO nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    SELECT p->>'codigo', v_ver, t.ord::int, t.v->>'casuistica', t.v->'entrada', t.v->'esperado'
      FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY t(v, ord);
    INSERT INTO nucleo_relaciones (origen, destino, tipo)
    SELECT p->>'codigo', d, 'DEPENDE' FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
     WHERE NOT EXISTS (SELECT 1 FROM nucleo_relaciones x WHERE x.origen = p->>'codigo' AND x.destino = d AND x.tipo = 'DEPENDE');
  END IF;

  RETURN jsonb_build_object(
    'resultado', CASE WHEN v_bloq > 0 THEN 'RECHAZADA' WHEN p_aplicar THEN 'CANDIDATA' ELSE 'EVALUADA_SIN_ESCRIBIR' END,
    'tipo', v_tipo, 'version', v_ver, 'clasificacion', v_clasif, 'bloqueantes', v_bloq,
    'avisos', (SELECT count(*) FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND NOT (x->>'bloqueante')::boolean),
    'controles', ctl);
END $function$;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_calculo_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  k record; v_res jsonb; v_err text; v_n integer := 0; r jsonb; v_txt text;
  m jsonb := '{"param":"ZZT.MONTO_BASE"}'; dec jsonb := '{"param":"ZZT.DECIMALES"}'; tres jsonb := '{"param":"ZZT.MAX_INTENTOS"}';
  items jsonb := '[{"monto":10.5},{"monto":4.25},{"monto":0.25}]';
  base jsonb;
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    -- K1-K4 evaluación: resultado esperado o código de error esperado
    FOR k IN SELECT * FROM (VALUES
      ('K1 suma de dos parámetros',   jsonb_build_object('op','+','izq',tres,'der',tres), '{}'::jsonb, '6'::jsonb, NULL::text),
      ('K1 resta',                    jsonb_build_object('op','-','izq',m,'der',tres), '{}', '97.555', NULL),
      ('K1 producto',                 jsonb_build_object('op','*','izq',tres,'der',dec), '{}', '6', NULL),
      ('K1 división',                 jsonb_build_object('op','/','izq',tres,'der',tres), '{}', '1', NULL),
      ('K1 máximo',                   jsonb_build_object('op','max','izq',tres,'der',dec), '{}', '3', NULL),
      ('K1 mínimo',                   jsonb_build_object('op','min','izq',tres,'der',dec), '{}', '2', NULL),
      ('K1 hecho relativo al param',  jsonb_build_object('op','+','izq','{"hecho":"zzt_monto"}'::jsonb,'der',tres), jsonb_build_object('zzt_monto','{"param":"ZZT.MONTO_BASE","mas":1}'::jsonb), '104.555', NULL),
      ('K2 suma de un campo',         jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items',items), '15', NULL),
      ('K2 suma de lista simple',     jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb), jsonb_build_object('zzt_items','[1.5,2.5]'::jsonb), '4', NULL),
      ('K2 suma de lista vacía',      jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items','[]'::jsonb), '0', NULL),
      ('K3 redondeo piso',            jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',dec), '{}', '100.55', NULL),
      ('K3 redondeo techo',           jsonb_build_object('op','redondeo','modo','techo','izq',m,'decimales',dec), '{}', '100.56', NULL),
      ('K3 redondeo normal',          jsonb_build_object('op','redondeo','modo','normal','izq',m,'decimales',dec), '{}', '100.56', NULL),
      ('K3 cálculo dentro de una comparación', jsonb_build_object('op','>','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'),'der',m), jsonb_build_object('zzt_items',items), 'false', NULL),
      ('K4 división entre cero',      jsonb_build_object('op','/','izq',tres,'der',jsonb_build_object('op','-','izq',tres,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DIVISION_CERO'),
      ('K4 lista que no es lista',    jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb), jsonb_build_object('zzt_items','{"monto":1}'::jsonb), NULL, 'NUCLEO_EVAL_LISTA_INVALIDA'),
      ('K4 elemento sin el campo',    jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'), jsonb_build_object('zzt_items','[{"otro":1}]'::jsonb), NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 operando de texto',        jsonb_build_object('op','+','izq',tres,'der','{"lit":"tres"}'::jsonb), '{}', NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 decimales negativos',      jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',jsonb_build_object('op','-','izq',dec,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DECIMALES_INVALIDOS'),
      ('K4 decimales no enteros',     jsonb_build_object('op','redondeo','modo','piso','izq',m,'decimales',jsonb_build_object('op','/','izq',dec,'der',tres)), '{}', NULL, 'NUCLEO_EVAL_DECIMALES_INVALIDOS'),
      ('K4 redondeo de un texto',     jsonb_build_object('op','redondeo','modo','piso','izq','{"lit":"x"}'::jsonb,'decimales',dec), '{}', NULL, 'NUCLEO_EVAL_NO_NUMERICO'),
      ('K4 operador inventado',       '{"op":"potencia","izq":{"lit":1},"der":{"lit":1}}'::jsonb, '{}', NULL, 'NUCLEO_EVAL_OPERADOR_INVALIDO')
    ) t(caso, cond, entrada, esperado, error) LOOP
      v_res := NULL; v_err := NULL;
      BEGIN v_res := saly.nucleo_eval_v1(k.cond, k.entrada); EXCEPTION WHEN others THEN v_err := SQLERRM; END;
      IF k.error IS NULL AND (v_err IS NOT NULL OR v_res IS DISTINCT FROM k.esperado) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % obtuvo % (error %)', k.caso, v_res, v_err;
      END IF;
      IF k.error IS NOT NULL AND (v_err IS NULL OR split_part(v_err, ':', 1) <> k.error) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % debía fallar con % y obtuvo % / %', k.caso, k.error, v_res, v_err;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- K5 forma: rechaza cálculos mal escritos y acepta los bien escritos
    FOR k IN SELECT * FROM (VALUES
      ('K5 suma sin lista',        '{"op":"suma","campo":"monto"}'::jsonb, false),
      ('K5 suma con campo vacío',  '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":""}'::jsonb, false),
      ('K5 suma con campo número', '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":1}'::jsonb, false),
      ('K5 redondeo sin modo',     '{"op":"redondeo","izq":{"hecho":"zzt_monto"},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 redondeo modo raro',    '{"op":"redondeo","modo":"banquero","izq":{"hecho":"zzt_monto"},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 redondeo sin decimales','{"op":"redondeo","modo":"piso","izq":{"hecho":"zzt_monto"}}'::jsonb, false),
      ('K5 operador inventado',    '{"op":"potencia","izq":{"hecho":"zzt_monto"},"der":{"param":"ZZT.DECIMALES"}}'::jsonb, false),
      ('K5 resta sin der',         '{"op":"-","izq":{"hecho":"zzt_monto"}}'::jsonb, false),
      ('K5 suma bien escrita',     '{"op":"suma","lista":{"hecho":"zzt_items"},"campo":"monto"}'::jsonb, true),
      ('K5 redondeo bien escrito', '{"op":"redondeo","modo":"techo","izq":{"op":"*","izq":{"hecho":"zzt_monto"},"der":{"param":"ZZT.MAX_INTENTOS"}},"decimales":{"param":"ZZT.DECIMALES"}}'::jsonb, true)
    ) t(caso, cond, valida) LOOP
      IF (saly.nucleo_condicion_problema_v1(k.cond) IS NULL) IS DISTINCT FROM k.valida THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % (problema: %)', k.caso, saly.nucleo_condicion_problema_v1(k.cond);
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- K6 puerta: una regla de definición con efecto CALCULAR entra como candidata
    base := jsonb_build_object('codigo','ZZT-K-1','clave','zzt_k_uno','titulo','Total redondeado de prueba',
      'descripcion','Calcula el total de los montos de la lista redondeado hacia abajo a los decimales configurados',
      'familia','ZZT_FAM','naturaleza','DEFINICION','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-BACK','modo','HEREDA',
      'clase','BACKEND','efecto','CALCULAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-calculo','solicitante','autotest'),
      'condicion', jsonb_build_object('op','redondeo','modo','piso','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb,'campo','monto'),'decimales',dec),
      'pruebas', jsonb_build_array(
        jsonb_build_object('entrada',jsonb_build_object('zzt_items','[{"monto":10.555},{"monto":4.25}]'::jsonb),'esperado',14.80),
        jsonb_build_object('entrada',jsonb_build_object('zzt_items','[]'::jsonb),'esperado',0)));
    r := saly.nucleo_regla_proponer_v1(base, false);
    SELECT string_agg(x->>'control' || ': ' || (x->>'detalle'), '; ') INTO v_txt FROM jsonb_array_elements(r->'controles') x
     WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
    IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 regla de cálculo rechazada: %', v_txt; END IF;
    v_n := v_n + 1;
    -- K7 decimales fijos en el redondeo se detectan como dato fijo
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('condicion', jsonb_set(base->'condicion', '{decimales}', '{"lit":2}')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Sin datos fijos' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K7 decimales fijos no detectados';
    END IF;
    v_n := v_n + 1;
    -- K8 un dato fuera del vocabulario dentro de la lista se detecta
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('condicion', jsonb_set(base->'condicion', '{izq,lista}', '{"hecho":"zzt_inactividad"}')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Datos dentro del vocabulario' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 dato fuera de vocabulario en la lista no detectado';
    END IF;
    v_n := v_n + 1;
    -- K9 una regla de cálculo con efecto de conducta se rechaza
    r := saly.nucleo_regla_proponer_v1(base || '{"efecto":"BLOQUEAR"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Efecto coherente con la naturaleza' AND (x->>'ok')::boolean IS NOT TRUE) THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K9 efecto incoherente aceptado';
    END IF;
    v_n := v_n + 1;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'CALCULO ' || v_n || '/' || v_n;
END $function$;

INSERT INTO saly.nucleo_errores (codigo, puerta, significado, accion) VALUES
  ('NUCLEO_EVAL_DIVISION_CERO','PROPUESTA','Un cálculo divide entre cero con los valores de la prueba','Revisar el divisor o agregar una condición que lo excluya'),
  ('NUCLEO_EVAL_LISTA_INVALIDA','PROPUESTA','La suma recibió algo que no es una lista','Entregar el dato como lista en la entrada de la prueba'),
  ('NUCLEO_EVAL_NO_NUMERICO','PROPUESTA','Un cálculo recibió un valor que no es número (o un elemento de la lista sin el campo)','Corregir el dato o el campo que se suma'),
  ('NUCLEO_EVAL_DECIMALES_INVALIDOS','PROPUESTA','Los decimales del redondeo no son un entero entre 0 y 10','Corregir el parámetro de decimales');
UPDATE saly.nucleo_errores SET accion = 'Usar y, o, no, =, !=, >, >=, <, <=, +, -, *, /, max, min, suma o redondeo' WHERE codigo = 'NUCLEO_EVAL_OPERADOR_INVALIDO';
REVOKE ALL ON FUNCTION saly.nucleo_autotest_calculo_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION saly.nucleo_autotest_calculo_v1() TO service_role;
  END IF;
END $g$;
