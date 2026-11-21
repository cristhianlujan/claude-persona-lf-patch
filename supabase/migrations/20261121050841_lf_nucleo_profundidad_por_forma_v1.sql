-- Núcleo de reglas: la profundidad de pruebas exigida depende de la forma de la condición (LF y SALY, mismo código).
-- Antes: cada regla debía cubrir todas las casuísticas de su naturaleza (una regla sí/no debía probar "en el límite").
-- Ahora: UMBRAL (compara contra un parámetro) exige EN/BAJO/SOBRE_EL_LIMITE; CATEGORICA exige SE_CUMPLE y NO_SE_CUMPLE.
-- Nueva nucleo_forma_condicion_v1 y prueba nucleo_autotest_profundidad_v1. Sin reglas reales afectadas (0 en producción).

-- ===== instancia lf_ops =====
ALTER TABLE lf_ops.nucleo_casuisticas ADD COLUMN forma text NOT NULL DEFAULT 'TODAS';
ALTER TABLE lf_ops.nucleo_casuisticas ADD CONSTRAINT nucleo_casuisticas_forma CHECK (forma IN ('TODAS','UMBRAL','CATEGORICA'));
COMMENT ON COLUMN lf_ops.nucleo_casuisticas.forma IS 'Forma de condición a la que se exige esta casuística: UMBRAL (compara contra un parámetro), CATEGORICA (sí/no o valores) o TODAS';
UPDATE lf_ops.nucleo_casuisticas SET forma = 'UMBRAL' WHERE familia IS NULL AND codigo IN ('EN_EL_LIMITE','BAJO_EL_LIMITE','SOBRE_EL_LIMITE');
INSERT INTO lf_ops.nucleo_casuisticas (codigo, familia, naturaleza, descripcion, forma) VALUES
  ('SE_CUMPLE', NULL, 'CONDUCTA', 'Una entrada que cumple la condición produce el efecto', 'CATEGORICA'),
  ('NO_SE_CUMPLE', NULL, 'CONDUCTA', 'Una entrada que no cumple la condición no produce el efecto', 'CATEGORICA');

CREATE OR REPLACE FUNCTION lf_ops.nucleo_forma_condicion_v1(c jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'lf_ops'
AS $function$
  -- UMBRAL: compara (>, >=, <, <=) algo contra un parámetro; CATEGORICA: cualquier otra condición
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM lf_ops.nucleo_nodos_condicion_v1(c) x
     WHERE x->>'op' IN ('>','>=','<','<=')
       AND (EXISTS (SELECT 1 FROM lf_ops.nucleo_nodos_condicion_v1(x->'izq') y WHERE y ? 'param')
            OR EXISTS (SELECT 1 FROM lf_ops.nucleo_nodos_condicion_v1(x->'der') y WHERE y ? 'param')))
  THEN 'UMBRAL' ELSE 'CATEGORICA' END
$function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  r record; fam record; j record; t record;
  v_ver integer; v_hash text; v_motivos jsonb := '[]'; v_bloqueos jsonb := '[]';
  v_req integer; v_cub integer; v_faltan text; v_fallan text; v_fallan_n integer[] := '{}'; v_prof numeric; v_cal numeric := 0; v_sem numeric := 0;
  v_juicio_ok boolean := false; v_fres numeric := 0; v_nota integer; v_dec text; v_res jsonb; v_txt text; v_id bigint;
  pp numeric; pc numeric; ps numeric; pj numeric; pf numeric; u_auto numeric; u_manual numeric; u_dim numeric; v_cfg jsonb;
  v_siempre boolean;
