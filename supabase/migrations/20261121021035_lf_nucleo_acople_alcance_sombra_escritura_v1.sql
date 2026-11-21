-- Núcleo de reglas, acople reversible (2): alcance derivado de las reglas legadas y sombra por escritura (solo LF).
-- 1) lf_ops.lf_legado_alcance_v1(regla): con las pantallas enlazadas de una regla legada busca su ancestro común
--    más bajo en el árbol y si lo cubren completo. Propone UNA_PANTALLA, HEREDA_EN_ANCESTRO (cubre todo),
--    APLICACIONES_POR_PANTALLA (cubre una parte) o SIN_PANTALLAS_EN_ARBOL. Una corrida queda en lf_ops.lf_legado_alcance.
-- 2) El modo sombra usa ese alcance derivado; la brecha ALCANCE_POR_DERIVAR queda solo donde no hay propuesta única.
-- 3) Sombra por escritura: un trigger sobre lf_ops.reglas evalúa cada alta o cambio en el momento. Nunca bloquea
--    la escritura legada (cualquier error queda registrado) y se apaga con NUCLEO.SOMBRA_ESCRITURA_ACTIVA = false.
BEGIN;

INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','SOMBRA_ESCRITURA_ACTIVA','true','BOOLEAN','REAL','Activa la evaluación en sombra de cada alta o cambio en lf_ops.reglas. false la apaga sin migración.');

CREATE TABLE lf_ops.lf_legado_alcance (
  corrida timestamptz NOT NULL,
  regla_id integer NOT NULL,
  pantallas integer NOT NULL,
  pantallas_en_arbol integer NOT NULL,
  ancestro text,
  pantallas_bajo_ancestro integer,
  propuesta text NOT NULL,
  aplicaciones text[] NOT NULL,
  PRIMARY KEY (corrida, regla_id),
  CONSTRAINT lf_legado_alcance_propuesta CHECK (propuesta IN ('TRANSVERSAL','UNA_PANTALLA','HEREDA_EN_ANCESTRO','APLICACIONES_POR_PANTALLA','SIN_PANTALLAS_EN_ARBOL'))
);
COMMENT ON TABLE lf_ops.lf_legado_alcance IS 'Alcance derivado de cada regla legada en el árbol del núcleo, a partir de sus enlaces a pantallas. Una corrida por fecha.';

