-- Núcleo de reglas, bloque B (F1 completo, instancia LF).
-- Tablas: reglas (identidad), versiones (inmutables, con vigencia), aplicaciones (regla -> nodo, con modo),
-- relaciones entre reglas, registro de parámetros. Resolvedor nucleo_reglas_efectivas_v1(nodo, fecha).
-- Autopruebas al final: 10 escenarios sobre el árbol real; se deshacen solos y, si uno falla, se revierte todo.
BEGIN;

CREATE TABLE lf_ops.nucleo_reglas (
  codigo text PRIMARY KEY,
  clave text NOT NULL,
  familia text NOT NULL REFERENCES lf_ops.nucleo_familias(codigo),
  naturaleza text NOT NULL,
  estado text NOT NULL DEFAULT 'CANDIDATA',
  regla_legacy_id integer UNIQUE REFERENCES lf_ops.reglas(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_reglas_codigo_formato CHECK (codigo ~ '^[A-Z][A-Z0-9_.-]{2,80}$'),
  CONSTRAINT nucleo_reglas_clave_formato CHECK (clave ~ '^[a-z][a-z0-9_]{2,80}$'),
  CONSTRAINT nucleo_reglas_naturaleza_valida CHECK (naturaleza IN ('CONDUCTA','DEFINICION')),
  CONSTRAINT nucleo_reglas_estado_valido CHECK (estado IN ('BORRADOR','CANDIDATA','VIGENTE','DEPRECADA','RETIRADA'))
);
COMMENT ON TABLE lf_ops.nucleo_reglas IS 'Identidad estable de cada regla del núcleo. clave = concepto que gobierna (dos reglas con la misma clave se especializan o compiten).';

CREATE TABLE lf_ops.nucleo_regla_versiones (
  regla text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo),
  version integer NOT NULL,
  titulo text NOT NULL,
  descripcion text NOT NULL,
  condicion jsonb,
  efecto text,
  autoridad text NOT NULL,
  publicada_desde timestamptz NOT NULL,
  exigible_desde timestamptz NOT NULL,
  vigente_hasta timestamptz,
  hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (regla, version),
  CONSTRAINT nucleo_versiones_version_positiva CHECK (version >= 1),
  CONSTRAINT nucleo_versiones_descripcion_minima CHECK (length(btrim(descripcion)) >= 20),
  CONSTRAINT nucleo_versiones_exigible_tras_publicacion CHECK (exigible_desde >= publicada_desde),
  CONSTRAINT nucleo_versiones_intervalo_valido CHECK (vigente_hasta IS NULL OR vigente_hasta > publicada_desde)
);
COMMENT ON TABLE lf_ops.nucleo_regla_versiones IS 'Versiones inmutables. Evolucionar una regla = insertar una versión nueva; la anterior se cierra sola.';

CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_versiones_alta_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops AS $$
DECLARE v_prev record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('lf_ops.nucleo_regla_versiones:' || NEW.regla, 0));
  IF NEW.version IS NULL THEN
    SELECT COALESCE(max(version), 0) + 1 INTO NEW.version FROM lf_ops.nucleo_regla_versiones WHERE regla = NEW.regla;
  END IF;
  SELECT * INTO v_prev FROM lf_ops.nucleo_regla_versiones
   WHERE regla = NEW.regla AND vigente_hasta IS NULL ORDER BY version DESC LIMIT 1;
  IF FOUND THEN
    IF NEW.publicada_desde <= v_prev.publicada_desde THEN
      RAISE EXCEPTION 'NUCLEO_VERSION_FECHA_INVALIDA: la versión % debe publicarse después de la % de %', NEW.version, v_prev.version, NEW.regla;
    END IF;
    UPDATE lf_ops.nucleo_regla_versiones SET vigente_hasta = NEW.publicada_desde
     WHERE regla = NEW.regla AND version = v_prev.version;
  END IF;
  NEW.hash := encode(sha256(convert_to(concat_ws('|', NEW.regla, NEW.version, NEW.titulo, NEW.descripcion,
                 NEW.condicion::text, NEW.efecto, NEW.autoridad), 'UTF8')), 'hex');
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_versiones_alta_v1 BEFORE INSERT ON lf_ops.nucleo_regla_versiones
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_versiones_alta_v1();

CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_versiones_inmutables_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'NUCLEO_VERSION_INMUTABLE: no se borra la versión % de %', OLD.version, OLD.regla;
  END IF;
  IF OLD.vigente_hasta IS NULL AND NEW.vigente_hasta IS NOT NULL
     AND ROW(NEW.regla, NEW.version, NEW.titulo, NEW.descripcion, NEW.condicion, NEW.efecto, NEW.autoridad,
             NEW.publicada_desde, NEW.exigible_desde, NEW.hash)
         IS NOT DISTINCT FROM
         ROW(OLD.regla, OLD.version, OLD.titulo, OLD.descripcion, OLD.condicion, OLD.efecto, OLD.autoridad,
             OLD.publicada_desde, OLD.exigible_desde, OLD.hash) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'NUCLEO_VERSION_INMUTABLE: la versión % de % no se modifica; cree una versión nueva', OLD.version, OLD.regla;
END $$;
CREATE TRIGGER trg_nucleo_versiones_inmutables_v1 BEFORE UPDATE OR DELETE ON lf_ops.nucleo_regla_versiones
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_versiones_inmutables_v1();

CREATE TABLE lf_ops.nucleo_aplicaciones (
  regla text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo),
  nodo text NOT NULL REFERENCES lf_ops.nucleo_nodos(codigo),
  modo text NOT NULL DEFAULT 'HEREDA',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (regla, nodo),
  CONSTRAINT nucleo_aplicaciones_modo_valido CHECK (modo IN ('HEREDA','FIJA','SOLO_AQUI'))
);
COMMENT ON TABLE lf_ops.nucleo_aplicaciones IS 'Dónde se aplica cada regla. HEREDA baja a los descendientes; FIJA baja y no se puede especializar; SOLO_AQUI no se hereda.';

CREATE TABLE lf_ops.nucleo_relaciones (
  origen text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo),
  destino text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo),
  tipo text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (origen, destino, tipo),
  CONSTRAINT nucleo_relaciones_tipo_valido CHECK (tipo IN ('REFINA','SOBRESCRIBE','DEPENDE','CONFLICTA','REEMPLAZA')),
  CONSTRAINT nucleo_relaciones_no_reflexiva CHECK (origen <> destino)
);
CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_relaciones_sin_ciclo_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops AS $$
BEGIN
  IF NEW.tipo IN ('DEPENDE','REEMPLAZA') AND EXISTS (
    WITH RECURSIVE alcanza(r) AS (
      SELECT NEW.destino
      UNION
      SELECT x.destino FROM lf_ops.nucleo_relaciones x JOIN alcanza a ON x.origen = a.r WHERE x.tipo = NEW.tipo)
    SELECT 1 FROM alcanza WHERE r = NEW.origen) THEN
    RAISE EXCEPTION 'NUCLEO_RELACION_CICLO: % % % cerraría un ciclo', NEW.origen, NEW.tipo, NEW.destino;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_relaciones_sin_ciclo_v1 BEFORE INSERT OR UPDATE ON lf_ops.nucleo_relaciones
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_relaciones_sin_ciclo_v1();