BEGIN
  SELECT * INTO r FROM nucleo_reglas WHERE codigo = p_regla;
  IF NOT FOUND THEN RAISE EXCEPTION 'NUCLEO_REGLA_INEXISTENTE: %', p_regla; END IF;
  SELECT version INTO v_ver FROM nucleo_regla_versiones WHERE regla = p_regla AND estado = 'CANDIDATA';
  IF v_ver IS NULL THEN RETURN jsonb_build_object('regla', p_regla, 'decision', 'NO_APLICA', 'estado', r.estado); END IF;
  SELECT * INTO fam FROM nucleo_familias WHERE codigo = r.familia;

  pp := nucleo_config_num_v1('NUCLEO_EVAL.PESO_PROFUNDIDAD'); pc := nucleo_config_num_v1('NUCLEO_EVAL.PESO_CALIDAD');
  ps := nucleo_config_num_v1('NUCLEO_EVAL.PESO_SEMANTICA');  pj := nucleo_config_num_v1('NUCLEO_EVAL.PESO_JUICIO');
  pf := nucleo_config_num_v1('NUCLEO_EVAL.PESO_FRESCURA');
  IF pp + pc + ps + pj + pf <> 100 THEN RAISE EXCEPTION 'NUCLEO_EVAL_PESOS_INVALIDOS: suman %', pp + pc + ps + pj + pf; END IF;
  u_auto := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_AUTO'); u_manual := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_MANUAL');
  u_dim := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_DIMENSION');
  IF u_manual > u_auto THEN RAISE EXCEPTION 'NUCLEO_EVAL_UMBRALES_INVALIDOS: manual % > auto %', u_manual, u_auto; END IF;
  v_cfg := jsonb_build_object('pesos', jsonb_build_array(pp, pc, ps, pj, pf), 'umbral_auto', u_auto, 'umbral_manual', u_manual,
           'umbral_dimension', u_dim, 'dias_frescura', nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA'));

  v_hash := nucleo_hash_paquete_v1(p_regla, v_ver);

  -- Pruebas guardadas: se vuelven a ejecutar ahora (con los parámetros vigentes)
  FOR t IN SELECT * FROM nucleo_regla_pruebas WHERE regla = p_regla AND version = v_ver ORDER BY n LOOP
    BEGIN
      v_res := nucleo_eval_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver), t.entrada);
      IF v_res IS DISTINCT FROM t.esperado THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n); v_fallan_n := v_fallan_n || t.n; END IF;
    EXCEPTION WHEN others THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n || ' (' || SQLERRM || ')'); v_fallan_n := v_fallan_n || t.n;
    END;
  END LOOP;
  IF v_fallan IS NOT NULL THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','PRUEBAS','detalle','Fallan con los parámetros vigentes: ' || v_fallan);
  END IF;

  -- Profundidad: casuísticas requeridas cubiertas por una prueba que pasa
  SELECT count(*), count(*) FILTER (WHERE cubierta), string_agg(codigo, ', ' ORDER BY codigo) FILTER (WHERE NOT cubierta)
    INTO v_req, v_cub, v_faltan
    FROM (SELECT k.codigo, EXISTS (
            SELECT 1 FROM nucleo_regla_pruebas t2 WHERE t2.regla = p_regla AND t2.version = v_ver AND t2.casuistica = k.codigo
               AND t2.n <> ALL (v_fallan_n)) AS cubierta
            FROM nucleo_casuisticas k
           WHERE k.estado = 'ACTIVA' AND k.naturaleza = r.naturaleza AND (k.familia IS NULL OR k.familia = r.familia)
             AND k.forma IN ('TODAS', nucleo_forma_condicion_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver)))) x;
  v_prof := CASE WHEN v_req = 0 THEN 0 ELSE v_cub::numeric / v_req END;
  IF v_req = 0 THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','No hay casuísticas definidas para esta familia, naturaleza y forma de condición');
  ELSIF v_faltan IS NOT NULL THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','Faltan pruebas para las casuísticas: ' || v_faltan);
  END IF;

  -- Juicio vigente: el último de esta versión, atado al hash actual
  SELECT * INTO j FROM nucleo_juicios WHERE regla = p_regla AND version = v_ver ORDER BY id DESC LIMIT 1;
  IF j.id IS NULL THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','No tiene juicio: debe juzgarse contra la rúbrica');
  ELSIF j.hash_evaluado <> v_hash THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','El juicio corresponde a otro contenido: debe rejuzgarse');
  ELSE
    v_cal := j.calidad; v_sem := least(j.semantica, j.coherencia);
    v_juicio_ok := j.veredicto = 'PASS';
    v_fres := CASE WHEN j.created_at >= now() - make_interval(days => nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA')::int) THEN 1
                   ELSE nucleo_config_num_v1('NUCLEO_EVAL.FRESCURA_VENCIDA') END;
    IF v_fres < 1 THEN v_motivos := v_motivos || jsonb_build_object('dimension','FRESCURA','detalle','El juicio superó los días de frescura'); END IF;
    SELECT string_agg(format('%s (%s): %s', k.key, k.value->>'puntaje', k.value->>'observacion'), '; ' ORDER BY k.key) INTO v_txt
      FROM jsonb_each(j.puntajes) k WHERE (k.value->>'puntaje')::numeric < 1;
    IF j.calidad < u_dim OR j.semantica < u_dim OR j.coherencia < u_dim OR j.veredicto = 'DEVOLVER' OR v_txt IS NOT NULL THEN
      v_motivos := v_motivos || jsonb_build_object('dimension','JUEZ','detalle', CASE WHEN j.veredicto = 'DEVOLVER' THEN 'El juez devolvió la regla. ' ELSE '' END || COALESCE(v_txt,''));
    END IF;
  END IF;

  -- Requisitos para poder promover
  SELECT string_agg(d.destino, ', ') INTO v_txt FROM nucleo_relaciones d JOIN nucleo_reglas x ON x.codigo = d.destino
   WHERE d.origen = p_regla AND d.tipo = 'DEPENDE' AND x.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','DEPENDENCIAS','detalle','Depende de reglas no vigentes: ' || v_txt); END IF;
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt
    FROM nucleo_nodos_condicion_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver)) x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM public.lf_global_config g WHERE g.scope || '.' || g.config_key = x->>'param'
         AND g.valid_from <= now() AND g.value_status <> 'REAL'
         AND g.valid_from = (SELECT max(g2.valid_from) FROM public.lf_global_config g2 WHERE g2.scope = g.scope AND g2.config_key = g.config_key AND g2.valid_from <= now()));
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','VALOR_REAL','detalle','Usa parámetros con valor de muestra: ' || v_txt); END IF;
  WITH RECURSIVE dn(c) AS (
      SELECT a.nodo FROM nucleo_aplicaciones a WHERE a.regla = p_regla AND a.modo = 'FIJA'
      UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(DISTINCT x.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas x JOIN nucleo_aplicaciones a ON a.regla = x.codigo
   WHERE x.clave = r.clave AND x.codigo <> p_regla AND x.estado IN ('CANDIDATA','VIGENTE') AND a.nodo IN (SELECT c FROM dn);
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','FIJA','detalle','Es FIJA y hay reglas de la misma clave debajo que deben resolverse: ' || v_txt); END IF;

  v_nota := round(pp * v_prof + pc * v_cal + ps * v_sem + pj * (CASE WHEN v_juicio_ok THEN 1 ELSE 0 END) + pf * v_fres);
  v_siempre := COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.TIPOS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(fam.tipo)
            OR COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.FAMILIAS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(r.familia);
  v_dec := CASE
    WHEN jsonb_array_length(v_bloqueos) > 0 THEN 'BLOQUEADA'
    WHEN v_fallan IS NOT NULL OR j.veredicto = 'DEVOLVER' OR v_nota < u_manual THEN 'DEVUELTA'
    WHEN v_nota < u_auto OR v_siempre THEN 'MANUAL'
    ELSE 'AUTO' END;
  IF v_dec = 'MANUAL' AND v_siempre THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','POLITICA','detalle','La familia ' || r.familia || ' siempre requiere decisión humana');
  END IF;
  IF v_dec = 'MANUAL' AND v_nota < u_auto THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral automático %s', v_nota, u_auto));
  END IF;
  IF v_dec = 'DEVUELTA' AND v_nota < u_manual THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral de revisión %s', v_nota, u_manual));
  END IF;

  IF p_registrar THEN
    INSERT INTO nucleo_evaluaciones (regla, version, hash_paquete, nota, decision, componentes, motivos, config_usada, juicio_id)
    VALUES (p_regla, v_ver, v_hash, v_nota, v_dec,
            jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
            v_bloqueos || v_motivos, v_cfg, j.id)
    RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('regla', p_regla, 'version', v_ver, 'hash_paquete', v_hash, 'nota', v_nota, 'decision', v_dec,
    'componentes', jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
    'motivos', v_bloqueos || v_motivos, 'evaluacion_id', v_id);
END $function$;

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
    ('zzt_items','json','ninguna','Lista de montos de prueba del núcleo (autotest de cálculo)'),
    ('zzt_activo','boolean','ninguna','Indicador de prueba del núcleo (autotest de profundidad)');
  INSERT INTO lf_ops.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_monto','CURADO'), ('ZZT_FAM','zzt_items','CURADO'), ('ZZT_FAM','zzt_activo','CURADO');
  INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MONTO_BASE','100.555','DECIMAL','REAL','Monto de prueba del núcleo (autotest de cálculo)'),
    ('ZZT','DECIMALES','2','INTEGER','REAL','Decimales de prueba del núcleo (autotest de cálculo)');
END $function$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_profundidad_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'lf_ops', 'public'
AS $function$
DECLARE
  k record; v_n integer := 0; r jsonb; e jsonb; v_prof text; base jsonb;
  tres jsonb := '{"param":"ZZT.MAX_INTENTOS"}';
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    -- D1 forma de la condición
    FOR k IN SELECT * FROM (VALUES
      ('D1 sí/no',                    '{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb, 'CATEGORICA'),
      ('D1 igual a un texto',         '{"op":"!=","izq":{"hecho":"zzt_activo"},"der":{"lit":"X"}}'::jsonb, 'CATEGORICA'),
      ('D1 mayor o igual a parámetro', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres), 'UMBRAL'),
      ('D1 parámetro a la izquierda', jsonb_build_object('op','<','izq',tres,'der','{"hecho":"zzt_intentos"}'::jsonb), 'UMBRAL'),
      ('D1 cálculo contra parámetro', jsonb_build_object('op','>','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb),'der',tres), 'UMBRAL'),
      ('D1 parámetro dentro de un cálculo', jsonb_build_object('op','>','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',jsonb_build_object('op','*','izq',tres,'der',tres)), 'UMBRAL'),
      ('D1 umbral dentro de un y',    jsonb_build_object('op','y','izq','{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb,'der',jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres)), 'UMBRAL'),
      ('D1 igual a un parámetro',     jsonb_build_object('op','=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres), 'CATEGORICA'),
      ('D1 mayor entre dos datos',    '{"op":">","izq":{"hecho":"zzt_intentos"},"der":{"hecho":"zzt_inactividad"}}'::jsonb, 'CATEGORICA')
    ) t(caso, cond, forma) LOOP
      IF lf_ops.nucleo_forma_condicion_v1(k.cond) IS DISTINCT FROM k.forma THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % dio % y debía dar %', k.caso, lf_ops.nucleo_forma_condicion_v1(k.cond), k.forma;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- D2-D4 profundidad exigida según la forma
    base := jsonb_build_object('clave','zzt_prof','titulo','Regla de prueba de profundidad',
      'descripcion','Bloquea cuando el indicador de prueba está activo (autotest de profundidad)',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-AMB','modo','HEREDA',
      'clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-profundidad','solicitante','autotest'),
      'condicion','{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb);
    FOR k IN SELECT * FROM (VALUES
      ('D2 sí/no con ambos lados', 'ZZT-PR-1', base || jsonb_build_object('pruebas', '[{"casuistica":"SE_CUMPLE","entrada":{"zzt_activo":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"zzt_activo":false},"esperado":false}]'::jsonb), NULL::text, NULL::text),
      ('D3 sí/no sin el lado falso', 'ZZT-PR-2', base || jsonb_build_object('pruebas', '[{"casuistica":"SE_CUMPLE","entrada":{"zzt_activo":true},"esperado":true},{"entrada":{"zzt_activo":true},"esperado":true}]'::jsonb), 'NO_SE_CUMPLE', 'LIMITE'),
      ('D4 umbral solo con sí/no', 'ZZT-PR-3', base || jsonb_build_object(
          'condicion', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres),
          'pruebas', jsonb_build_array(
             jsonb_build_object('casuistica','SE_CUMPLE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
             jsonb_build_object('casuistica','NO_SE_CUMPLE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false))),
        'BAJO_EL_LIMITE, EN_EL_LIMITE, SOBRE_EL_LIMITE', 'SE_CUMPLE')
      ,('D5 umbral con sus tres límites', 'ZZT-PR-4', base || jsonb_build_object(
          'condicion', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres),
          'pruebas', jsonb_build_array(
             jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
             jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
             jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true))),
        NULL, NULL)
    ) t(caso, codigo, payload, falta, no_debe) LOOP
      r := lf_ops.nucleo_regla_proponer_v1(k.payload || jsonb_build_object('codigo', k.codigo, 'clave', lower(replace(k.codigo,'-','_'))));
      IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % no entró (%)', k.caso, r; END IF;
      e := lf_ops.nucleo_regla_evaluar_v1(k.codigo, false);
      SELECT x->>'detalle' INTO v_prof FROM jsonb_array_elements(e->'motivos') x WHERE x->>'dimension' = 'PROFUNDIDAD';
      IF k.falta IS NULL AND v_prof IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % pide profundidad de más: %', k.caso, v_prof; END IF;
      IF k.falta IS NOT NULL AND (v_prof IS NULL OR position(k.falta IN v_prof) = 0 OR position(k.no_debe IN v_prof) > 0) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % debía pedir solo % y pidió %', k.caso, k.falta, coalesce(v_prof, 'nada');
      END IF;
      v_n := v_n + 1;
    END LOOP;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PROFUNDIDAD ' || v_n || '/' || v_n;
END $function$;

REVOKE ALL ON FUNCTION lf_ops.nucleo_forma_condicion_v1(jsonb), lf_ops.nucleo_autotest_profundidad_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_forma_condicion_v1(jsonb), lf_ops.nucleo_autotest_profundidad_v1() TO service_role;
  END IF;
END $g$;

-- ===== instancia saly =====
ALTER TABLE saly.nucleo_casuisticas ADD COLUMN forma text NOT NULL DEFAULT 'TODAS';
ALTER TABLE saly.nucleo_casuisticas ADD CONSTRAINT nucleo_casuisticas_forma CHECK (forma IN ('TODAS','UMBRAL','CATEGORICA'));
COMMENT ON COLUMN saly.nucleo_casuisticas.forma IS 'Forma de condición a la que se exige esta casuística: UMBRAL (compara contra un parámetro), CATEGORICA (sí/no o valores) o TODAS';
UPDATE saly.nucleo_casuisticas SET forma = 'UMBRAL' WHERE familia IS NULL AND codigo IN ('EN_EL_LIMITE','BAJO_EL_LIMITE','SOBRE_EL_LIMITE');
INSERT INTO saly.nucleo_casuisticas (codigo, familia, naturaleza, descripcion, forma) VALUES
  ('SE_CUMPLE', NULL, 'CONDUCTA', 'Una entrada que cumple la condición produce el efecto', 'CATEGORICA'),
  ('NO_SE_CUMPLE', NULL, 'CONDUCTA', 'Una entrada que no cumple la condición no produce el efecto', 'CATEGORICA');

CREATE OR REPLACE FUNCTION saly.nucleo_forma_condicion_v1(c jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
  -- UMBRAL: compara (>, >=, <, <=) algo contra un parámetro; CATEGORICA: cualquier otra condición
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM saly.nucleo_nodos_condicion_v1(c) x
     WHERE x->>'op' IN ('>','>=','<','<=')
       AND (EXISTS (SELECT 1 FROM saly.nucleo_nodos_condicion_v1(x->'izq') y WHERE y ? 'param')
            OR EXISTS (SELECT 1 FROM saly.nucleo_nodos_condicion_v1(x->'der') y WHERE y ? 'param')))
  THEN 'UMBRAL' ELSE 'CATEGORICA' END
$function$;

CREATE OR REPLACE FUNCTION saly.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  r record; fam record; j record; t record;
  v_ver integer; v_hash text; v_motivos jsonb := '[]'; v_bloqueos jsonb := '[]';
  v_req integer; v_cub integer; v_faltan text; v_fallan text; v_fallan_n integer[] := '{}'; v_prof numeric; v_cal numeric := 0; v_sem numeric := 0;
  v_juicio_ok boolean := false; v_fres numeric := 0; v_nota integer; v_dec text; v_res jsonb; v_txt text; v_id bigint;
  pp numeric; pc numeric; ps numeric; pj numeric; pf numeric; u_auto numeric; u_manual numeric; u_dim numeric; v_cfg jsonb;
  v_siempre boolean;
BEGIN
  SELECT * INTO r FROM nucleo_reglas WHERE codigo = p_regla;
  IF NOT FOUND THEN RAISE EXCEPTION 'NUCLEO_REGLA_INEXISTENTE: %', p_regla; END IF;
  SELECT version INTO v_ver FROM nucleo_regla_versiones WHERE regla = p_regla AND estado = 'CANDIDATA';
  IF v_ver IS NULL THEN RETURN jsonb_build_object('regla', p_regla, 'decision', 'NO_APLICA', 'estado', r.estado); END IF;
  SELECT * INTO fam FROM nucleo_familias WHERE codigo = r.familia;

  pp := nucleo_config_num_v1('NUCLEO_EVAL.PESO_PROFUNDIDAD'); pc := nucleo_config_num_v1('NUCLEO_EVAL.PESO_CALIDAD');
  ps := nucleo_config_num_v1('NUCLEO_EVAL.PESO_SEMANTICA');  pj := nucleo_config_num_v1('NUCLEO_EVAL.PESO_JUICIO');
  pf := nucleo_config_num_v1('NUCLEO_EVAL.PESO_FRESCURA');
  IF pp + pc + ps + pj + pf <> 100 THEN RAISE EXCEPTION 'NUCLEO_EVAL_PESOS_INVALIDOS: suman %', pp + pc + ps + pj + pf; END IF;
  u_auto := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_AUTO'); u_manual := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_MANUAL');
  u_dim := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_DIMENSION');
  IF u_manual > u_auto THEN RAISE EXCEPTION 'NUCLEO_EVAL_UMBRALES_INVALIDOS: manual % > auto %', u_manual, u_auto; END IF;
  v_cfg := jsonb_build_object('pesos', jsonb_build_array(pp, pc, ps, pj, pf), 'umbral_auto', u_auto, 'umbral_manual', u_manual,
           'umbral_dimension', u_dim, 'dias_frescura', nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA'));

  v_hash := nucleo_hash_paquete_v1(p_regla, v_ver);

  -- Pruebas guardadas: se vuelven a ejecutar ahora (con los parámetros vigentes)
  FOR t IN SELECT * FROM nucleo_regla_pruebas WHERE regla = p_regla AND version = v_ver ORDER BY n LOOP
    BEGIN
      v_res := nucleo_eval_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver), t.entrada);
      IF v_res IS DISTINCT FROM t.esperado THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n); v_fallan_n := v_fallan_n || t.n; END IF;
    EXCEPTION WHEN others THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n || ' (' || SQLERRM || ')'); v_fallan_n := v_fallan_n || t.n;
    END;
  END LOOP;
  IF v_fallan IS NOT NULL THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','PRUEBAS','detalle','Fallan con los parámetros vigentes: ' || v_fallan);
  END IF;

  -- Profundidad: casuísticas requeridas cubiertas por una prueba que pasa
  SELECT count(*), count(*) FILTER (WHERE cubierta), string_agg(codigo, ', ' ORDER BY codigo) FILTER (WHERE NOT cubierta)
    INTO v_req, v_cub, v_faltan
    FROM (SELECT k.codigo, EXISTS (
            SELECT 1 FROM nucleo_regla_pruebas t2 WHERE t2.regla = p_regla AND t2.version = v_ver AND t2.casuistica = k.codigo
               AND t2.n <> ALL (v_fallan_n)) AS cubierta
            FROM nucleo_casuisticas k
           WHERE k.estado = 'ACTIVA' AND k.naturaleza = r.naturaleza AND (k.familia IS NULL OR k.familia = r.familia)
             AND k.forma IN ('TODAS', nucleo_forma_condicion_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver)))) x;
  v_prof := CASE WHEN v_req = 0 THEN 0 ELSE v_cub::numeric / v_req END;
  IF v_req = 0 THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','No hay casuísticas definidas para esta familia, naturaleza y forma de condición');
  ELSIF v_faltan IS NOT NULL THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','Faltan pruebas para las casuísticas: ' || v_faltan);
  END IF;

  -- Juicio vigente: el último de esta versión, atado al hash actual
  SELECT * INTO j FROM nucleo_juicios WHERE regla = p_regla AND version = v_ver ORDER BY id DESC LIMIT 1;
  IF j.id IS NULL THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','No tiene juicio: debe juzgarse contra la rúbrica');
  ELSIF j.hash_evaluado <> v_hash THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','El juicio corresponde a otro contenido: debe rejuzgarse');
  ELSE
    v_cal := j.calidad; v_sem := least(j.semantica, j.coherencia);
    v_juicio_ok := j.veredicto = 'PASS';
    v_fres := CASE WHEN j.created_at >= now() - make_interval(days => nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA')::int) THEN 1
                   ELSE nucleo_config_num_v1('NUCLEO_EVAL.FRESCURA_VENCIDA') END;
    IF v_fres < 1 THEN v_motivos := v_motivos || jsonb_build_object('dimension','FRESCURA','detalle','El juicio superó los días de frescura'); END IF;
    SELECT string_agg(format('%s (%s): %s', k.key, k.value->>'puntaje', k.value->>'observacion'), '; ' ORDER BY k.key) INTO v_txt
      FROM jsonb_each(j.puntajes) k WHERE (k.value->>'puntaje')::numeric < 1;
    IF j.calidad < u_dim OR j.semantica < u_dim OR j.coherencia < u_dim OR j.veredicto = 'DEVOLVER' OR v_txt IS NOT NULL THEN
      v_motivos := v_motivos || jsonb_build_object('dimension','JUEZ','detalle', CASE WHEN j.veredicto = 'DEVOLVER' THEN 'El juez devolvió la regla. ' ELSE '' END || COALESCE(v_txt,''));
    END IF;
  END IF;

  -- Requisitos para poder promover
  SELECT string_agg(d.destino, ', ') INTO v_txt FROM nucleo_relaciones d JOIN nucleo_reglas x ON x.codigo = d.destino
   WHERE d.origen = p_regla AND d.tipo = 'DEPENDE' AND x.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','DEPENDENCIAS','detalle','Depende de reglas no vigentes: ' || v_txt); END IF;
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt
    FROM nucleo_nodos_condicion_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver)) x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM saly.config_global g WHERE g.scope || '.' || g.config_key = x->>'param'
         AND g.valid_from <= now() AND g.value_status <> 'REAL'
         AND g.valid_from = (SELECT max(g2.valid_from) FROM saly.config_global g2 WHERE g2.scope = g.scope AND g2.config_key = g.config_key AND g2.valid_from <= now()));
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','VALOR_REAL','detalle','Usa parámetros con valor de muestra: ' || v_txt); END IF;
  WITH RECURSIVE dn(c) AS (
      SELECT a.nodo FROM nucleo_aplicaciones a WHERE a.regla = p_regla AND a.modo = 'FIJA'
      UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(DISTINCT x.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas x JOIN nucleo_aplicaciones a ON a.regla = x.codigo
   WHERE x.clave = r.clave AND x.codigo <> p_regla AND x.estado IN ('CANDIDATA','VIGENTE') AND a.nodo IN (SELECT c FROM dn);
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','FIJA','detalle','Es FIJA y hay reglas de la misma clave debajo que deben resolverse: ' || v_txt); END IF;

  v_nota := round(pp * v_prof + pc * v_cal + ps * v_sem + pj * (CASE WHEN v_juicio_ok THEN 1 ELSE 0 END) + pf * v_fres);
  v_siempre := COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.TIPOS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(fam.tipo)
            OR COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.FAMILIAS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(r.familia);
  v_dec := CASE
    WHEN jsonb_array_length(v_bloqueos) > 0 THEN 'BLOQUEADA'
    WHEN v_fallan IS NOT NULL OR j.veredicto = 'DEVOLVER' OR v_nota < u_manual THEN 'DEVUELTA'
    WHEN v_nota < u_auto OR v_siempre THEN 'MANUAL'
    ELSE 'AUTO' END;
  IF v_dec = 'MANUAL' AND v_siempre THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','POLITICA','detalle','La familia ' || r.familia || ' siempre requiere decisión humana');
  END IF;
  IF v_dec = 'MANUAL' AND v_nota < u_auto THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral automático %s', v_nota, u_auto));
  END IF;
  IF v_dec = 'DEVUELTA' AND v_nota < u_manual THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral de revisión %s', v_nota, u_manual));
  END IF;

  IF p_registrar THEN
    INSERT INTO nucleo_evaluaciones (regla, version, hash_paquete, nota, decision, componentes, motivos, config_usada, juicio_id)
    VALUES (p_regla, v_ver, v_hash, v_nota, v_dec,
            jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
            v_bloqueos || v_motivos, v_cfg, j.id)
    RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('regla', p_regla, 'version', v_ver, 'hash_paquete', v_hash, 'nota', v_nota, 'decision', v_dec,
    'componentes', jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
    'motivos', v_bloqueos || v_motivos, 'evaluacion_id', v_id);
END $function$;

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
    ('zzt_items','json','ninguna','Lista de montos de prueba del núcleo (autotest de cálculo)'),
    ('zzt_activo','boolean','ninguna','Indicador de prueba del núcleo (autotest de profundidad)');
  INSERT INTO saly.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_monto','CURADO'), ('ZZT_FAM','zzt_items','CURADO'), ('ZZT_FAM','zzt_activo','CURADO');
  INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MONTO_BASE','100.555','DECIMAL','REAL','Monto de prueba del núcleo (autotest de cálculo)'),
    ('ZZT','DECIMALES','2','INTEGER','REAL','Decimales de prueba del núcleo (autotest de cálculo)');
END $function$;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_profundidad_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  k record; v_n integer := 0; r jsonb; e jsonb; v_prof text; base jsonb;
  tres jsonb := '{"param":"ZZT.MAX_INTENTOS"}';
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    -- D1 forma de la condición
    FOR k IN SELECT * FROM (VALUES
      ('D1 sí/no',                    '{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb, 'CATEGORICA'),
      ('D1 igual a un texto',         '{"op":"!=","izq":{"hecho":"zzt_activo"},"der":{"lit":"X"}}'::jsonb, 'CATEGORICA'),
      ('D1 mayor o igual a parámetro', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres), 'UMBRAL'),
      ('D1 parámetro a la izquierda', jsonb_build_object('op','<','izq',tres,'der','{"hecho":"zzt_intentos"}'::jsonb), 'UMBRAL'),
      ('D1 cálculo contra parámetro', jsonb_build_object('op','>','izq',jsonb_build_object('op','suma','lista','{"hecho":"zzt_items"}'::jsonb),'der',tres), 'UMBRAL'),
      ('D1 parámetro dentro de un cálculo', jsonb_build_object('op','>','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',jsonb_build_object('op','*','izq',tres,'der',tres)), 'UMBRAL'),
      ('D1 umbral dentro de un y',    jsonb_build_object('op','y','izq','{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb,'der',jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres)), 'UMBRAL'),
      ('D1 igual a un parámetro',     jsonb_build_object('op','=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres), 'CATEGORICA'),
      ('D1 mayor entre dos datos',    '{"op":">","izq":{"hecho":"zzt_intentos"},"der":{"hecho":"zzt_inactividad"}}'::jsonb, 'CATEGORICA')
    ) t(caso, cond, forma) LOOP
      IF saly.nucleo_forma_condicion_v1(k.cond) IS DISTINCT FROM k.forma THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % dio % y debía dar %', k.caso, saly.nucleo_forma_condicion_v1(k.cond), k.forma;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    -- D2-D4 profundidad exigida según la forma
    base := jsonb_build_object('clave','zzt_prof','titulo','Regla de prueba de profundidad',
      'descripcion','Bloquea cuando el indicador de prueba está activo (autotest de profundidad)',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-AMB','modo','HEREDA',
      'clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-profundidad','solicitante','autotest'),
      'condicion','{"op":"=","izq":{"hecho":"zzt_activo"},"der":{"lit":true}}'::jsonb);
    FOR k IN SELECT * FROM (VALUES
      ('D2 sí/no con ambos lados', 'ZZT-PR-1', base || jsonb_build_object('pruebas', '[{"casuistica":"SE_CUMPLE","entrada":{"zzt_activo":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"zzt_activo":false},"esperado":false}]'::jsonb), NULL::text, NULL::text),
      ('D3 sí/no sin el lado falso', 'ZZT-PR-2', base || jsonb_build_object('pruebas', '[{"casuistica":"SE_CUMPLE","entrada":{"zzt_activo":true},"esperado":true},{"entrada":{"zzt_activo":true},"esperado":true}]'::jsonb), 'NO_SE_CUMPLE', 'LIMITE'),
      ('D4 umbral solo con sí/no', 'ZZT-PR-3', base || jsonb_build_object(
          'condicion', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres),
          'pruebas', jsonb_build_array(
             jsonb_build_object('casuistica','SE_CUMPLE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
             jsonb_build_object('casuistica','NO_SE_CUMPLE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false))),
        'BAJO_EL_LIMITE, EN_EL_LIMITE, SOBRE_EL_LIMITE', 'SE_CUMPLE')
      ,('D5 umbral con sus tres límites', 'ZZT-PR-4', base || jsonb_build_object(
          'condicion', jsonb_build_object('op','>=','izq','{"hecho":"zzt_intentos"}'::jsonb,'der',tres),
          'pruebas', jsonb_build_array(
             jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
             jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
             jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true))),
        NULL, NULL)
    ) t(caso, codigo, payload, falta, no_debe) LOOP
      r := saly.nucleo_regla_proponer_v1(k.payload || jsonb_build_object('codigo', k.codigo, 'clave', lower(replace(k.codigo,'-','_'))));
      IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % no entró (%)', k.caso, r; END IF;
      e := saly.nucleo_regla_evaluar_v1(k.codigo, false);
      SELECT x->>'detalle' INTO v_prof FROM jsonb_array_elements(e->'motivos') x WHERE x->>'dimension' = 'PROFUNDIDAD';
      IF k.falta IS NULL AND v_prof IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % pide profundidad de más: %', k.caso, v_prof; END IF;
      IF k.falta IS NOT NULL AND (v_prof IS NULL OR position(k.falta IN v_prof) = 0 OR position(k.no_debe IN v_prof) > 0) THEN
        RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: % debía pedir solo % y pidió %', k.caso, k.falta, coalesce(v_prof, 'nada');
      END IF;
      v_n := v_n + 1;
    END LOOP;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PROFUNDIDAD ' || v_n || '/' || v_n;
END $function$;

REVOKE ALL ON FUNCTION saly.nucleo_forma_condicion_v1(jsonb), saly.nucleo_autotest_profundidad_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION saly.nucleo_forma_condicion_v1(jsonb), saly.nucleo_autotest_profundidad_v1() TO service_role;
  END IF;
END $g$;
