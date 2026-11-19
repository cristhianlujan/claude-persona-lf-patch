-- IG Chat 13: historial automático para reglas (sin modificar filas ni guard de promoción).
-- La fila corriente sigue en lf_ops.reglas; el historial se consulta por lf_ops.v_reglas_historial.
CREATE TABLE lf_ops.reglas_versiones (
  codigo text NOT NULL,
  version integer NOT NULL,
  categoria text NOT NULL,
  titulo text NOT NULL,
  descripcion text NOT NULL,
  razon text,
  valor_config jsonb,
  es_transversal boolean NOT NULL,
  estado text NOT NULL,
  origen text,
  motivo text NOT NULL,
  cambiado_por text NOT NULL,
  vigente_desde timestamptz NOT NULL,
  vigente_hasta timestamptz,
  CONSTRAINT reglas_versiones_pkey PRIMARY KEY (codigo, version),
  CONSTRAINT reglas_versiones_version_positive CHECK (version >= 1),
  CONSTRAINT reglas_versiones_interval_valid CHECK (
    vigente_hasta IS NULL OR vigente_hasta >= vigente_desde
  )
);

COMMENT ON TABLE lf_ops.reglas_versiones IS
  'Para la regla actual usar lf_ops.reglas; el historial esta en lf_ops.v_reglas_historial (consumo de Paulo, programador). Registra fotos anteriores; version consecutiva por codigo.';
REVOKE ALL ON TABLE lf_ops.reglas_versiones FROM PUBLIC;

-- Se permite version NULL al INSERT: el BEFORE INSERT asigna max(version)+1 por codigo.
-- La foto inicial usa version=1 explícita; las posteriores son automáticas.
CREATE OR REPLACE FUNCTION lf_ops.fn_reglas_versiones_numero_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, lf_ops
AS $$
BEGIN
  IF NEW.version IS NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('lf_ops.reglas_versiones:' || NEW.codigo, 0)
    );
    SELECT COALESCE(MAX(v.version), 0) + 1
      INTO NEW.version
      FROM lf_ops.reglas_versiones v
     WHERE v.codigo = NEW.codigo;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lf_reglas_versiones_numero_v1
BEFORE INSERT ON lf_ops.reglas_versiones
FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_reglas_versiones_numero_v1();

-- La version inicial queda abierta mientras su snapshot sea la fila actual.
-- Al primer cambio se cierra esa version sin duplicar su contenido;
-- a partir del segundo se inserta cada preimagen con version sucesiva.
CREATE OR REPLACE FUNCTION lf_ops.fn_reglas_historial_preimagen_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, lf_ops
AS $$
DECLARE
  v_ultima lf_ops.reglas_versiones%ROWTYPE;
  v_momento timestamptz;
  v_motivo text;
  v_actor text;
  v_inicio timestamptz;
BEGIN
  IF TG_OP = 'UPDATE' AND
     ROW(OLD.codigo, OLD.categoria, OLD.titulo, OLD.descripcion, OLD.razon,
         OLD.valor_config, OLD.es_transversal, OLD.estado, OLD.origen)
     IS NOT DISTINCT FROM
     ROW(NEW.codigo, NEW.categoria, NEW.titulo, NEW.descripcion, NEW.razon,
         NEW.valor_config, NEW.es_transversal, NEW.estado, NEW.origen)
  THEN
    RETURN NEW;
  END IF;

  v_momento := pg_catalog.clock_timestamp();
  v_motivo := COALESCE(NULLIF(pg_catalog.current_setting('lf.reglas_cambio_motivo', true), ''),
                       CASE WHEN TG_OP = 'DELETE' THEN 'DELETE_REGLA'
                            ELSE 'UPDATE_DE_FONDO' END);
  v_actor := COALESCE(NULLIF(pg_catalog.current_setting('lf.reglas_cambiado_por', true), ''),
                      SESSION_USER);

  SELECT * INTO v_ultima
    FROM lf_ops.reglas_versiones
   WHERE codigo = OLD.codigo
   ORDER BY version DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND AND v_ultima.vigente_hasta IS NULL THEN
    -- Inicial: la foto 1 ya contiene OLD. Solo cerrarla, sin version duplicada.
    UPDATE lf_ops.reglas_versiones
       SET vigente_hasta = GREATEST(v_momento, v_ultima.vigente_desde),
           motivo = v_motivo,
           cambiado_por = v_actor
     WHERE codigo = OLD.codigo AND version = v_ultima.version;
  ELSE
    v_inicio := CASE WHEN FOUND THEN v_ultima.vigente_hasta ELSE OLD.created_at END;
    INSERT INTO lf_ops.reglas_versiones (
      codigo, categoria, titulo, descripcion, razon, valor_config,
      es_transversal, estado, origen, motivo, cambiado_por, vigente_desde, vigente_hasta
    ) VALUES (
      OLD.codigo, OLD.categoria, OLD.titulo, OLD.descripcion, OLD.razon, OLD.valor_config,
      OLD.es_transversal, OLD.estado, OLD.origen, v_motivo, v_actor,
      COALESCE(v_inicio, OLD.created_at, v_momento),
      GREATEST(v_momento, COALESCE(v_inicio, OLD.created_at, v_momento))
    );
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