CREATE OR REPLACE FUNCTION lf_ops.lf_legado_alcance_v1(p_regla integer)
RETURNS TABLE (pantallas integer, pantallas_en_arbol integer, ancestro text, pantallas_bajo_ancestro integer, propuesta text, aplicaciones text[])
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, lf_ops AS $$
DECLARE v_transversal boolean; v_raiz text; v_nodos text[]; v_k integer; v_anc text; v_n integer;
BEGIN
  SELECT es_transversal INTO v_transversal FROM reglas WHERE id = p_regla;
  SELECT codigo INTO v_raiz FROM nucleo_nodos WHERE nivel = 'GLOBAL';
  SELECT count(*)::int, COALESCE(array_agg(DISTINCT n.codigo ORDER BY n.codigo) FILTER (WHERE n.codigo IS NOT NULL), '{}')
    INTO pantallas, v_nodos
    FROM reglas_pantallas rp LEFT JOIN nucleo_nodos n ON n.pantalla_id = rp.pantalla_id WHERE rp.regla_id = p_regla;
  pantallas_en_arbol := cardinality(v_nodos);
  IF v_transversal OR pantallas = 0 THEN
    ancestro := v_raiz; pantallas_bajo_ancestro := NULL; propuesta := 'TRANSVERSAL'; aplicaciones := ARRAY[v_raiz]; RETURN NEXT; RETURN;
  END IF;
  IF pantallas_en_arbol = 0 THEN
    propuesta := 'SIN_PANTALLAS_EN_ARBOL'; aplicaciones := '{}'; RETURN NEXT; RETURN;
  END IF;
  IF pantallas_en_arbol = 1 THEN
    ancestro := v_nodos[1]; pantallas_bajo_ancestro := 1; propuesta := 'UNA_PANTALLA'; aplicaciones := v_nodos; RETURN NEXT; RETURN;
  END IF;
  -- ancestro común más bajo: el ancestro compartido por todas las pantallas con mayor profundidad
  WITH RECURSIVE anc(hoja, nodo, prof) AS (
      SELECT x, x, 0 FROM unnest(v_nodos) x
      UNION ALL SELECT a.hoja, n.padre, a.prof + 1 FROM anc a JOIN nucleo_nodos n ON n.codigo = a.nodo WHERE n.padre IS NOT NULL),
    nivel(nodo, d) AS (
      SELECT n.codigo, (WITH RECURSIVE up(c, d) AS (SELECT n.codigo, 0 UNION ALL SELECT m.padre, up.d + 1 FROM up JOIN nucleo_nodos m ON m.codigo = up.c WHERE m.padre IS NOT NULL) SELECT max(d) FROM up)
        FROM nucleo_nodos n)
  SELECT a.nodo INTO v_anc FROM anc a JOIN nivel l ON l.nodo = a.nodo
   GROUP BY a.nodo, l.d HAVING count(DISTINCT a.hoja) = cardinality(v_nodos) ORDER BY l.d DESC LIMIT 1;
  WITH RECURSIVE dn(c) AS (SELECT v_anc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT count(*)::int INTO v_n FROM nucleo_nodos n WHERE n.codigo IN (SELECT c FROM dn) AND n.nivel = 'PANTALLA';
  ancestro := v_anc; pantallas_bajo_ancestro := v_n;
  IF v_n = pantallas_en_arbol THEN propuesta := 'HEREDA_EN_ANCESTRO'; aplicaciones := ARRAY[v_anc];
  ELSE propuesta := 'APLICACIONES_POR_PANTALLA'; aplicaciones := v_nodos; END IF;
  RETURN NEXT;
END $$;

-- Evaluación en sombra de una regla legada (la usan la corrida completa y el trigger)
CREATE OR REPLACE FUNCTION lf_ops.lf_legado_sombra_regla_v1(p_regla integer, p_corrida timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  r record; a record; v_p jsonb; v_res jsonb; v_fall text[]; v_brechas text[]; v_sinexp text[]; v_alc text;
  v_mapa jsonb := '{"Campos obligatorios":"SIN_ESTRUCTURA","Condición bien formada":"SIN_ESTRUCTURA","Efecto coherente con la naturaleza":"SIN_ESTRUCTURA",
                    "Pruebas mínimas de la familia":"SIN_PRUEBAS","Pruebas relativas al parámetro":"SIN_PRUEBAS","Pruebas se ejecutan y pasan":"SIN_PRUEBAS",
                    "Autoridad vigente":"SIN_AUTORIDAD_REGISTRADA","Familia existe":"SIN_FAMILIA","Alcance existe":"ALCANCE_POR_DERIVAR",
                    "Clase coherente con el alcance":"ALCANCE_POR_DERIVAR","Código libre":"YA_EN_EL_NUCLEO","Clasificación contra lo existente":"DUPLICADO_EN_LEGADO",
                    "Sin conflicto con reglas fijas superiores":"CONFLICTO_FIJA"}';
BEGIN
  SELECT g.*, f.familia, f.naturaleza INTO r FROM reglas g LEFT JOIN nucleo_regla_familia f ON f.regla_id = g.id WHERE g.id = p_regla;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO a FROM lf_legado_alcance_v1(p_regla);
  v_alc := CASE WHEN a.propuesta IN ('TRANSVERSAL','UNA_PANTALLA','HEREDA_EN_ANCESTRO') THEN a.aplicaciones[1]
                WHEN a.propuesta = 'APLICACIONES_POR_PANTALLA' THEN a.aplicaciones[1] END;
  v_p := jsonb_build_object(
    'codigo', r.codigo, 'clave', left(trim(BOTH '_' FROM lower(regexp_replace(r.codigo, '[^A-Za-z0-9]+', '_', 'g'))), 80),
    'titulo', r.titulo, 'descripcion', r.descripcion, 'familia', r.familia, 'naturaleza', r.naturaleza,
    'autoridad', r.origen, 'dueno', COALESCE(r.created_by, 'LEGADO'), 'alcance', v_alc, 'modo', 'HEREDA',
    'clase', CASE WHEN a.propuesta = 'TRANSVERSAL' OR (SELECT nivel FROM nucleo_nodos WHERE codigo = v_alc) IN ('GLOBAL','AMBITO') THEN 'TRANSVERSAL' ELSE 'PANTALLA' END,
    'impacto', 'IMPLEMENTAR', 'origen', jsonb_build_object('tipo','MIGRACION','ref','lf_ops.reglas/' || r.id,'solicitante', COALESCE(r.created_by, 'legado')));
  v_res := nucleo_regla_proponer_v1(v_p, false);
  SELECT COALESCE(array_agg(DISTINCT x->>'control' ORDER BY x->>'control'), '{}') INTO v_fall
    FROM jsonb_array_elements(v_res->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
  SELECT COALESCE(array_agg(DISTINCT v_mapa->>f ORDER BY v_mapa->>f) FILTER (WHERE v_mapa ? f), '{}'),
         COALESCE(array_agg(f ORDER BY f) FILTER (WHERE NOT v_mapa ? f), '{}')
    INTO v_brechas, v_sinexp FROM unnest(v_fall) f;
  IF a.propuesta IN ('APLICACIONES_POR_PANTALLA','SIN_PANTALLAS_EN_ARBOL') THEN v_brechas := array_append(v_brechas, 'ALCANCE_POR_DERIVAR'); END IF;
  INSERT INTO lf_legado_sombra VALUES (p_corrida, r.id, r.codigo, r.estado, r.origen, r.created_by, r.familia,
    COALESCE(a.propuesta || ':' || array_to_string(a.aplicaciones, ','), a.propuesta), a.pantallas,
    v_res->>'resultado', v_fall, (SELECT COALESCE(array_agg(DISTINCT b ORDER BY b), '{}') FROM unnest(v_brechas) b), v_sinexp)
  ON CONFLICT (corrida, regla_id) DO UPDATE SET resultado = EXCLUDED.resultado, fallidos = EXCLUDED.fallidos, brechas = EXCLUDED.brechas,
    sin_explicar = EXCLUDED.sin_explicar, alcance_propuesto = EXCLUDED.alcance_propuesto, estado_legado = EXCLUDED.estado_legado;
END $$;

-- Corrida completa (misma firma que antes): ahora con alcance derivado y guardando también el alcance
CREATE OR REPLACE FUNCTION lf_ops.lf_legado_sombra_v1(p_guardar boolean DEFAULT true)
RETURNS TABLE (estado_legado text, origen text, resultado text, brecha text, reglas bigint, sin_explicar bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE v_corrida timestamptz := clock_timestamp(); g record;
BEGIN
  FOR g IN SELECT id FROM reglas ORDER BY id LOOP
    PERFORM lf_legado_sombra_regla_v1(g.id, v_corrida);
    IF p_guardar THEN
      INSERT INTO lf_legado_alcance SELECT v_corrida, g.id, a.* FROM lf_legado_alcance_v1(g.id) a;
    END IF;
  END LOOP;
  RETURN QUERY
    SELECT s.estado_legado, s.origen, s.resultado, b, count(*), count(*) FILTER (WHERE cardinality(s.sin_explicar) > 0)
      FROM lf_legado_sombra s LEFT JOIN LATERAL unnest(CASE WHEN cardinality(s.brechas) = 0 THEN ARRAY['NINGUNA'] ELSE s.brechas END) b ON true
     WHERE s.corrida = v_corrida GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
  IF NOT p_guardar THEN DELETE FROM lf_legado_sombra WHERE corrida = v_corrida; END IF;
END $$;

-- Sombra por escritura: nunca bloquea la escritura legada
CREATE TABLE lf_ops.lf_legado_sombra_errores (
  ocurrido timestamptz NOT NULL DEFAULT clock_timestamp(),
  regla_id integer,
  operacion text NOT NULL,
  error text NOT NULL
);
COMMENT ON TABLE lf_ops.lf_legado_sombra_errores IS 'Errores de la sombra por escritura: la escritura legada siguió; aquí queda qué falló en la evaluación paralela.';
CREATE OR REPLACE FUNCTION lf_ops.fn_lf_legado_sombra_escritura_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
BEGIN
  IF COALESCE((SELECT g.config_value FROM public.lf_global_config g WHERE g.scope = 'NUCLEO' AND g.config_key = 'SOMBRA_ESCRITURA_ACTIVA'
                AND g.valid_from <= now() ORDER BY g.valid_from DESC LIMIT 1), 'false') <> 'true' THEN
    RETURN NULL;
  END IF;
  BEGIN
    PERFORM lf_legado_sombra_regla_v1(NEW.id, clock_timestamp());
  EXCEPTION WHEN others THEN
    BEGIN
      INSERT INTO lf_legado_sombra_errores (regla_id, operacion, error) VALUES (NEW.id, TG_OP, left(SQLERRM, 500));
    EXCEPTION WHEN others THEN NULL;
    END;
  END;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_lf_legado_sombra_escritura AFTER INSERT OR UPDATE ON lf_ops.reglas
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_lf_legado_sombra_escritura_v1();

-- Autoprueba: alcance derivado y sombra por escritura (incluido que un fallo no bloquee la escritura legada)
CREATE OR REPLACE FUNCTION lf_ops.lf_puente2_autotest_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $autotest$
DECLARE v_mod text; v_p1 integer; v_p2 integer; v_p3 integer; a record; v_id integer := 2147480000; v_n bigint;
BEGIN
  BEGIN
    -- un módulo con al menos dos pantallas del árbol
    SELECT n.padre INTO v_mod FROM nucleo_nodos n WHERE n.nivel = 'PANTALLA' GROUP BY n.padre HAVING count(*) >= 2 ORDER BY n.padre LIMIT 1;
    IF v_mod IS NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S0 no hay un módulo con dos pantallas'; END IF;
    SELECT (array_agg(pantalla_id ORDER BY codigo))[1], (array_agg(pantalla_id ORDER BY codigo))[2] INTO v_p1, v_p2 FROM nucleo_nodos WHERE padre = v_mod AND nivel = 'PANTALLA';
    -- S1 regla con todas las pantallas del módulo: hereda en el módulo
    INSERT INTO reglas (id, codigo, categoria, titulo, descripcion, origen, created_by) VALUES (v_id, 'ZZT-LEG-1', 'X', 'Regla legada de prueba', 'Regla legada de prueba del alcance derivado', 'prueba', 'autotest');
    INSERT INTO reglas_pantallas (regla_id, pantalla_id) SELECT v_id, pantalla_id FROM nucleo_nodos WHERE padre = v_mod AND nivel = 'PANTALLA';
    SELECT * INTO a FROM lf_legado_alcance_v1(v_id);
    IF a.propuesta IS DISTINCT FROM 'HEREDA_EN_ANCESTRO' OR a.ancestro IS DISTINCT FROM v_mod THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S1 cubre el módulo (%)', row_to_json(a); END IF;
    -- S2 si solo enlaza una parte, propone una aplicación por pantalla
    DELETE FROM reglas_pantallas WHERE regla_id = v_id AND pantalla_id <> v_p1 AND pantalla_id <> v_p2;
    IF (SELECT count(*) FROM nucleo_nodos WHERE padre = v_mod AND nivel = 'PANTALLA') > 2 THEN
      SELECT * INTO a FROM lf_legado_alcance_v1(v_id);
      IF a.propuesta IS DISTINCT FROM 'APLICACIONES_POR_PANTALLA' OR cardinality(a.aplicaciones) <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S2 parcial (%)', row_to_json(a); END IF;
    END IF;
    -- S3 una sola pantalla, y una pantalla fuera del árbol
    DELETE FROM reglas_pantallas WHERE regla_id = v_id AND pantalla_id = v_p2;
    SELECT * INTO a FROM lf_legado_alcance_v1(v_id);
    IF a.propuesta IS DISTINCT FROM 'UNA_PANTALLA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S3 una pantalla (%)', row_to_json(a); END IF;
    SELECT min(p.id) INTO v_p3 FROM pantallas p WHERE NOT EXISTS (SELECT 1 FROM nucleo_nodos n WHERE n.pantalla_id = p.id);
    IF v_p3 IS NOT NULL THEN
      DELETE FROM reglas_pantallas WHERE regla_id = v_id;
      INSERT INTO reglas_pantallas (regla_id, pantalla_id) VALUES (v_id, v_p3);
      SELECT * INTO a FROM lf_legado_alcance_v1(v_id);
      IF a.propuesta IS DISTINCT FROM 'SIN_PANTALLAS_EN_ARBOL' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S3b fuera del árbol (%)', row_to_json(a); END IF;
    END IF;
    -- S4 la escritura legada dispara la sombra en el momento
    SELECT count(*) INTO v_n FROM lf_legado_sombra WHERE regla_id = v_id;
    UPDATE reglas SET titulo = 'Regla legada de prueba (cambio)' WHERE id = v_id;
    IF (SELECT count(*) FROM lf_legado_sombra WHERE regla_id = v_id) <= v_n THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S4 la escritura no se evaluó en sombra'; END IF;
    -- S5 con el interruptor apagado no evalúa
    UPDATE public.lf_global_config SET config_value = 'false' WHERE scope = 'NUCLEO' AND config_key = 'SOMBRA_ESCRITURA_ACTIVA';
    SELECT count(*) INTO v_n FROM lf_legado_sombra WHERE regla_id = v_id;
    UPDATE reglas SET titulo = 'Regla legada de prueba (otro cambio)' WHERE id = v_id;
    IF (SELECT count(*) FROM lf_legado_sombra WHERE regla_id = v_id) <> v_n THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S5 evaluó con el interruptor apagado'; END IF;
    UPDATE public.lf_global_config SET config_value = 'true' WHERE scope = 'NUCLEO' AND config_key = 'SOMBRA_ESCRITURA_ACTIVA';
    -- S6 si la evaluación falla, la escritura legada sigue y el error queda registrado
    ALTER FUNCTION lf_ops.lf_legado_sombra_regla_v1(integer, timestamptz) RENAME TO lf_legado_sombra_regla_v1_apartada;
    UPDATE reglas SET titulo = 'Regla legada de prueba (con la sombra rota)' WHERE id = v_id;
    ALTER FUNCTION lf_ops.lf_legado_sombra_regla_v1_apartada(integer, timestamptz) RENAME TO lf_legado_sombra_regla_v1;
    IF (SELECT titulo FROM reglas WHERE id = v_id) <> 'Regla legada de prueba (con la sombra rota)'
       OR NOT EXISTS (SELECT 1 FROM lf_legado_sombra_errores WHERE regla_id = v_id AND operacion = 'UPDATE')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: S6 la sombra rota bloqueó la escritura o no registró el error'; END IF;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PUENTE2 6/6';
END $autotest$;

REVOKE ALL ON lf_ops.lf_legado_alcance, lf_ops.lf_legado_sombra_errores FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.lf_legado_alcance ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.lf_legado_sombra_errores ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.lf_legado_alcance AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.lf_legado_sombra_errores AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.lf_legado_alcance_v1(integer), lf_ops.lf_legado_sombra_regla_v1(integer, timestamptz),
  lf_ops.fn_lf_legado_sombra_escritura_v1(), lf_ops.lf_puente2_autotest_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.lf_legado_alcance_v1(integer), lf_ops.lf_legado_sombra_regla_v1(integer, timestamptz), lf_ops.lf_puente2_autotest_v1() TO service_role;
    GRANT SELECT ON lf_ops.lf_legado_alcance, lf_ops.lf_legado_sombra_errores TO service_role;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT SELECT ON lf_ops.lf_legado_alcance, lf_ops.lf_legado_sombra_errores TO supabase_read_only_user;
  END IF;
END $g$;

DO $run$
DECLARE v_total bigint; v_sinexp bigint; v_c timestamptz;
BEGIN
  RAISE NOTICE 'NUCLEO_AUTOTEST %', lf_ops.lf_puente2_autotest_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST %', lf_ops.lf_puente_autotest_v1();
  PERFORM lf_ops.lf_legado_sombra_v1(true);
  SELECT max(corrida) INTO v_c FROM lf_ops.lf_legado_alcance;
  SELECT count(*), count(*) FILTER (WHERE cardinality(sin_explicar) > 0) INTO v_total, v_sinexp FROM lf_ops.lf_legado_sombra WHERE corrida = v_c;
  IF v_total <> (SELECT count(*) FROM lf_ops.reglas) OR (SELECT count(*) FROM lf_ops.lf_legado_alcance WHERE corrida = v_c) <> v_total
    THEN RAISE EXCEPTION 'NUCLEO_SOMBRA_INCOMPLETA: %', v_total; END IF;
  RAISE NOTICE 'NUCLEO_SOMBRA: % reglas, % sin explicar', v_total, v_sinexp;
  IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo LIKE 'ZZT%') OR EXISTS (SELECT 1 FROM lf_ops.lf_legado_sombra_errores) THEN
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_DEJO_DATOS';
  END IF;
END $run$;
COMMIT;
