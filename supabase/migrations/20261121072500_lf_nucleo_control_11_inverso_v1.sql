-- F2 control 11 inverso: nonblocking suggestion based on current published applications.
-- Same engine in both product instances. No existing rule scope is modified.
BEGIN;
DO $pre$ BEGIN IF md5(pg_get_functiondef('lf_ops.nucleo_regla_proponer_v1(jsonb,boolean)'::regprocedure)) <> 'e8341c0b787db33b9d8e07681651e5f7' THEN RAISE EXCEPTION 'F2_CONTROL11_BASE_DRIFT lf_ops'; END IF; END $pre$;
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
  v_lits jsonb; v_efectos jsonb; v_bajar text; v_evidencia_bajar jsonb;
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

  -- 11 inverso: evidencia vigente concentrada en un subárbol propio.
  -- No presume exclusividad, no cambia alcance y no bloquea la propuesta.
  v_bajar := NULL;
  IF v_nivel IS NOT NULL AND upper(p->>'modo') IN ('HEREDA','FIJA')
     AND nucleo_condicion_problema_v1(p->'condicion') IS NULL THEN
    WITH RECURSIVE
    coinciden AS (
      SELECT DISTINCT r.codigo AS regla, a.nodo, v.version, a.modo
        FROM nucleo_reglas r
        JOIN nucleo_aplicaciones a ON a.regla=r.codigo
        JOIN LATERAL (
          SELECT version, condicion, efecto
          FROM nucleo_regla_versiones
          WHERE regla=r.codigo AND estado='PUBLICADA'
            AND publicada_desde <= now()
            AND (vigente_hasta IS NULL OR vigente_hasta > now())
          ORDER BY version DESC LIMIT 1
        ) v ON true
       WHERE r.estado='VIGENTE' AND r.codigo IS DISTINCT FROM p->>'codigo'
         AND r.clave=p->>'clave' AND r.familia=p->>'familia' AND r.naturaleza=v_nat
         AND v.condicion=p->'condicion' AND v.efecto=upper(p->>'efecto')
    ),
    puntos AS (SELECT DISTINCT nodo FROM coinciden),
    arriba(origen,nodo,padre,distancia) AS (
      SELECT p.nodo,n.codigo,n.padre,0 FROM puntos p JOIN nucleo_nodos n ON n.codigo=p.nodo
      UNION ALL
      SELECT a.origen,n.codigo,n.padre,a.distancia+1
      FROM arriba a JOIN nucleo_nodos n ON n.codigo=a.padre
    ),
    abajo(nodo,ambito) AS (
      SELECT codigo,CASE WHEN nivel='AMBITO' THEN codigo ELSE v_ambito END
      FROM nucleo_nodos WHERE codigo=v_alc
      UNION ALL
      SELECT n.codigo,CASE WHEN n.nivel='AMBITO' THEN n.codigo ELSE a.ambito END
      FROM abajo a JOIN nucleo_nodos n ON n.padre=a.nodo
    ),
    comunes AS (
      SELECT a.nodo,max(a.distancia) AS distancia
      FROM arriba a
      GROUP BY a.nodo
      HAVING count(DISTINCT a.origen)=(SELECT count(*) FROM puntos)
    )
    SELECT c.nodo INTO v_bajar
      FROM comunes c JOIN abajo a ON a.nodo=c.nodo
      JOIN nucleo_nodos n ON n.codigo=c.nodo
     WHERE c.nodo<>v_alc
       AND CASE v_clase
         WHEN 'BACKEND' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_BACKEND')::jsonb,'[]') @> jsonb_build_array(a.ambito)
         WHEN 'PANTALLA' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_PANTALLA')::jsonb,'[]') @> jsonb_build_array(a.ambito)
         WHEN 'TRANSVERSAL' THEN n.nivel='AMBITO'
         ELSE false END
     ORDER BY c.distancia,c.nodo LIMIT 1;
    IF false THEN
      SELECT jsonb_agg(jsonb_build_object('regla',r.codigo,'nodo',a.nodo,'version',v.version,'modo',a.modo)
                        ORDER BY r.codigo,a.nodo) INTO v_evidencia_bajar
        FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla=r.codigo
        JOIN LATERAL (
          SELECT version,condicion,efecto FROM nucleo_regla_versiones
          WHERE regla=r.codigo AND estado='PUBLICADA' AND publicada_desde<=now()
            AND (vigente_hasta IS NULL OR vigente_hasta>now())
          ORDER BY version DESC LIMIT 1
        ) v ON true
       WHERE r.estado='VIGENTE' AND r.codigo IS DISTINCT FROM p->>'codigo'
         AND r.clave=p->>'clave' AND r.familia=p->>'familia' AND r.naturaleza=v_nat
         AND v.condicion=p->'condicion' AND v.efecto=upper(p->>'efecto');
      ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto (inverso)','ok',false,'bloqueante',false,
        'accion','SUGERIR_BAJAR','alcance_sugerido',v_bajar,'evidencia',v_evidencia_bajar,
        'detalle',format('Revisar si el alcance %s puede bajar a %s: las aplicaciones vigentes equivalentes observadas se concentran en ese subárbol. No acredita exclusividad; confirme la intención y cobertura antes de cambiar.',v_alc,v_bajar));
    END IF;
  END IF;

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL AND v_bajar IS NULL THEN
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
DO $pre$ BEGIN IF md5(pg_get_functiondef('saly.nucleo_regla_proponer_v1(jsonb,boolean)'::regprocedure)) <> 'dc58c36dfee99f02867c5f4a6a7d8bfe' THEN RAISE EXCEPTION 'F2_CONTROL11_BASE_DRIFT saly'; END IF; END $pre$;
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
  v_lits jsonb; v_efectos jsonb; v_bajar text; v_evidencia_bajar jsonb;
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

  -- 11 inverso: evidencia vigente concentrada en un subárbol propio.
  -- No presume exclusividad, no cambia alcance y no bloquea la propuesta.
  v_bajar := NULL;
  IF v_nivel IS NOT NULL AND upper(p->>'modo') IN ('HEREDA','FIJA')
     AND nucleo_condicion_problema_v1(p->'condicion') IS NULL THEN
    WITH RECURSIVE
    coinciden AS (
      SELECT DISTINCT r.codigo AS regla, a.nodo, v.version, a.modo
        FROM nucleo_reglas r
        JOIN nucleo_aplicaciones a ON a.regla=r.codigo
        JOIN LATERAL (
          SELECT version, condicion, efecto
          FROM nucleo_regla_versiones
          WHERE regla=r.codigo AND estado='PUBLICADA'
            AND publicada_desde <= now()
            AND (vigente_hasta IS NULL OR vigente_hasta > now())
          ORDER BY version DESC LIMIT 1
        ) v ON true
       WHERE r.estado='VIGENTE' AND r.codigo IS DISTINCT FROM p->>'codigo'
         AND r.clave=p->>'clave' AND r.familia=p->>'familia' AND r.naturaleza=v_nat
         AND v.condicion=p->'condicion' AND v.efecto=upper(p->>'efecto')
    ),
    puntos AS (SELECT DISTINCT nodo FROM coinciden),
    arriba(origen,nodo,padre,distancia) AS (
      SELECT p.nodo,n.codigo,n.padre,0 FROM puntos p JOIN nucleo_nodos n ON n.codigo=p.nodo
      UNION ALL
      SELECT a.origen,n.codigo,n.padre,a.distancia+1
      FROM arriba a JOIN nucleo_nodos n ON n.codigo=a.padre
    ),
    abajo(nodo,ambito) AS (
      SELECT codigo,CASE WHEN nivel='AMBITO' THEN codigo ELSE v_ambito END
      FROM nucleo_nodos WHERE codigo=v_alc
      UNION ALL
      SELECT n.codigo,CASE WHEN n.nivel='AMBITO' THEN n.codigo ELSE a.ambito END
      FROM abajo a JOIN nucleo_nodos n ON n.padre=a.nodo
    ),
    comunes AS (
      SELECT a.nodo,max(a.distancia) AS distancia
      FROM arriba a
      GROUP BY a.nodo
      HAVING count(DISTINCT a.origen)=(SELECT count(*) FROM puntos)
    )
    SELECT c.nodo INTO v_bajar
      FROM comunes c JOIN abajo a ON a.nodo=c.nodo
      JOIN nucleo_nodos n ON n.codigo=c.nodo
     WHERE c.nodo<>v_alc
       AND CASE v_clase
         WHEN 'BACKEND' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_BACKEND')::jsonb,'[]') @> jsonb_build_array(a.ambito)
         WHEN 'PANTALLA' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_PANTALLA')::jsonb,'[]') @> jsonb_build_array(a.ambito)
         WHEN 'TRANSVERSAL' THEN n.nivel='AMBITO'
         ELSE false END
     ORDER BY c.distancia,c.nodo LIMIT 1;
    IF v_bajar IS NOT NULL THEN
      SELECT jsonb_agg(jsonb_build_object('regla',r.codigo,'nodo',a.nodo,'version',v.version,'modo',a.modo)
                        ORDER BY r.codigo,a.nodo) INTO v_evidencia_bajar
        FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla=r.codigo
        JOIN LATERAL (
          SELECT version,condicion,efecto FROM nucleo_regla_versiones
          WHERE regla=r.codigo AND estado='PUBLICADA' AND publicada_desde<=now()
            AND (vigente_hasta IS NULL OR vigente_hasta>now())
          ORDER BY version DESC LIMIT 1
        ) v ON true
       WHERE r.estado='VIGENTE' AND r.codigo IS DISTINCT FROM p->>'codigo'
         AND r.clave=p->>'clave' AND r.familia=p->>'familia' AND r.naturaleza=v_nat
         AND v.condicion=p->'condicion' AND v.efecto=upper(p->>'efecto');
      ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto (inverso)','ok',false,'bloqueante',false,
        'accion','SUGERIR_BAJAR','alcance_sugerido',v_bajar,'evidencia',v_evidencia_bajar,
        'detalle',format('Revisar si el alcance %s puede bajar a %s: las aplicaciones vigentes equivalentes observadas se concentran en ese subárbol. No acredita exclusividad; confirme la intención y cobertura antes de cambiar.',v_alc,v_bajar));
    END IF;
  END IF;

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL AND v_bajar IS NULL THEN
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
CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_alcance_inverso_v1()
 RETURNS text LANGUAGE plpgsql SET search_path TO 'pg_catalog','lf_ops','public' AS $test$
