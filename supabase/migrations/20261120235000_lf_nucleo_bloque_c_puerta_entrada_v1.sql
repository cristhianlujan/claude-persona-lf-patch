-- Núcleo de reglas, bloque C (F2 completo, instancia LF): puerta de entrada única.
-- nucleo_regla_proponer_v1(propuesta jsonb, aplicar boolean) evalúa 19 controles y, si no hay bloqueantes,
-- crea la regla como CANDIDATA (versión 1 + aplicación + dependencias). Con aplicar = false solo evalúa.
-- Cada control devuelve si pasó, si bloquea y un mensaje para corregir. Los avisos no bloquean.
-- Datos de soporte: registro de autoridades, contrato global + extensiones por familia, listas en lf_global_config.
-- Autopruebas al final: 18 escenarios; se deshacen solos y, si uno falla, se revierte toda la migración.
BEGIN;

-- Registro de autoridades (control 16)
CREATE TABLE lf_ops.nucleo_autoridades (
  codigo text PRIMARY KEY,
  tipo text NOT NULL,
  descripcion text NOT NULL,
  estado text NOT NULL DEFAULT 'VIGENTE',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_autoridades_tipo_valido CHECK (tipo IN ('DECISION_DUENO','NORMA','POLITICA','ANALISIS')),
  CONSTRAINT nucleo_autoridades_estado_valido CHECK (estado IN ('VIGENTE','REEMPLAZADA','RETIRADA')),
  CONSTRAINT nucleo_autoridades_descripcion_minima CHECK (length(btrim(descripcion)) >= 10)
);
INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion) VALUES
  ('Q01','DECISION_DUENO','MFA de LF: correo principal, SMS de contingencia, cuándo pedirlo en Login B2B'),
  ('Q02','DECISION_DUENO','Registro contable de pagos (ledger): tabla padre payment e hija payment_detail solo con insert'),
  ('Q03','DECISION_DUENO','Niubiz como proveedor de todo el recaudo (tarjeta y Yape)'),
  ('Q04','DECISION_DUENO','Estados de cuota, vencimiento sin gracia, reconciliación de medianoche y cancelación'),
  ('Q05','DECISION_DUENO','Tabla de pricing con histórico, vigencias y autoridad de cambios'),
  ('Q08','DECISION_DUENO','Textos legales y consentimientos: bloquean producción, no el desarrollo'),
  ('Q09','DECISION_DUENO','Contenido publicable del Home (aliados, prensa, personas, visuales)'),
  ('Q10','DECISION_DUENO','Envío de la Carta de No Adeudo según el modelo del aliado'),
  ('Q11','DECISION_DUENO','Recuperación de acceso del cliente sin el celular anterior'),
  ('Q12','DECISION_DUENO','Umbrales de señales de riesgo en base de datos con pantalla de mantenimiento'),
  ('D1','DECISION_DUENO','Núcleo de reglas: un motor con una instancia por producto (LF y SALY)'),
  ('D2','DECISION_DUENO','Núcleo de reglas: familias nuevas de negocio y de backend');
COMMENT ON TABLE lf_ops.nucleo_autoridades IS 'Autoridades que respaldan reglas (control 16 de la puerta).';

-- Contrato: campos obligatorios globales y extensiones por familia (control 2)
CREATE TABLE lf_ops.nucleo_contrato_campos (
  familia text REFERENCES lf_ops.nucleo_familias(codigo),
  campo text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_contrato_campo_formato CHECK (campo ~ '^[a-z][a-z0-9_]{1,60}$')
);
CREATE UNIQUE INDEX nucleo_contrato_campos_unico ON lf_ops.nucleo_contrato_campos (COALESCE(familia, '*'), campo);
INSERT INTO lf_ops.nucleo_contrato_campos (familia, campo)
SELECT NULL, c FROM unnest(ARRAY['codigo','clave','titulo','descripcion','familia','naturaleza','autoridad',
  'dueno','alcance','modo','clase','condicion','efecto','pruebas']) c;
