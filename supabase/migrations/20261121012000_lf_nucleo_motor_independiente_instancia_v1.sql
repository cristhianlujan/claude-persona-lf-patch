-- Núcleo de reglas, bloque F1: motor independiente de la instancia (paso previo a la instancia SALY, decisión D1).
-- 1) El control 19 (clase coherente con el alcance) lee los ámbitos de pantalla y de backend de la configuración
--    de la instancia (NUCLEO.AMBITOS_PANTALLA / NUCLEO.AMBITOS_BACKEND) en lugar de tener 'B2B','CLIENTE','BACKEND' escritos.
--    Para LF los valores son los mismos: el comportamiento no cambia.
-- 2) Las autopruebas crean sus propios datos (familias, hechos, parámetros, autoridad y nodos ZZT) dentro de la
--    subtransacción, así el mismo código de pruebas corre en cualquier instancia (LF y SALY).
BEGIN;

INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','AMBITOS_PANTALLA','["B2B","CLIENTE"]','JSON','REAL','Ámbitos del árbol del núcleo cuyas reglas de clase PANTALLA son válidas (control 19).'),
 ('NUCLEO','AMBITOS_BACKEND','["BACKEND"]','JSON','REAL','Ámbitos del árbol del núcleo donde valen las reglas de clase BACKEND, además de la raíz (control 19).');

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
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=.' END);

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

-- Datos propios de las autopruebas (se crean dentro de cada prueba y se deshacen con ella)
CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_datos_v1()
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
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
END $$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_puerta_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$