CREATE TABLE lf_ops.nucleo_parametros (
  scope text NOT NULL,
  config_key text NOT NULL,
  hecho text REFERENCES lf_ops.nucleo_hechos(codigo),
  minimo numeric,
  maximo numeric,
  dueno text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, config_key),
  CONSTRAINT nucleo_parametros_rango_valido CHECK (minimo IS NULL OR maximo IS NULL OR minimo <= maximo)
);
COMMENT ON TABLE lf_ops.nucleo_parametros IS 'Metadatos de cada parámetro de public.lf_global_config: dato que compara, rango permitido y dueño. El valor sigue viviendo solo en lf_global_config.';
CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_parametros_existe_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = NEW.scope AND config_key = NEW.config_key) THEN
    RAISE EXCEPTION 'NUCLEO_PARAMETRO_INEXISTENTE: %.%', NEW.scope, NEW.config_key;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_parametros_existe_v1 BEFORE INSERT OR UPDATE OF scope, config_key ON lf_ops.nucleo_parametros
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_parametros_existe_v1();

-- Resolvedor
CREATE OR REPLACE FUNCTION lf_ops.nucleo_reglas_efectivas_v1(p_nodo text, p_fecha timestamptz DEFAULT now())
RETURNS TABLE (regla text, clave text, version integer, nodo_origen text, modo text, distancia integer, conflicto text)
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, lf_ops AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_nodos WHERE codigo = p_nodo) THEN
    RAISE EXCEPTION 'NUCLEO_NODO_INEXISTENTE: %', p_nodo;
  END IF;
  RETURN QUERY
  WITH RECURSIVE anc(nodo, d) AS (
    SELECT p_nodo, 0
    UNION ALL
    SELECT n.padre, anc.d + 1 FROM lf_ops.nucleo_nodos n JOIN anc ON n.codigo = anc.nodo WHERE n.padre IS NOT NULL),
  cand AS (
    SELECT r.codigo AS regla, r.clave, v.version, a.nodo, a.modo, anc.d
      FROM lf_ops.nucleo_aplicaciones a
      JOIN anc ON anc.nodo = a.nodo
      JOIN lf_ops.nucleo_reglas r ON r.codigo = a.regla AND r.estado = 'VIGENTE'
      JOIN lf_ops.nucleo_regla_versiones v ON v.regla = r.codigo
       AND v.publicada_desde <= p_fecha AND (v.vigente_hasta IS NULL OR v.vigente_hasta > p_fecha)
     WHERE a.modo <> 'SOLO_AQUI' OR anc.d = 0),
  fija AS (SELECT c.clave, max(c.d) AS d FROM cand c WHERE c.modo = 'FIJA' GROUP BY c.clave),
  elegido AS (
    SELECT c.clave, COALESCE(f.d, min(c.d)) AS d
      FROM cand c LEFT JOIN fija f ON f.clave = c.clave
     GROUP BY c.clave, f.d)
  SELECT c.regla, c.clave, c.version, c.nodo, c.modo, c.d,
         CASE
           WHEN (SELECT count(*) FROM cand x WHERE x.clave = c.clave AND x.d = c.d) > 1 THEN 'MISMO_NIVEL'
           WHEN c.modo = 'FIJA' AND EXISTS (SELECT 1 FROM cand x WHERE x.clave = c.clave AND x.d < c.d) THEN 'FIJA_IGNORA_ESPECIALIZACION'
         END
    FROM cand c JOIN elegido e ON e.clave = c.clave AND e.d = c.d
   WHERE NOT EXISTS (SELECT 1 FROM fija f WHERE f.clave = c.clave) OR c.modo = 'FIJA';
END $$;
COMMENT ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(text, timestamptz) IS
  'Reglas efectivas de un nodo en una fecha: la más específica gana, salvo una FIJA superior; SOLO_AQUI no se hereda; marca conflictos.';

-- Acceso
REVOKE ALL ON lf_ops.nucleo_reglas, lf_ops.nucleo_regla_versiones, lf_ops.nucleo_aplicaciones,
              lf_ops.nucleo_relaciones, lf_ops.nucleo_parametros FROM PUBLIC;
REVOKE ALL ON lf_ops.nucleo_reglas, lf_ops.nucleo_regla_versiones, lf_ops.nucleo_aplicaciones,
              lf_ops.nucleo_relaciones, lf_ops.nucleo_parametros FROM anon, authenticated;