COMMENT ON TABLE lf_ops.nucleo_contrato_campos IS 'Contrato de la regla: familia NULL = global; con familia = extensión de esa familia.';

-- Listas usadas por los controles (en la configuración global, no en el código)
INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','LITERALES_PERMITIDOS','[0, true, false]','JSON','REAL','Literales que una condición puede usar sin parámetro (control 5 de la puerta del núcleo).'),
 ('NUCLEO','EFECTOS_CONDUCTA','["BLOQUEAR","RECHAZAR","AVISAR","EXIGIR","PERMITIR","OCULTAR","MOSTRAR"]','JSON','REAL','Efectos válidos para reglas de conducta (control 18).'),
 ('NUCLEO','EFECTOS_DEFINICION','["CALCULAR","CLASIFICAR","DEFINIR","FORMATEAR"]','JSON','REAL','Efectos válidos para reglas de definición (control 18).');

-- Lectura de un parámetro vigente: 'SCOPE.CLAVE' (la clave puede contener puntos)
CREATE OR REPLACE FUNCTION lf_ops.nucleo_param_valor_v1(p_ref text)
RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $$
  SELECT g.config_value FROM public.lf_global_config g
   WHERE g.scope = split_part(p_ref, '.', 1)
     AND g.config_key = substr(p_ref, length(split_part(p_ref, '.', 1)) + 2)
     AND g.valid_from <= now()
   ORDER BY g.valid_from DESC LIMIT 1
$$;