DECLARE
  base jsonb; r jsonb; n integer;
  hoja text := 'ZZT-MOD-1';
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    base := jsonb_build_object(
      'codigo','ZZT-OTP-1','clave','zzt_otp_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de envíos en la ventana vigente',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));

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
    UPDATE lf_ops.nucleo_familias SET estado = 'RETIRADA' WHERE codigo = 'ZZT_FAM';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X5C','clave','zzt_x5c'), false);
    UPDATE lf_ops.nucleo_familias SET estado = 'ACTIVA' WHERE codigo = 'ZZT_FAM';
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '1' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5c familia retirada aceptada'; END IF;
    -- C6 dato fijo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X6','clave','zzt_x6',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('lit',3))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '5' AND (x->>'ok')::boolean = false AND (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C6 dato fijo no detectado'; END IF;
    -- C7 hecho fuera del vocabulario
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X7','clave','zzt_x7',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','sueldo'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '4' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C7 vocabulario'; END IF;
    -- C8 parámetro inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X8','clave','zzt_x8',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.NO_EXISTE'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '6' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C8 parámetro'; END IF;
    -- C9 pruebas que no pasan
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X9','clave','zzt_x9','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',false),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C9 pruebas que fallan'; END IF;
    -- C10 pruebas con valor fijo y pruebas insuficientes
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X10','clave','zzt_x10','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',9),'esperado',true))), false);
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
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.PARAM_MUESTRA','mas',-1)),'esperado',false))), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '14' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11c valor de muestra (%)', r->>'resultado'; END IF;
    -- C12 unidad incompatible (parámetro registrado con otro dato)
    INSERT INTO lf_ops.nucleo_parametros (scope, config_key, hecho, dueno) VALUES ('ZZT','INACTIVIDAD_MAX','zzt_inactividad','LF_GOVERNANCE');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X12','clave','zzt_x12',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '13' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C12 unidades'; END IF;
    -- C13 efecto incoherente con la naturaleza
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X13','clave','zzt_x13','naturaleza','DEFINICION'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '18' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C13 efecto'; END IF;
    -- C14 clase BACKEND en un alcance de pantalla
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14','clave','zzt_x14','clase','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14 clase'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14B','clave','zzt_x14b','clase','BACKEND','alcance','ZZT-BACK'), false);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14b backend válido rechazado'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14C','clave','zzt_x14c','clase','PANTALLA','alcance','ZZT-BACK'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14c pantalla en backend aceptada'; END IF;
    -- C15 conflicto con FIJA superior
    UPDATE lf_ops.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-OTP-1';
    PERFORM set_config('lf.nucleo_publicando', 'ZZT-OTP-1:1', true);
    UPDATE lf_ops.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-OTP-1' AND version = 1;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    UPDATE lf_ops.nucleo_aplicaciones SET modo = 'FIJA' WHERE regla = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-4','alcance',hoja), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '9' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C15 fija superior'; END IF;
    -- C16 dependencia no vigente: aviso, no bloqueo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    UPDATE lf_ops.nucleo_reglas SET estado = 'CANDIDATA' WHERE codigo = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR (r->>'avisos')::int < 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C16 dependencia candidata (%)', r->>'resultado'; END IF;
    -- C17 extensión de contrato por familia
    INSERT INTO lf_ops.nucleo_contrato_campos (familia, campo) VALUES ('ZZT_FAM','riesgo_operativo');
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
      'condicion', jsonb_build_object('op','~','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C20 operador desconocido'; END IF;
    -- C21 nodo ambiguo (operador y hoja a la vez)
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X21','clave','zzt_x21',
      'condicion', jsonb_build_object('op','>=','lit',3,'izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C21 hoja ambigua'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PUERTA 26/26';

END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_evaluacion_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  base jsonb; r jsonb; e jsonb; h text; ok boolean; pts jsonb; pts_bajo jsonb; jui jsonb;
  hoja text := 'ZZT-MOD-1';
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    SELECT jsonb_object_agg(codigo, jsonb_build_object('puntaje', 1)) INTO pts FROM lf_ops.nucleo_rubrica WHERE estado = 'ACTIVO';
    pts_bajo := pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.5,'observacion','El título no dice qué se bloquea'),
                                          'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.7,'observacion','No dice qué ve el usuario al bloquearse'),
                                          'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Parecida a otra regla de reintentos'));
    jui := jsonb_build_object('veredicto','PASS','juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,
                              'llamadas_modelo',0,'evidencia_ref','autotest bloque D');
    base := jsonb_build_object(
      'codigo','ZZT-EV-1','clave','zzt_ev_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de reenvíos configurado',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));

    -- E1 sin juicio: BLOQUEADA, pruebas guardadas con su casuística
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 propuesta (%)', r; END IF;
    IF (SELECT string_agg(casuistica, ',' ORDER BY n) FROM lf_ops.nucleo_regla_pruebas WHERE regla = 'ZZT-EV-1') IS DISTINCT FROM 'EN_EL_LIMITE,BAJO_EL_LIMITE,SOBRE_EL_LIMITE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 pruebas no guardadas'; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-1');
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"JUICIO"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 sin juicio (%)', e; END IF;
    h := e->>'hash_paquete';

    -- E2 juicio con otro hash: rechazado
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',repeat('a',64),'puntajes',pts));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_HASH_DISTINTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E2 hash distinto aceptado'; END IF;
    -- E3 rúbrica incompleta y puntaje bajo sin observación
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts - 'COH_EFECTO'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%COH_EFECTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3 rúbrica incompleta aceptada'; END IF;
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts || '{"CAL_ALCANCE":{"puntaje":0.9}}'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%CAL_ALCANCE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3b puntaje bajo sin observación aceptado'; END IF;
    -- E4 PASS con dimensión bajo el umbral: incoherente
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts_bajo));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_VEREDICTO_INCOHERENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E4 PASS incoherente aceptado'; END IF;
    -- E5 procedencia: INDEPENDIENTE no puede ser el productor ni tener cero llamadas
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts,'modo','INDEPENDIENTE'));
    EXCEPTION WHEN check_violation THEN ok := SQLERRM LIKE '%procedencia_honesta%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E5 independencia sin prueba aceptada'; END IF;

    -- E6 juicio completo: AUTO con nota 100 y pasa a VIGENTE
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR (e->>'nota')::int IS DISTINCT FROM 100
       OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-EV-1') IS DISTINCT FROM 'VIGENTE'
       OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-EV-1' AND version = 1) IS DISTINCT FROM 'PUBLICADA'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 auto (%)', e; END IF;
    IF (SELECT count(*) FROM lf_ops.nucleo_evaluaciones WHERE regla = 'ZZT-EV-1') <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 historial'; END IF;

    -- E7 poca profundidad y calidad media: MANUAL con motivos; sin decisión queda pendiente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-2','clave','zzt_ev_dos','pruebas', (base->'pruebas') - 2));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-2', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-2','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2');
    IF e->>'resultado' IS DISTINCT FROM 'PENDIENTE_DECISION' OR e->>'decision' <> 'MANUAL'
       OR NOT (e->'motivos' @> '[{"dimension":"PROFUNDIDAD"}]') OR position('SOBRE_EL_LIMITE' IN e::text) = 0
       OR NOT (e->'motivos' @> '[{"dimension":"NOTA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E7 manual (%)', e; END IF;
    -- E8 el dueño rechaza: queda en la cola de remediación; luego aprueba: VIGENTE y sale de la cola
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"RECHAZAR","autoridad":"ZZT-Q","motivo":"Falta la prueba sobre el límite"}');
    IF e->>'resultado' IS DISTINCT FROM 'RECHAZADA_POR_DUENO' OR NOT EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2' AND origen = 'DECISION_DUENO')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 rechazo (%)', e; END IF;
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"APROBAR","autoridad":"ZZT-Q","motivo":"Aceptada con la cobertura actual"}');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_MANUAL' OR EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 aprobación (%)', e; END IF;
    -- E9 autoridad no vigente en la decisión
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-3','clave','zzt_ev_tres','pruebas', (base->'pruebas') - 2));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-3','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT-D','POLITICA','Autoridad de prueba retirada','RETIRADA');
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_promover_v1('ZZT-EV-3', '{"decision":"APROBAR","autoridad":"ZZT-AUT-D","motivo":"Aprobación con autoridad retirada"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E9 autoridad retirada aceptada'; END IF;
    -- E10 umbral cambiado solo en configuración: la misma regla pasa a AUTO
    UPDATE public.lf_global_config SET config_value = '80' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10 umbral por configuración (%)', e; END IF;
    UPDATE public.lf_global_config SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    -- E10b nota bajo el umbral de revisión (cambiado en configuración): DEVUELTA con motivo
    UPDATE public.lf_global_config SET config_value = '90' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE public.lf_global_config SET config_value = '84' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR position('bajo el umbral de revisión 84' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10b umbral de revisión (%)', e; END IF;
    UPDATE public.lf_global_config SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE public.lf_global_config SET config_value = '60' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    -- E11 decisión humana sobre algo que no es MANUAL: rechazada
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-4','clave','zzt_ev_cuatro'));
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_promover_v1('ZZT-EV-4', '{"decision":"APROBAR","autoridad":"ZZT-Q","motivo":"Intento de saltar el juicio"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_NO_APLICA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E11 decisión sobre BLOQUEADA aceptada'; END IF;
    -- E12 juicio atado al hash: una prueba agregada después invalida el juicio
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    INSERT INTO lf_ops.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-4', 1, 9, 'EN_EL_LIMITE', jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')), 'true');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR position('rejuzgarse' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E12 hash (%)', e; END IF;
    -- E13 juez devuelve: DEVUELTA y en la cola con sus observaciones
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','veredicto','DEVOLVER','puntajes',pts_bajo));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-4');
    IF e->>'resultado' IS DISTINCT FROM 'DEVUELTA' OR (e->'componentes'->>'juicio')::boolean IS NOT FALSE
       OR NOT EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-4' AND motivos::text LIKE '%qué ve el usuario%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E13 devuelta (%)', e; END IF;
    -- E14 pruebas relativas: cambiar el parámetro no rompe las pruebas
    UPDATE public.lf_global_config SET config_value = '7' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->'motivos' @> '[{"dimension":"PRUEBAS"}]' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E14 pruebas rotas por cambio de parámetro'; END IF;
    UPDATE public.lf_global_config SET config_value = '3' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS';
    -- E15 prueba que falla con los parámetros vigentes: DEVUELTA
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-5','clave','zzt_ev_cinco'));
    INSERT INTO lf_ops.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-5', 1, 9, NULL, jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')), 'false');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-5','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR NOT (e->'motivos' @> '[{"dimension":"PRUEBAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E15 prueba fallida (%)', e; END IF;
    -- E16 parámetro con valor de muestra: BLOQUEADA
    INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','EV_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-6','clave','zzt_ev_seis',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.EV_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.EV_MUESTRA')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.EV_MUESTRA','mas',-1)),'esperado',false))));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-6','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"VALOR_REAL"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E16 valor de muestra (%)', e; END IF;
    -- E17 dependencia no vigente: BLOQUEADA; al quedar vigente, deja de bloquear
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-7','clave','zzt_ev_siete','depende','["ZZT-EV-5"]'::jsonb));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-7','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"DEPENDENCIAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17 dependencia (%)', e; END IF;
    UPDATE lf_ops.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-EV-5';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17b dependencia vigente (%)', e; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', true);
    IF EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-7') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17c regla no devuelta en la cola'; END IF;
    -- E18 familia que siempre requiere decisión humana: MANUAL aunque la nota sea 100
    r := lf_ops.nucleo_regla_proponer_v1(jsonb_build_object(
      'codigo','ZZT-EV-8','clave','zzt_ev_sesion','titulo','Cierre de sesión por inactividad',
      'descripcion','La sesión se cierra cuando la inactividad alcanza el tiempo máximo configurado',
      'familia','ZZT_FAM_MANUAL','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','TRANSVERSAL','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_inactividad'),'der',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX','mas',1)),'esperado',true))));
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 propuesta (%)', r; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-8','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    IF e->>'decision' IS DISTINCT FROM 'MANUAL' OR (e->>'nota')::int <> 100 OR NOT (e->'motivos' @> '[{"dimension":"POLITICA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 siempre manual (%)', e; END IF;
    -- E19 regla FIJA con la misma clave debajo: BLOQUEADA
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-9','clave','zzt_ev_fija','alcance',hoja));
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-10','clave','zzt_ev_fija','modo','FIJA'));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-10','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"FIJA"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E19 fija con especializaciones (%)', e; END IF;
    -- E20 casuística desconocida en la propuesta
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-11','clave','zzt_ev_once','pruebas',
      jsonb_set(base->'pruebas', '{0,casuistica}', '"NO_EXISTE"')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Casuísticas conocidas' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E20 casuística desconocida'; END IF;
    -- E21 historial y pruebas no se modifican
    ok := false;
    BEGIN UPDATE lf_ops.nucleo_regla_pruebas SET esperado = 'false' WHERE regla = 'ZZT-EV-1' AND n = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_PRUEBA_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21 prueba modificable'; END IF;
    ok := false;
    BEGIN UPDATE lf_ops.nucleo_juicios SET veredicto = 'PASS' WHERE regla = 'ZZT-EV-4';
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_HISTORIAL_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21b juicio modificable'; END IF;
    -- E22 pesos que no suman 100: falla cerrado
    UPDATE public.lf_global_config SET config_value = '15' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'PESO_FRESCURA';
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_EVAL_PESOS_INVALIDOS%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E22 pesos inválidos aceptados'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'EVALUACION 23/23';
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_cambio_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  base jsonb; r jsonb; e jsonb; ok boolean; pts jsonb; jui jsonb; n integer; t text;
  hoja text := 'ZZT-MOD-1';
  hoja2 text := 'ZZT-MOD-2';
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    SELECT jsonb_object_agg(codigo, jsonb_build_object('puntaje', 1)) INTO pts FROM lf_ops.nucleo_rubrica WHERE estado = 'ACTIVO';
    jui := jsonb_build_object('veredicto','PASS','juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,
                              'llamadas_modelo',0,'evidencia_ref','autotest bloque E','puntajes',pts);
    base := jsonb_build_object(
      'codigo','ZZT-CB-1','clave','zzt_cb_reenvios','titulo','Bloqueo por reenvíos de OTP',
      'descripcion','Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos configurado',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','plazo_dias',10,
      'origen', jsonb_build_object('tipo','IG','ref','EXEC-AUTOTEST-E','solicitante','autotest'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));

    -- K1 sin origen, origen inválido e impacto NINGUNO en una regla nueva: rechazados por el control específico
    r := lf_ops.nucleo_regla_proponer_v1(base - 'origen', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Campos obligatorios' AND x->>'detalle' LIKE '%origen%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1 sin origen (%)', r; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"origen":{"tipo":"OTRO","ref":"EXEC-VALIDA","solicitante":"autotest"}}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Origen del cambio' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1b tipo de origen inválido'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"origen":{"tipo":"IG","ref":"x","solicitante":"autotest"}}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Origen del cambio' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1b2 referencia de origen vacía'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"impacto":"NINGUNO"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Impacto declarado' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1c impacto NINGUNO en regla nueva'; END IF;

    -- K2 alta: versión 1 CANDIDATA sin fechas, con origen guardado; el resolvedor no la ve
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2 alta (%)', r; END IF;
    IF (SELECT estado || '|' || COALESCE(publicada_desde::text,'-') || '|' || (origen->>'ref') || '|' || impacto FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1)
       IS DISTINCT FROM 'CANDIDATA|-|EXEC-AUTOTEST-E|IMPLEMENTAR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2 versión guardada'; END IF;
    -- K2b una versión no puede nacer publicada
    ok := false;
    BEGIN INSERT INTO lf_ops.nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, estado, publicada_desde, exigible_desde)
          SELECT regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, 'PUBLICADA', now(), now() FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_ALTA_INVALIDA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2b versión nacida publicada'; END IF;
    -- K3 publicar sin promoción: rechazado; cambio de estado directo: rechazado
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_version_publicar_v1('ZZT-CB-1', 1); EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_PUBLICAR_SIN_PROMOCION%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K3 publicar sin promoción'; END IF;
    ok := false;
    BEGIN UPDATE lf_ops.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-CB-1';
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_TRANSICION_FUERA_DE_RUTA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K3b publicación directa'; END IF;
    -- K4 juicio y promoción: PUBLICADA, regla VIGENTE, exigible a los 10 días pedidos; el resolvedor la ve en una hoja
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-CB-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO'
       OR (SELECT estado || '|' || (exigible_desde - publicada_desde)::text FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1) IS DISTINCT FROM 'PUBLICADA|10 days'
       OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K4 promoción (%)', e; END IF;
    IF (SELECT version FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K4 resolvedor v1'; END IF;

    -- K5 cambio sin cambios, cambio de identidad y cambio de alcance: rechazados
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'detalle' LIKE 'SIN_CAMBIOS%') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5 sin cambios (%)', r; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","clave":"zzt_cb_otra","descripcion":"Bloquea el reenvío de OTP con otra clave distinta a la original"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5b cambio de identidad'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('tipo','CAMBIO','alcance',hoja,'descripcion','Bloquea el reenvío de OTP solo en esta pantalla concreta del flujo'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5c cambio de alcance'; END IF;
    -- K6 cambio válido: v2 CANDIDATA; la regla sigue VIGENTE con v1 en efecto
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; aplica a SMS y correo","origen":{"tipo":"CHAT","ref":"chat-autotest-e","solicitante":"autotest"}}');
    IF r->>'resultado' <> 'CANDIDATA' OR (r->>'version')::int IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 cambio (%)', r; END IF;
    IF (SELECT version FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 1
       OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE'
       OR (SELECT count(*) FROM lf_ops.nucleo_regla_pruebas WHERE regla = 'ZZT-CB-1' AND version = 2) <> 3
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 la candidata entró en efecto o sin pruebas'; END IF;
    -- K7 segundo cambio con una candidata abierta: rechazado
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Otro cambio mientras la versión dos sigue abierta en revisión"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false AND x->>'detalle' LIKE '%candidata%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K7 dos candidatas'; END IF;

    -- K8 implementación de v1 en una hoja; v2 publicada: la hoja queda EN_PLAZO y pasa a DESFASADO tras el plazo
    INSERT INTO lf_ops.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 1, hoja, 'PR autotest v1');
    ok := false;
    BEGIN INSERT INTO lf_ops.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 2, hoja, 'PR autotest v2 antes de tiempo');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_IMPLEMENTACION_VERSION_NO_PUBLICADA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 implementación de candidata'; END IF;
    IF (SELECT estado FROM lf_ops.nucleo_cola_trabajo_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 al día con v1'; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-CB-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR (e->>'version')::int <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 promover v2 (%)', e; END IF;
    IF (SELECT string_agg(version::text, ',') FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM '2'
       OR (SELECT vigente_hasta IS NOT NULL FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1) IS NOT TRUE
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 v2 en efecto y v1 cerrada'; END IF;
    SELECT estado INTO t FROM lf_ops.nucleo_cola_trabajo_v1(hoja) WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'EN_PLAZO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 en plazo (%)', t; END IF;
    SELECT estado INTO t FROM lf_ops.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'DESFASADO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 desfasado tras el plazo (%)', t; END IF;
    -- K9 otra hoja sin ninguna implementación: debe la versión vigente y hoy está en plazo
    SELECT estado INTO t FROM lf_ops.nucleo_cola_trabajo_v1(hoja2) WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'EN_PLAZO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K9 hoja sin implementar hoy (%)', t; END IF;
    -- K10 implementar v2: AL_DIA
    INSERT INTO lf_ops.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 2, hoja, 'PR autotest v2');
    SELECT estado INTO t FROM lf_ops.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K10 al día con v2 (%)', t; END IF;
    -- K11 v3 sin impacto (aclaración de texto): exigible de inmediato y la hoja sigue AL_DIA
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","impacto":"NINGUNO","titulo":"Bloqueo por reenvíos de código OTP","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; aplica a SMS y correo"}');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-CB-1');
    IF (SELECT exigible_desde = publicada_desde FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 3) IS NOT TRUE
       OR (SELECT estado FROM lf_ops.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 'AL_DIA'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K11 aclaración sin impacto (%)', e; END IF;
    -- K12 inmutabilidad: contenido de una versión publicada y descartada → publicada no se pueden cambiar
    ok := false;
    BEGIN PERFORM set_config('lf.nucleo_publicando', 'ZZT-CB-1:1', true);
          UPDATE lf_ops.nucleo_regla_versiones SET titulo = 'Cambiado' WHERE regla = 'ZZT-CB-1' AND version = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_INMUTABLE%'; END;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K12 contenido modificable'; END IF;
    -- K13 descarte: la candidata se descarta con autoridad y motivo; luego se acepta un cambio nuevo
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; cambio que se descartará"}');
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_version_descartar_v1('ZZT-CB-1', 'ZZT-Q', 'corto'); EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DESCARTE_SIN_MOTIVO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13 descarte sin motivo'; END IF;
    PERFORM lf_ops.nucleo_version_descartar_v1('ZZT-CB-1', 'ZZT-Q', 'Se reemplaza por otro cambio con mejor redacción');
    IF lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-1', false)->>'decision' IS DISTINCT FROM 'NO_APLICA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13a evaluar sin candidata'; END IF;
    ok := false;
    BEGIN PERFORM set_config('lf.nucleo_publicando', 'ZZT-CB-1:4', true);
          UPDATE lf_ops.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-CB-1' AND version = 4;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_TRANSICION_INVALIDA%'; END;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13b descartada a publicada'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; redacción final aprobada"}', false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13c cambio tras descarte (%)', r; END IF;
    IF (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13d descarte cambió la regla vigente'; END IF;

    -- K14 revalidación: un campo nuevo en el contrato y un parámetro de muestra aparecen; al quitarlos, desaparecen
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14 revalidación con regla sana'; END IF;
    INSERT INTO lf_ops.nucleo_contrato_campos (familia, campo) VALUES ('ZZT_FAM', 'zzt_campo_nuevo');
    IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1' AND motivo = 'CONTRATO' AND detalle LIKE '%zzt_campo_nuevo%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14 contrato nuevo no detectado'; END IF;
    DELETE FROM lf_ops.nucleo_contrato_campos WHERE campo = 'zzt_campo_nuevo';
    UPDATE public.lf_global_config SET value_status = 'FICTICIO' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS'
       AND valid_from = (SELECT max(valid_from) FROM public.lf_global_config WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS' AND valid_from <= now());
    IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1' AND motivo = 'PARAMETRO')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14b parámetro de muestra no detectado'; END IF;
    UPDATE public.lf_global_config SET value_status = 'REAL' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS' AND value_status = 'FICTICIO';
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14c revalidación no se limpia'; END IF;
    -- K15 una regla con solo una candidata descartada queda RETIRADA
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"codigo":"ZZT-CB-2","clave":"zzt_cb_dos"}');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-2', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-2','hash_evaluado',e->>'hash_paquete','veredicto','DEVOLVER'));
    PERFORM lf_ops.nucleo_regla_evaluar_v1('ZZT-CB-2', true);
    IF NOT EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-CB-2') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15 devuelta fuera de la cola'; END IF;
    PERFORM lf_ops.nucleo_version_descartar_v1('ZZT-CB-2', 'ZZT-Q', 'Se descarta la regla antes de publicarse');
    IF EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-CB-2') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15b descartada sigue en la cola'; END IF;
    IF (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-CB-2') IS DISTINCT FROM 'RETIRADA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15 retirada'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'CAMBIO 16/16';
END $function$;

REVOKE ALL ON FUNCTION lf_ops.nucleo_autotest_datos_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_autotest_datos_v1() TO service_role;
  END IF;
END $g$;

DO $run$ BEGIN
  RAISE NOTICE 'NUCLEO_AUTOTEST: % · % · %', lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_autotest_cambio_v1();
  IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'ZZT-%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_familias WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_nodos WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_hechos WHERE codigo LIKE 'zzt%')
     OR EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = 'ZZT' OR description LIKE '%(autotest)%' OR config_value LIKE '%ZZT%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_autoridades WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_contrato_campos WHERE campo LIKE 'zzt%')
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_DEJO_DATOS'; END IF;
END $run$;
COMMIT;