-- Backfill + activacion del guard histórico en UNA transacción y lock real.
-- Cubre writes concurrentes de otros chats: ninguna fila cambia entre foto y triggers.
DO $install$
BEGIN
  LOCK TABLE lf_ops.reglas IN SHARE ROW EXCLUSIVE MODE;
  INSERT INTO lf_ops.reglas_versiones (
    codigo, version, categoria, titulo, descripcion, razon, valor_config,
    es_transversal, estado, origen, motivo, cambiado_por, vigente_desde, vigente_hasta
  )
  SELECT r.codigo, 1, r.categoria, r.titulo, r.descripcion, r.razon, r.valor_config,
         r.es_transversal, r.estado, r.origen, 'FOTO_INICIAL',
         COALESCE(NULLIF(r.created_by, ''), 'MIGRACION_INICIAL'),
         r.created_at, NULL
    FROM lf_ops.reglas r;
  EXECUTE 'CREATE TRIGGER trg_lf_reglas_historial_update_v1
    BEFORE UPDATE ON lf_ops.reglas
    FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_reglas_historial_preimagen_v1()';
  EXECUTE 'CREATE TRIGGER trg_lf_reglas_historial_delete_v1
    BEFORE DELETE ON lf_ops.reglas
    FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_reglas_historial_preimagen_v1()';
END;
$install$;

CREATE VIEW lf_ops.v_reglas_historial AS
SELECT h.codigo, h.version, h.categoria, h.titulo, h.descripcion,
       h.razon, h.valor_config, h.es_transversal, h.estado, h.origen,
       h.motivo, h.cambiado_por, h.vigente_desde, h.vigente_hasta,
       false AS es_actual
  FROM lf_ops.reglas_versiones h
 WHERE h.vigente_hasta IS NOT NULL
    OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas r WHERE r.codigo = h.codigo)
UNION ALL
SELECT r.codigo,
       CASE WHEN h.version IS NULL THEN 1
            WHEN h.vigente_hasta IS NULL THEN h.version
            ELSE h.version + 1 END AS version,
       r.categoria, r.titulo, r.descripcion, r.razon, r.valor_config,
       r.es_transversal, r.estado, r.origen,
       CASE WHEN h.vigente_hasta IS NULL THEN h.motivo
            ELSE COALESCE(h.motivo, 'CREACION_REGLA') END,
       CASE WHEN h.version IS NULL THEN COALESCE(NULLIF(r.created_by,''), 'CREACION_REGLA')
            ELSE h.cambiado_por END,
       CASE WHEN h.version IS NULL OR h.vigente_hasta IS NULL THEN r.created_at
            ELSE h.vigente_hasta END,
       NULL::timestamptz AS vigente_hasta,
       true AS es_actual
  FROM lf_ops.reglas r
  LEFT JOIN LATERAL (
    SELECT v.version, v.vigente_hasta, v.motivo, v.cambiado_por
      FROM lf_ops.reglas_versiones v
     WHERE v.codigo = r.codigo
     ORDER BY v.version DESC
     LIMIT 1
  ) h ON true;

COMMENT ON VIEW lf_ops.v_reglas_historial IS
  'Para la regla actual usar lf_ops.reglas; el historial esta en lf_ops.v_reglas_historial (lo consume Paulo, el programador). es_actual=true identifica la version vigente de la fila.';
REVOKE ALL ON TABLE lf_ops.v_reglas_historial FROM PUBLIC;
GRANT USAGE ON SCHEMA lf_ops TO service_role;
GRANT SELECT ON lf_ops.v_reglas_historial TO service_role;

-- Readback invariantes de la foto inicial; aborta el despliegue si la base difiere.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM lf_ops.reglas r
    LEFT JOIN lf_ops.reglas_versiones v ON v.codigo=r.codigo AND v.version=1
    WHERE v.codigo IS NULL OR v.estado IS DISTINCT FROM r.estado
      OR v.titulo IS DISTINCT FROM r.titulo
      OR v.descripcion IS DISTINCT FROM r.descripcion
      OR v.valor_config IS DISTINCT FROM r.valor_config
  ) OR EXISTS (
    SELECT 1 FROM lf_ops.reglas_versiones v
    WHERE v.version <> 1 OR v.vigente_hasta IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'LF_IG_REGLAS_HISTORIAL_INITIAL_BACKFILL_MISMATCH';
  END IF;
END;
$$;