-- Evaluador de condiciones: hojas {hecho}, {param}, {lit}; operadores de comparación, y, o, no.
CREATE OR REPLACE FUNCTION lf_ops.nucleo_eval_v1(c jsonb, e jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = pg_catalog, lf_ops AS $$
DECLARE a jsonb; b jsonb; v jsonb;
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
  IF c->>'op' IS NULL OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=') THEN RAISE EXCEPTION 'NUCLEO_EVAL_OPERADOR_INVALIDO: %', c->>'op'; END IF;
  IF c->>'op' = 'no' THEN RETURN to_jsonb(NOT (lf_ops.nucleo_eval_v1(c->'izq', e))::text::boolean); END IF;
  a := lf_ops.nucleo_eval_v1(c->'izq', e);
  b := lf_ops.nucleo_eval_v1(c->'der', e);
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
END $$;

-- Forma de la condición: cada nodo es una hoja ({hecho}|{param}|{lit}) o un operador conocido con sus operandos.
-- Devuelve NULL si es válida o el primer problema encontrado.
CREATE OR REPLACE FUNCTION lf_ops.nucleo_condicion_problema_v1(c jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
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
  IF NOT c ? 'op' OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=') THEN RETURN 'operador desconocido o ausente: ' || c::text; END IF;
  IF c->>'op' = 'no' THEN RETURN lf_ops.nucleo_condicion_problema_v1(c->'izq'); END IF;
  RETURN COALESCE(lf_ops.nucleo_condicion_problema_v1(c->'izq'), lf_ops.nucleo_condicion_problema_v1(c->'der'));
END $$;

-- Recorre la condición y devuelve sus nodos
CREATE OR REPLACE FUNCTION lf_ops.nucleo_nodos_condicion_v1(c jsonb)
RETURNS SETOF jsonb LANGUAGE sql IMMUTABLE AS $$
  WITH RECURSIVE t(n) AS (
    SELECT c WHERE jsonb_typeof(c) = 'object'
    UNION ALL
    SELECT x FROM t, LATERAL (VALUES (t.n->'izq'), (t.n->'der')) y(x)
     WHERE x IS NOT NULL AND jsonb_typeof(x) = 'object')
  SELECT n FROM t
$$;

-- Puerta de entrada
CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  ctl jsonb := '[]'::jsonb;
  v_fam record; v_falta text; v_txt text; v_n integer; v_ok boolean;
  v_clase text := upper(p->>'clase'); v_nat text := upper(p->>'naturaleza'); v_alc text := p->>'alcance';
  v_ambito text; v_nivel text; v_clasif text := 'NUEVA'; v_prueba jsonb; v_res jsonb; v_bloq integer;
  v_lits jsonb; v_efectos jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_proponer:' || coalesce(p->>'clave', ''), 0));

  -- 0 código libre
  v_ok := p->>'codigo' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nucleo_reglas WHERE codigo = p->>'codigo');
  ctl := ctl || jsonb_build_object('n',0,'control','Código libre','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'El código ya existe o falta: use otro código o proponga una versión nueva de la regla existente.' END);

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
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=.' END);

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
    WHEN 'BACKEND' THEN v_nivel = 'GLOBAL' OR v_ambito = 'BACKEND'
    WHEN 'PANTALLA' THEN v_ambito IN ('B2B','CLIENTE')
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
   WHERE r.clave = p->>'clave' AND r.familia = p->>'familia' AND r.estado NOT IN ('RETIRADA')
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

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc;
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto','ok',false,'bloqueante',false,
      'detalle','Ya existe idéntica en otros nodos (' || v_txt || '): considere registrarla una vez en el nodo común y retirar las copias.');
  END IF;

  -- 12 hacia abajo: reglas de la misma clave en los descendientes (aviso)
  WITH RECURSIVE dn(c) AS (SELECT v_alc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
   WHERE r.clave = p->>'clave' AND a.nodo IN (SELECT c FROM dn) AND a.nodo <> v_alc;
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',12,'control','Impacto hacia abajo','ok',false,'bloqueante',false,
      'detalle', CASE WHEN upper(p->>'modo') = 'FIJA' THEN 'Es FIJA y hay reglas de la misma clave abajo (deben resolverse antes de promover): '
                      ELSE 'Hay reglas de la misma clave abajo (quedan como especialización): ' END || v_txt);
  END IF;

  SELECT count(*) INTO v_bloq FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;

  IF v_bloq = 0 AND p_aplicar THEN
    INSERT INTO nucleo_reglas (codigo, clave, familia, naturaleza, estado)
    VALUES (p->>'codigo', p->>'clave', p->>'familia', v_nat, 'CANDIDATA');
    INSERT INTO nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, publicada_desde, exigible_desde)
    VALUES (p->>'codigo', p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad',
            now(), COALESCE((p->>'exigible_desde')::timestamptz, now()));
    INSERT INTO nucleo_aplicaciones (regla, nodo, modo) VALUES (p->>'codigo', v_alc, upper(p->>'modo'));
    INSERT INTO nucleo_relaciones (origen, destino, tipo)
    SELECT p->>'codigo', d, 'DEPENDE' FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d;
  END IF;

  RETURN jsonb_build_object(
    'resultado', CASE WHEN v_bloq > 0 THEN 'RECHAZADA' WHEN p_aplicar THEN 'CANDIDATA' ELSE 'EVALUADA_SIN_ESCRIBIR' END,
    'clasificacion', v_clasif, 'bloqueantes', v_bloq,
    'avisos', (SELECT count(*) FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND NOT (x->>'bloqueante')::boolean),
    'controles', ctl);
END $$;
COMMENT ON FUNCTION lf_ops.nucleo_regla_proponer_v1(jsonb, boolean) IS
  'Puerta de entrada única del núcleo: 19 controles; crea la regla como CANDIDATA si no hay bloqueantes. aplicar=false solo evalúa.';

