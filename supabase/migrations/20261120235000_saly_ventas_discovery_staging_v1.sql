-- SALY Ventas | Lote 25 | Ingesta de fuentes publicas con RUC opcional.
-- CANDIDATO: requiere PR, PG17/ROLLBACK, Merge Train, readback; NO ejecutar directo.
-- Independiente del maestro saly.ventas_empresas (aun no desplegado).
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO') <> 1
 THEN RAISE EXCEPTION 'SALY_VENTAS_PROJECT_NOT_UNIQUE_ACTIVE'; END IF;
 IF to_regclass('saly.ventas_discovery_ingestas') IS NOT NULL
 OR to_regclass('saly.ventas_discovery_registros') IS NOT NULL
 OR to_regclass('saly.ventas_unidades_operativas') IS NOT NULL
 THEN RAISE EXCEPTION 'SALY_VENTAS_STAGING_ALREADY_EXISTS'; END IF;
END $pre$;

CREATE TABLE saly.ventas_discovery_ingestas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source_code text NOT NULL CHECK (length(btrim(source_code)) > 0),
 source_version text NOT NULL CHECK (length(btrim(source_version)) > 0),
 recurso_url text NOT NULL CHECK (recurso_url ~ '^https://'),
 licencia_codigo text NOT NULL CHECK (length(btrim(licencia_codigo)) > 0),
 atribucion text NOT NULL CHECK (length(btrim(atribucion)) > 0),
 comprobacion_licencia_url text NOT NULL CHECK (comprobacion_licencia_url ~ '^https://'),
 derechos_verificados boolean NOT NULL DEFAULT false,
 archivo_sha256 text CHECK (archivo_sha256 IS NULL OR archivo_sha256 ~ '^[0-9a-f]{64}$'),
 estado text NOT NULL DEFAULT 'PREPARADA'
  CHECK (estado IN ('PREPARADA','VALIDADA','PARCIAL','RECHAZADA')),
 filas_reportadas integer CHECK (filas_reportadas IS NULL OR filas_reportadas >= 0),
 run_ref text NOT NULL CHECK (length(btrim(run_ref)) > 0),
 creada_en timestamptz NOT NULL DEFAULT now(),
 actualizada_en timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT ventas_ingesta_valida_gate CHECK (
   estado <> 'VALIDADA' OR
   (derechos_verificados AND archivo_sha256 IS NOT NULL AND filas_reportadas IS NOT NULL)
 ),
 UNIQUE(id,derechos_verificados),
 UNIQUE(source_code,source_version,archivo_sha256)
);
COMMENT ON TABLE saly.ventas_discovery_ingestas IS
'Ingesta auditada de una version concreta de recurso. La licencia verificable no equivale a permiso de contacto.';

CREATE TABLE saly.ventas_discovery_registros (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ingesta_id uuid NOT NULL,
 derechos_verificados boolean NOT NULL DEFAULT true CHECK (derechos_verificados),
 fila_origen integer NOT NULL CHECK (fila_origen > 0),
 nombre_literal text NOT NULL CHECK (length(btrim(nombre_literal)) > 0),
 ruc_literal text,
 ruc_candidato text CHECK (ruc_candidato IS NULL OR ruc_candidato ~ '^[0-9]{11}$'),
 ubigeo_candidato text CHECK (ubigeo_candidato IS NULL OR ubigeo_candidato ~ '^[0-9]{6}$'),
 clase_registro text NOT NULL DEFAULT 'POR_CLASIFICAR'
  CHECK (clase_registro IN ('POR_CLASIFICAR','ENTIDAD_PUBLICA','DEPENDENCIA','ESTABLECIMIENTO','OTRO')),
 estado_identidad text NOT NULL DEFAULT 'PENDIENTE'
  CHECK (estado_identidad IN ('PENDIENTE','SIN_RUC','DISCREPANCIA','VALIDADA','DESCARTADA')),
 creada_en timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (ingesta_id,derechos_verificados)
  REFERENCES saly.ventas_discovery_ingestas(id,derechos_verificados) ON DELETE RESTRICT,
 UNIQUE(ingesta_id,fila_origen)
);
CREATE INDEX ventas_disc_registros_ruc_idx ON saly.ventas_discovery_registros(ruc_candidato);
CREATE INDEX ventas_disc_registros_ubigeo_idx ON saly.ventas_discovery_registros(ubigeo_candidato);
COMMENT ON TABLE saly.ventas_discovery_registros IS
'Filas originales publicas sin PII: RUC opcional; duplicados de RUC permitidos para conservar la evidencia de origen.';

CREATE TABLE saly.ventas_unidades_operativas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 registro_id uuid NOT NULL UNIQUE REFERENCES saly.ventas_discovery_registros(id) ON DELETE RESTRICT,
 unidad_padre_id uuid REFERENCES saly.ventas_unidades_operativas(id) ON DELETE RESTRICT,
 nombre_unidad text NOT NULL CHECK (length(btrim(nombre_unidad)) > 0),
 tipo_unidad text NOT NULL DEFAULT 'POR_CLASIFICAR'
  CHECK (tipo_unidad IN ('POR_CLASIFICAR','ENTIDAD_PUBLICA','MUNICIPALIDAD','DIRIS','DEPENDENCIA','ESTABLECIMIENTO','OTRA')),
 estado_vinculacion text NOT NULL DEFAULT 'PENDIENTE'
  CHECK (estado_vinculacion IN ('PENDIENTE','VALIDACION_RUC','VALIDADA','DISCREPANCIA')),
 creada_en timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT ventas_unidad_no_auto_padre CHECK (unidad_padre_id IS NULL OR unidad_padre_id <> id)
);
COMMENT ON TABLE saly.ventas_unidades_operativas IS
'Unidades operativas separadas del futuro maestro por RUC; el vinculo juridico se crea solo tras Step 20 validado.';

ALTER TABLE saly.ventas_discovery_ingestas ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_registros ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_unidades_operativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON saly.ventas_discovery_ingestas,
 saly.ventas_discovery_registros,saly.ventas_unidades_operativas
 FROM PUBLIC,anon,authenticated;
-- Sin grants a runtime: necesita operacion gobernada. Sin seed ni datos personales.
COMMIT;