DECLARE
 p jsonb; r jsonb; c jsonb; raiz text; before_count integer;
BEGIN
 BEGIN
  PERFORM nucleo_autotest_datos_v1();
  SELECT codigo INTO raiz FROM nucleo_nodos WHERE nivel='GLOBAL';
  p := jsonb_build_object('codigo','ZZT-I1','clave','zzt_inverso','titulo','Regla de prueba de alcance',
    'descripcion','Condición de prueba de alcance del núcleo', 'familia','ZZT_FAM','naturaleza','CONDUCTA',
    'autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-MOD-1','modo','HEREDA','clase','PANTALLA',
    'efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-inverso','solicitante','autotest'),
    'condicion',jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
    'pruebas',jsonb_build_array(jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
    jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));
  -- I1 no evidence: no narrowing.
  r := nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I1_NO_EVIDENCE'; END IF;
  -- I2 a candidate is not authoritative evidence.
  r:=nucleo_regla_proponer_v1(p);
  IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE %',r; END IF;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I2_CANDIDATE'; END IF;
  -- Publish fixture using same transactional route as existing suite.
  PERFORM set_config('lf.nucleo_publicando','ZZT-I1:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I1';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I1' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  -- I3 broad scope produces exact nonblocking control and persisted evidence.
  SELECT count(*) INTO before_count FROM nucleo_reglas;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  SELECT x INTO c FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR';
  IF c IS NULL OR c->>'n'<>'11' OR c->>'alcance_sugerido'<>'ZZT-MOD-1' OR (c->>'bloqueante')::boolean IS NOT FALSE OR (c->>'ok')::boolean IS NOT FALSE
     OR c->'evidencia' IS DISTINCT FROM '[{"regla":"ZZT-I1","nodo":"ZZT-MOD-1","version":1,"modo":"HEREDA"}]'::jsonb
     OR r->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'F2_INV_I3_EXPECTED_SUGGESTION %',r; END IF;
  -- I4 dry-run has no writes; no contradictory upward suggestion.
  IF (SELECT count(*) FROM nucleo_reglas)<>before_count OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n'='11' AND x->>'control'='Alcance correcto')
     THEN RAISE EXCEPTION 'F2_INV_I4_DRY_RUN'; END IF;
  -- I5 same scope or SOLO_AQUI cannot trigger narrowing.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I5_SAME'; END IF;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB','modo','SOLO_AQUI'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I5_SOLO'; END IF;
  -- I6 different effect cannot be evidence.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB','efecto','PERMITIR'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I6_EFFECT'; END IF;
  -- I7 suggestion does not change even an accepted candidate application.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IA','alcance','ZZT-AMB'));
  IF r->>'resultado'<>'CANDIDATA' OR NOT EXISTS(SELECT 1 FROM nucleo_aplicaciones WHERE regla='ZZT-IA' AND nodo='ZZT-AMB') OR
     EXISTS(SELECT 1 FROM nucleo_aplicaciones WHERE regla='ZZT-IA' AND nodo<>'ZZT-AMB') THEN RAISE EXCEPTION 'F2_INV_I7_NO_MOVE %',r; END IF;
  -- I8 evidence in two modules gives their common scope, not an arbitrary leaf.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-I2','alcance','ZZT-MOD-2'));
  IF r->>'resultado'<>'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE2 %',r; END IF;
  PERFORM set_config('lf.nucleo_publicando','ZZT-I2:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I2';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I2' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance',raiz,'clase','TRANSVERSAL'),false);
  SELECT x INTO c FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR';
  IF c IS NULL OR c->>'alcance_sugerido'<>'ZZT-AMB' OR jsonb_array_length(c->'evidencia')<>2 THEN RAISE EXCEPTION 'F2_INV_I8_COMMON %',r; END IF;
  -- I9 evidence spanning proposal's distinct branches: do not suggest one.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I9_COVERED'; END IF;
  -- I10 evidence not confined to one eligible subtree, no suggestion.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-I3','alcance','ZZT-BACK','clase','BACKEND'));
  IF r->>'resultado'<>'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE3 %',r; END IF;
  PERFORM set_config('lf.nucleo_publicando','ZZT-I3:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I3';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I3' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance',raiz,'clase','TRANSVERSAL'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I10_OUTSIDE'; END IF;
  RAISE EXCEPTION 'F2_INV_ROLLBACK_OK';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'F2_INV_ROLLBACK_OK' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM nucleo_reglas WHERE codigo IN ('ZZT-I1','ZZT-I2','ZZT-I3','ZZT-IA')) THEN RAISE EXCEPTION 'F2_INV_ROLLBACK_LEAK'; END IF;
 RETURN 'ALCANCE_INVERSO 10/10';