-- Acceso
REVOKE ALL ON lf_ops.nucleo_autoridades, lf_ops.nucleo_contrato_campos FROM PUBLIC;
REVOKE ALL ON lf_ops.nucleo_autoridades, lf_ops.nucleo_contrato_campos FROM anon, authenticated;
ALTER TABLE lf_ops.nucleo_autoridades ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_contrato_campos ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_autoridades AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_contrato_campos AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.nucleo_regla_proponer_v1(jsonb, boolean), lf_ops.nucleo_eval_v1(jsonb, jsonb),
  lf_ops.nucleo_param_valor_v1(text), lf_ops.nucleo_nodos_condicion_v1(jsonb), lf_ops.nucleo_condicion_problema_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION lf_ops.nucleo_regla_proponer_v1(jsonb, boolean), lf_ops.nucleo_eval_v1(jsonb, jsonb),
  lf_ops.nucleo_param_valor_v1(text), lf_ops.nucleo_nodos_condicion_v1(jsonb), lf_ops.nucleo_condicion_problema_v1(jsonb) FROM anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_regla_proponer_v1(jsonb, boolean), lf_ops.nucleo_eval_v1(jsonb, jsonb),
      lf_ops.nucleo_param_valor_v1(text), lf_ops.nucleo_nodos_condicion_v1(jsonb), lf_ops.nucleo_condicion_problema_v1(jsonb) TO service_role; END IF;
END $g$;

-- Autopruebas (se deshacen solas; un fallo revierte toda la migración)
DO $autotest$
DECLARE
  base jsonb; r jsonb; n integer;
  hoja text := (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'PANTALLA' AND padre IN
                 (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'MODULO' AND padre = 'B2B') ORDER BY codigo LIMIT 1);