ALTER TABLE lf_ops.nucleo_reglas ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_regla_versiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_aplicaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_relaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_parametros ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_reglas AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_regla_versiones AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_aplicaciones AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_relaciones AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_parametros AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(text, timestamptz) FROM anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(text, timestamptz) TO service_role; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(text, timestamptz) TO supabase_read_only_user; END IF;
END $g$;

-- Autopruebas (se deshacen solas; un fallo revierte toda la migración)
DO $autotest$
DECLARE
  t0 timestamptz := now();
  n integer; v_txt text; v_ok boolean;
  hoja text := (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'PANTALLA' AND padre IN
                  (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'MODULO' AND padre = 'B2B') ORDER BY codigo LIMIT 1);
  modulo text := (SELECT padre FROM lf_ops.nucleo_nodos WHERE codigo = (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'PANTALLA' AND padre IN
                  (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'MODULO' AND padre = 'B2B') ORDER BY codigo LIMIT 1));
BEGIN
  BEGIN
    IF hoja IS NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: no hay pantalla B2B en el árbol'; END IF;
    INSERT INTO lf_ops.nucleo_reglas(codigo, clave, familia, naturaleza, estado) VALUES
      ('ZZT-A','zzt_timeout','SESSION','CONDUCTA','VIGENTE'), ('ZZT-B','zzt_timeout','SESSION','CONDUCTA','VIGENTE'),
      ('ZZT-C','zzt_mfa','MFA_OTP_SSO','CONDUCTA','VIGENTE'), ('ZZT-D','zzt_mfa','MFA_OTP_SSO','CONDUCTA','VIGENTE'),
      ('ZZT-E','zzt_local','STATES','CONDUCTA','VIGENTE'), ('ZZT-F','zzt_cand','STATES','CONDUCTA','CANDIDATA'),
      ('ZZT-G','zzt_par','STATES','CONDUCTA','VIGENTE'), ('ZZT-H','zzt_par','STATES','CONDUCTA','VIGENTE');
    INSERT INTO lf_ops.nucleo_regla_versiones(regla, titulo, descripcion, autoridad, publicada_desde, exigible_desde)
    SELECT c, 'Autoprueba '||c, 'Regla de autoprueba del resolvedor del núcleo', 'AUTOTEST', t0 - interval '10 days', t0 - interval '10 days'
      FROM unnest(ARRAY['ZZT-A','ZZT-B','ZZT-C','ZZT-D','ZZT-E','ZZT-F','ZZT-G','ZZT-H']) c;
    INSERT INTO lf_ops.nucleo_aplicaciones(regla, nodo, modo) VALUES
      ('ZZT-A','B2B','HEREDA'), ('ZZT-C','GLOBAL','FIJA'), ('ZZT-D','B2B','HEREDA'),
      ('ZZT-E','B2B','SOLO_AQUI'), ('ZZT-F','B2B','HEREDA'), ('ZZT-G', modulo,'HEREDA'), ('ZZT-H', modulo,'HEREDA');

    -- T1 herencia
    SELECT string_agg(nodo_origen, ',') INTO v_txt FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_timeout';
    IF v_txt IS DISTINCT FROM 'B2B' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T1 herencia (%)', v_txt; END IF;
    -- T2 especialización
    INSERT INTO lf_ops.nucleo_aplicaciones VALUES ('ZZT-B', hoja, 'HEREDA');
    SELECT string_agg(regla, ',') INTO v_txt FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_timeout';
    IF v_txt IS DISTINCT FROM 'ZZT-B' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T2 especialización (%)', v_txt; END IF;
    -- T3 fija gana y marca conflicto
    SELECT string_agg(regla || ':' || coalesce(conflicto,'-'), ',') INTO v_txt FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_mfa';
    IF v_txt IS DISTINCT FROM 'ZZT-C:FIJA_IGNORA_ESPECIALIZACION' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T3 fija (%)', v_txt; END IF;
    -- T4 solo aquí
    SELECT count(*) INTO n FROM lf_ops.nucleo_reglas_efectivas_v1('B2B') WHERE clave = 'zzt_local';
    IF n <> 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T4a solo aquí en B2B (%)', n; END IF;
    SELECT count(*) INTO n FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_local';
    IF n <> 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T4b solo aquí heredada (%)', n; END IF;
    -- T5 vigencia por fecha y cierre automático
    INSERT INTO lf_ops.nucleo_regla_versiones(regla, titulo, descripcion, autoridad, publicada_desde, exigible_desde)
    VALUES ('ZZT-A','Autoprueba ZZT-A v2','Segunda versión de la regla de autoprueba','AUTOTEST', t0 - interval '1 day', t0);
    DELETE FROM lf_ops.nucleo_aplicaciones WHERE regla = 'ZZT-B';
    SELECT string_agg(version::text, ',') INTO v_txt FROM lf_ops.nucleo_reglas_efectivas_v1(hoja, t0 - interval '5 days') WHERE clave = 'zzt_timeout';
    IF v_txt IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T5a versión pasada (%)', v_txt; END IF;
    SELECT string_agg(version::text, ',') INTO v_txt FROM lf_ops.nucleo_reglas_efectivas_v1(hoja, t0) WHERE clave = 'zzt_timeout';
    IF v_txt IS DISTINCT FROM '2' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T5b versión vigente (%)', v_txt; END IF;
    SELECT (vigente_hasta = t0 - interval '1 day') INTO v_ok FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-A' AND version = 1;
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T5c cierre automático'; END IF;
    -- T6 inmutabilidad
    v_ok := false;
    BEGIN UPDATE lf_ops.nucleo_regla_versiones SET titulo = 'cambio' WHERE regla = 'ZZT-A' AND version = 1;
    EXCEPTION WHEN others THEN v_ok := SQLERRM LIKE 'NUCLEO_VERSION_INMUTABLE%'; END;
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T6a update permitido'; END IF;
    v_ok := false;
    BEGIN DELETE FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-A' AND version = 1;
    EXCEPTION WHEN others THEN v_ok := SQLERRM LIKE 'NUCLEO_VERSION_INMUTABLE%'; END;
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T6b delete permitido'; END IF;
    -- T7 ciclo de dependencias
    INSERT INTO lf_ops.nucleo_relaciones VALUES ('ZZT-A','ZZT-C','DEPENDE');
    v_ok := false;
    BEGIN INSERT INTO lf_ops.nucleo_relaciones VALUES ('ZZT-C','ZZT-A','DEPENDE');
    EXCEPTION WHEN others THEN v_ok := SQLERRM LIKE 'NUCLEO_RELACION_CICLO%'; END;
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T7 ciclo aceptado'; END IF;
    -- T8 nodo inexistente
    v_ok := false;
    BEGIN PERFORM * FROM lf_ops.nucleo_reglas_efectivas_v1('NO-EXISTE');
    EXCEPTION WHEN others THEN v_ok := SQLERRM LIKE 'NUCLEO_NODO_INEXISTENTE%'; END;
    IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T8 nodo inexistente'; END IF;
    -- T9 candidata excluida
    SELECT count(*) INTO n FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_cand';
    IF n <> 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T9 candidata efectiva'; END IF;
    -- T10 conflicto en el mismo nivel
    SELECT count(*) INTO n FROM lf_ops.nucleo_reglas_efectivas_v1(hoja) WHERE clave = 'zzt_par' AND conflicto = 'MISMO_NIVEL';
    IF n <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T10 mismo nivel (%)', n; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'NUCLEO_AUTOTEST: 10/10 escenarios OK (datos de prueba deshechos)';
END $autotest$;
COMMIT;