END $test$;
REVOKE ALL ON FUNCTION lf_ops.nucleo_autotest_alcance_inverso_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION lf_ops.nucleo_autotest_alcance_inverso_v1() TO service_role;
CREATE OR REPLACE FUNCTION saly.nucleo_autotest_alcance_inverso_v1()
 RETURNS text LANGUAGE plpgsql SET search_path TO 'pg_catalog','saly','public' AS $test$
DECLARE
 p jsonb; r jsonb; c jsonb; raiz text; before_count integer;
BEGIN
 BEGIN
  PERFORM nucleo_autotest_datos_v1();
  SELECT codigo INTO raiz FROM nucleo_nodos WHERE nivel='GLOBAL';
  p := jsonb_build_object('codigo','ZZT-I1','clave','zzt_inverso','titulo','Regla de prueba de alcance',
    'descripcion','Condición de prueba de alcance del núcleo', 'familia','ZZT_FAM','naturaleza','CONDUCTA',
    'autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-MOD-1','modo','HEREDA','clase','PANTALLA',
    'efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-inverso','solicitante','autotest'),
    'condicion',jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
    'pruebas',jsonb_build_array(jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
    jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));
  -- I1 no evidence: no narrowing.
  r := nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I1_NO_EVIDENCE'; END IF;
  -- I2 a candidate is not authoritative evidence.
  r:=nucleo_regla_proponer_v1(p);
  IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE %',r; END IF;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I2_CANDIDATE'; END IF;
  -- Publish fixture using same transactional route as existing suite.
  PERFORM set_config('lf.nucleo_publicando','ZZT-I1:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I1';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I1' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  -- I3 broad scope produces exact nonblocking control and persisted evidence.
  SELECT count(*) INTO before_count FROM nucleo_reglas;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  SELECT x INTO c FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR';
  IF c IS NULL OR c->>'n'<>'11' OR c->>'alcance_sugerido'<>'ZZT-MOD-1' OR (c->>'bloqueante')::boolean IS NOT FALSE OR (c->>'ok')::boolean IS NOT FALSE
     OR c->'evidencia' IS DISTINCT FROM '[{"regla":"ZZT-I1","nodo":"ZZT-MOD-1","version":1,"modo":"HEREDA"}]'::jsonb
     OR r->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'F2_INV_I3_EXPECTED_SUGGESTION %',r; END IF;
  -- I4 dry-run has no writes; no contradictory upward suggestion.
  IF (SELECT count(*) FROM nucleo_reglas)<>before_count OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n'='11' AND x->>'control'='Alcance correcto')
     THEN RAISE EXCEPTION 'F2_INV_I4_DRY_RUN'; END IF;
  -- I5 same scope or SOLO_AQUI cannot trigger narrowing.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I5_SAME'; END IF;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB','modo','SOLO_AQUI'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I5_SOLO'; END IF;
  -- I6 different effect cannot be evidence.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB','efecto','PERMITIR'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I6_EFFECT'; END IF;
  -- I7 suggestion does not change even an accepted candidate application.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IA','alcance','ZZT-AMB'));
  IF r->>'resultado'<>'CANDIDATA' OR NOT EXISTS(SELECT 1 FROM nucleo_aplicaciones WHERE regla='ZZT-IA' AND nodo='ZZT-AMB') OR
     EXISTS(SELECT 1 FROM nucleo_aplicaciones WHERE regla='ZZT-IA' AND nodo<>'ZZT-AMB') THEN RAISE EXCEPTION 'F2_INV_I7_NO_MOVE %',r; END IF;
  -- I8 evidence in two modules gives their common scope, not an arbitrary leaf.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-I2','alcance','ZZT-MOD-2'));
  IF r->>'resultado'<>'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE2 %',r; END IF;
  PERFORM set_config('lf.nucleo_publicando','ZZT-I2:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I2';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I2' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance',raiz,'clase','TRANSVERSAL'),false);
  SELECT x INTO c FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR';
  IF c IS NULL OR c->>'alcance_sugerido'<>'ZZT-AMB' OR jsonb_array_length(c->'evidencia')<>2 THEN RAISE EXCEPTION 'F2_INV_I8_COMMON %',r; END IF;
  -- I9 evidence spanning proposal's distinct branches: do not suggest one.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance','ZZT-AMB'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I9_COVERED'; END IF;
  -- I10 evidence not confined to one eligible subtree, no suggestion.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-I3','alcance','ZZT-BACK','clase','BACKEND'));
  IF r->>'resultado'<>'CANDIDATA' THEN RAISE EXCEPTION 'F2_INV_FIXTURE3 %',r; END IF;
  PERFORM set_config('lf.nucleo_publicando','ZZT-I3:1',true);
  UPDATE nucleo_reglas SET estado='VIGENTE' WHERE codigo='ZZT-I3';
  UPDATE nucleo_regla_versiones SET estado='PUBLICADA',publicada_desde=now(),exigible_desde=now() WHERE regla='ZZT-I3' AND version=1;
  PERFORM set_config('lf.nucleo_publicando','',true);
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-IP','alcance',raiz,'clase','TRANSVERSAL'),false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'accion'='SUGERIR_BAJAR') THEN RAISE EXCEPTION 'F2_INV_I10_OUTSIDE'; END IF;
  RAISE EXCEPTION 'F2_INV_ROLLBACK_OK';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'F2_INV_ROLLBACK_OK' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM nucleo_reglas WHERE codigo IN ('ZZT-I1','ZZT-I2','ZZT-I3','ZZT-IA')) THEN RAISE EXCEPTION 'F2_INV_ROLLBACK_LEAK'; END IF;
 RETURN 'ALCANCE_INVERSO 10/10';
END $test$;
REVOKE ALL ON FUNCTION saly.nucleo_autotest_alcance_inverso_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION saly.nucleo_autotest_alcance_inverso_v1() TO service_role;
DO $verify$ BEGIN
 IF lf_ops.nucleo_autotest_alcance_inverso_v1() IS DISTINCT FROM 'ALCANCE_INVERSO 10/10' OR saly.nucleo_autotest_alcance_inverso_v1() IS DISTINCT FROM 'ALCANCE_INVERSO 10/10' THEN RAISE EXCEPTION 'F2_INV_SUITE_FAILED'; END IF;
END $verify$;
COMMIT;