BEGIN
  BEGIN
    base := jsonb_build_object(
      'codigo','ZZT-OTP-1','clave','zzt_otp_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de envíos en la ventana vigente',
      'familia','RATE_LIMIT','naturaleza','CONDUCTA','autoridad','Q01','dueno','LF_GOVERNANCE',
      'alcance','B2B','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',-1)),'esperado',false)));

    -- C1 regla correcta: CANDIDATA y escrita
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 correcta (%)', r; END IF;
    IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-OTP-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 sin versión'; END IF;
    -- C2 código repetido
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'RECHAZADA' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C2 código repetido'; END IF;
    -- C3 duplicado en el mismo alcance
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"codigo":"ZZT-OTP-2"}');
    IF r->>'clasificacion' NOT LIKE 'DUPLICADO_DE ZZT-OTP-1' OR r->>'resultado' <> 'RECHAZADA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C3 duplicado (%)', r->>'clasificacion'; END IF;
    -- C4 especialización en una pantalla
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-3','alcance',hoja), false);
    IF r->>'clasificacion' <> 'ESPECIALIZA ZZT-OTP-1' OR r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C4 especialización (%)', r->>'clasificacion'; END IF;
    -- C5 evaluar sin escribir no escribe; la copia idéntica en otro nodo genera aviso 11
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-OTP-3') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 escribió en modo evaluación'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '11' AND NOT (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 sin aviso de alcance (11)'; END IF;
    -- C5b proponer arriba avisa de la regla de la misma clave abajo (12)
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-5','alcance','GLOBAL','clase','TRANSVERSAL'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '12' AND x->>'detalle' LIKE '%ZZT-OTP-1%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5b sin aviso hacia abajo (12)'; END IF;
    -- C5c familia retirada
    UPDATE lf_ops.nucleo_familias SET estado = 'RETIRADA' WHERE codigo = 'RATE_LIMIT';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X5C','clave','zzt_x5c'), false);
    UPDATE lf_ops.nucleo_familias SET estado = 'ACTIVA' WHERE codigo = 'RATE_LIMIT';
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '1' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5c familia retirada aceptada'; END IF;
    -- C6 dato fijo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X6','clave','zzt_x6',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('lit',3))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '5' AND (x->>'ok')::boolean = false AND (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C6 dato fijo no detectado'; END IF;
    -- C7 hecho fuera del vocabulario
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X7','clave','zzt_x7',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','sueldo'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '4' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C7 vocabulario'; END IF;
    -- C8 parámetro inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X8','clave','zzt_x8',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.NO_EXISTE'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '6' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C8 parámetro'; END IF;
    -- C9 pruebas que no pasan
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X9','clave','zzt_x9','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),'esperado',false),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',-1)),'esperado',false))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C9 pruebas que fallan'; END IF;
    -- C10 pruebas con valor fijo y pruebas insuficientes
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X10','clave','zzt_x10','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',9),'esperado',true))), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('7','8') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C10 pruebas fijas/insuficientes'; END IF;
    -- C11 autoridad inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11','clave','zzt_x11','autoridad','Q99'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11 autoridad'; END IF;
    -- C11b autoridad retirada
    INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT','POLITICA','Autoridad de prueba retirada','RETIRADA');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11B','clave','zzt_x11b','autoridad','ZZT-AUT'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11b autoridad retirada aceptada'; END IF;
    -- C11c parámetro con valor de muestra: aviso, no bloqueo
    INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','PARAM_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11C','clave','zzt_x11c',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.PARAM_MUESTRA','mas',-1)),'esperado',false))), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '14' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11c valor de muestra (%)', r->>'resultado'; END IF;
    -- C12 unidad incompatible (parámetro registrado con otro dato)
    INSERT INTO lf_ops.nucleo_parametros (scope, config_key, hecho, dueno) VALUES ('AUTH','SESSION_IDLE_TIMEOUT_SECONDS','inactividad_sesion','LF_GOVERNANCE');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X12','clave','zzt_x12',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '13' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C12 unidades'; END IF;
    -- C13 efecto incoherente con la naturaleza
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X13','clave','zzt_x13','naturaleza','DEFINICION'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '18' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C13 efecto'; END IF;
    -- C14 clase BACKEND en un alcance de pantalla
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14','clave','zzt_x14','clase','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14 clase'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14B','clave','zzt_x14b','clase','BACKEND','alcance','BACKEND'), false);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14b backend válido rechazado'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14C','clave','zzt_x14c','clase','PANTALLA','alcance','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14c pantalla en backend aceptada'; END IF;
    -- C15 conflicto con FIJA superior
    UPDATE lf_ops.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-OTP-1';
    UPDATE lf_ops.nucleo_aplicaciones SET modo = 'FIJA' WHERE regla = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-4','alcance',hoja), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '9' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C15 fija superior'; END IF;
    -- C16 dependencia no vigente: aviso, no bloqueo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    UPDATE lf_ops.nucleo_reglas SET estado = 'CANDIDATA' WHERE codigo = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR (r->>'avisos')::int < 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C16 dependencia candidata (%)', r->>'resultado'; END IF;
    -- C17 extensión de contrato por familia
    INSERT INTO lf_ops.nucleo_contrato_campos (familia, campo) VALUES ('RATE_LIMIT','riesgo_operativo');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X17','clave','zzt_x17'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '2' AND (x->>'ok')::boolean = false AND x->>'detalle' LIKE '%riesgo_operativo%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C17 extensión de familia'; END IF;
    -- C18 familia inexistente y alcance inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X18','clave','zzt_x18','familia','NO_EXISTE','alcance','NO-EXISTE'), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('1','3') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C18 familia/alcance'; END IF;

    -- C19 condición como texto: se rechaza por forma y no se cuelga el evaluador
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19','clave','zzt_x19','condicion',to_jsonb('intentos >= 3'::text)), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND x->>'detalle' LIKE '%NUCLEO_EVAL_NODO_INVALIDO%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19 condición texto'; END IF;
    -- C19b condición como lista
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19B','clave','zzt_x19b','condicion','["hecho"]'::jsonb), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19b condición lista'; END IF;
    -- C20 operador desconocido
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X20','clave','zzt_x20',
      'condicion', jsonb_build_object('op','~','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C20 operador desconocido'; END IF;
    -- C21 nodo ambiguo (operador y hoja a la vez)
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X21','clave','zzt_x21',
      'condicion', jsonb_build_object('op','>=','lit',3,'izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C21 hoja ambigua'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'NUCLEO_PUERTA_AUTOTEST: 26/26 escenarios OK (datos de prueba deshechos)';
END $autotest$;
COMMIT;
