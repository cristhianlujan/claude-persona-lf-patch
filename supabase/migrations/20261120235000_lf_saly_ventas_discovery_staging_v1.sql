-- SALY Ventas | Lote 25 | Ingesta de fuentes publicas con RUC opcional.
-- CANDIDATO: requiere PR, PG17/ROLLBACK, Merge Train, readback; NO ejecutar directo.
-- Independiente del maestro saly.ventas_empresas (aun no desplegado).
-- SUPERSEDE el CREATE TABLE de hallazgos propuesto en L20, no desplegado.
-- L27: contrato source_id/connector_id/substep_code/batch/query_hash, sin claims de FK no existente.
-- Sin merges ni writer hasta alinear Step10/L20 y validar RLS/PG17.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO') <> 1
 THEN RAISE EXCEPTION 'SALY_VENTAS_PROJECT_NOT_UNIQUE_ACTIVE'; END IF;
 IF to_regclass('saly.ventas_discovery_ingestas') IS NOT NULL
 OR to_regclass('saly.ventas_hallazgos') IS NOT NULL
 OR to_regclass('saly.ventas_unidades_operativas') IS NOT NULL
 THEN RAISE EXCEPTION 'SALY_VENTAS_STAGING_ALREADY_EXISTS'; END IF;
END $pre$;

CREATE TABLE saly.ventas_discovery_ingestas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 -- Source lineage uses stable identifiers from PE-SALY-DISCOVERY-2026-11-V0.2.
 -- FKs to L20 RUN/SOURCE/QUERY tables are prohibited until their DDL exists.
 catalog_version text NOT NULL CHECK (length(btrim(catalog_version)) > 0),
 source_id text NOT NULL CHECK (length(btrim(source_id)) > 0),
 connector_id text NOT NULL CHECK (length(btrim(connector_id)) > 0),
 substep_code text NOT NULL CHECK (substep_code ~ '^1[2-7]\\.[0-9]{2}
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
 CONSTRAINT ventas_ingesta_derechos_con_evidencia CHECK (
   NOT derechos_verificados OR
   (archivo_sha256 IS NOT NULL AND filas_reportadas IS NOT NULL
    AND estado IN ('PARCIAL','VALIDADA'))
 ),
 UNIQUE(id,derechos_verificados),
 UNIQUE(source_id,source_version,archivo_sha256)
);
COMMENT ON TABLE saly.ventas_discovery_ingestas IS
'Ingesta auditada de una version concreta de recurso. La licencia verificable no equivale a permiso de contacto.';

-- CANONICAL HALLAZGOS: replaces L20 proposal; do NOT deploy its old
-- DDL unchanged. Add RUN/connector FKs after L20 execution tables are governed.
CREATE TABLE saly.ventas_hallazgos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ingesta_id uuid NOT NULL,
 derechos_verificados boolean NOT NULL DEFAULT true CHECK (derechos_verificados),
 fila_origen integer NOT NULL CHECK (fila_origen > 0),
 external_ref text NOT NULL CHECK (length(btrim(external_ref)) > 0),
 tipo text NOT NULL DEFAULT 'POR_CLASIFICAR'
  CHECK (tipo IN ('POR_CLASIFICAR','EMPRESA','ENTIDAD_PUBLICA','DEPENDENCIA','ESTABLECIMIENTO','OTRO')),
 nombre_provisional text NOT NULL CHECK (length(btrim(nombre_provisional)) > 0),
 ruc_literal text,
 ruc_candidato text CHECK (ruc_candidato IS NULL OR ruc_candidato ~ '^[0-9]{11}$'),
 ubigeo_candidato text CHECK (ubigeo_candidato IS NULL OR ubigeo_candidato ~ '^[0-9]{6}$'),
 evidencia_ref text NOT NULL CHECK (length(btrim(evidencia_ref)) > 0),
 estado_identidad text NOT NULL DEFAULT 'PENDIENTE'
  CHECK (estado_identidad IN ('PENDIENTE','SIN_RUC','DISCREPANCIA','VALIDADA','DESCARTADA')),
 creada_en timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (ingesta_id,derechos_verificados)
  REFERENCES saly.ventas_discovery_ingestas(id,derechos_verificados) ON DELETE RESTRICT,
 UNIQUE(ingesta_id,fila_origen),
 UNIQUE(ingesta_id,external_ref)
);
CREATE INDEX ventas_hallazgos_ruc_idx ON saly.ventas_hallazgos(ruc_candidato);
CREATE INDEX ventas_hallazgos_ubigeo_idx ON saly.ventas_hallazgos(ubigeo_candidato);
COMMENT ON TABLE saly.ventas_hallazgos IS
'Fuente canonica de hallazgos Step 10; RUC opcional y no unico; integracion RUN/conector + Step 20 pendiente. No contactar.';

CREATE TABLE saly.ventas_unidades_operativas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 registro_id uuid NOT NULL UNIQUE REFERENCES saly.ventas_hallazgos(id) ON DELETE RESTRICT,
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
ALTER TABLE saly.ventas_hallazgos ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_unidades_operativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON saly.ventas_discovery_ingestas,
 saly.ventas_hallazgos,saly.ventas_unidades_operativas
 FROM PUBLIC,anon,authenticated;
-- Sin grants a runtime: necesita operacion gobernada. Sin seed ni datos personales.
COMMIT;
),
 scope_key text NOT NULL DEFAULT 'GENERAL' CHECK (length(btrim(scope_key)) > 0),
 batch_key text NOT NULL CHECK (length(btrim(batch_key)) > 0),
 query_hash text NOT NULL CHECK (query_hash ~ '^[0-9a-f]{64}
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
 CONSTRAINT ventas_ingesta_derechos_con_evidencia CHECK (
   NOT derechos_verificados OR
   (archivo_sha256 IS NOT NULL AND filas_reportadas IS NOT NULL
    AND estado IN ('PARCIAL','VALIDADA'))
 ),
 UNIQUE(id,derechos_verificados),
 UNIQUE(source_code,source_version,archivo_sha256)
);
COMMENT ON TABLE saly.ventas_discovery_ingestas IS
'Ingesta auditada de una version concreta de recurso. La licencia verificable no equivale a permiso de contacto.';

-- CANONICAL HALLAZGOS: replaces L20 proposal; do NOT deploy its old
-- DDL unchanged. Add RUN/connector FKs after L20 execution tables are governed.
CREATE TABLE saly.ventas_hallazgos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ingesta_id uuid NOT NULL,
 derechos_verificados boolean NOT NULL DEFAULT true CHECK (derechos_verificados),
 fila_origen integer NOT NULL CHECK (fila_origen > 0),
 external_ref text NOT NULL CHECK (length(btrim(external_ref)) > 0),
 tipo text NOT NULL DEFAULT 'POR_CLASIFICAR'
  CHECK (tipo IN ('POR_CLASIFICAR','EMPRESA','ENTIDAD_PUBLICA','DEPENDENCIA','ESTABLECIMIENTO','OTRO')),
 nombre_provisional text NOT NULL CHECK (length(btrim(nombre_provisional)) > 0),
 ruc_literal text,
 ruc_candidato text CHECK (ruc_candidato IS NULL OR ruc_candidato ~ '^[0-9]{11}$'),
 ubigeo_candidato text CHECK (ubigeo_candidato IS NULL OR ubigeo_candidato ~ '^[0-9]{6}$'),
 evidencia_ref text NOT NULL CHECK (length(btrim(evidencia_ref)) > 0),
 estado_identidad text NOT NULL DEFAULT 'PENDIENTE'
  CHECK (estado_identidad IN ('PENDIENTE','SIN_RUC','DISCREPANCIA','VALIDADA','DESCARTADA')),
 creada_en timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (ingesta_id,derechos_verificados)
  REFERENCES saly.ventas_discovery_ingestas(id,derechos_verificados) ON DELETE RESTRICT,
 UNIQUE(ingesta_id,fila_origen),
 UNIQUE(ingesta_id,external_ref)
);
CREATE INDEX ventas_hallazgos_ruc_idx ON saly.ventas_hallazgos(ruc_candidato);
CREATE INDEX ventas_hallazgos_ubigeo_idx ON saly.ventas_hallazgos(ubigeo_candidato);
COMMENT ON TABLE saly.ventas_hallazgos IS
'Fuente canonica de hallazgos Step 10; RUC opcional y no unico; integracion RUN/conector + Step 20 pendiente. No contactar.';

CREATE TABLE saly.ventas_unidades_operativas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 registro_id uuid NOT NULL UNIQUE REFERENCES saly.ventas_hallazgos(id) ON DELETE RESTRICT,
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
ALTER TABLE saly.ventas_hallazgos ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_unidades_operativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON saly.ventas_discovery_ingestas,
 saly.ventas_hallazgos,saly.ventas_unidades_operativas
 FROM PUBLIC,anon,authenticated;
-- Sin grants a runtime: necesita operacion gobernada. Sin seed ni datos personales.
COMMIT;
),
 consulta_evidencia_ref text NOT NULL CHECK (length(btrim(consulta_evidencia_ref)) > 0),
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
 CONSTRAINT ventas_ingesta_derechos_con_evidencia CHECK (
   NOT derechos_verificados OR
   (archivo_sha256 IS NOT NULL AND filas_reportadas IS NOT NULL
    AND estado IN ('PARCIAL','VALIDADA'))
 ),
 UNIQUE(id,derechos_verificados),
 UNIQUE(source_code,source_version,archivo_sha256)
);
COMMENT ON TABLE saly.ventas_discovery_ingestas IS
'Ingesta auditada de una version concreta de recurso. La licencia verificable no equivale a permiso de contacto.';

-- CANONICAL HALLAZGOS: replaces L20 proposal; do NOT deploy its old
-- DDL unchanged. Add RUN/connector FKs after L20 execution tables are governed.
CREATE TABLE saly.ventas_hallazgos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ingesta_id uuid NOT NULL,
 derechos_verificados boolean NOT NULL DEFAULT true CHECK (derechos_verificados),
 fila_origen integer NOT NULL CHECK (fila_origen > 0),
 external_ref text NOT NULL CHECK (length(btrim(external_ref)) > 0),
 tipo text NOT NULL DEFAULT 'POR_CLASIFICAR'
  CHECK (tipo IN ('POR_CLASIFICAR','EMPRESA','ENTIDAD_PUBLICA','DEPENDENCIA','ESTABLECIMIENTO','OTRO')),
 nombre_provisional text NOT NULL CHECK (length(btrim(nombre_provisional)) > 0),
 ruc_literal text,
 ruc_candidato text CHECK (ruc_candidato IS NULL OR ruc_candidato ~ '^[0-9]{11}$'),
 ubigeo_candidato text CHECK (ubigeo_candidato IS NULL OR ubigeo_candidato ~ '^[0-9]{6}$'),
 evidencia_ref text NOT NULL CHECK (length(btrim(evidencia_ref)) > 0),
 estado_identidad text NOT NULL DEFAULT 'PENDIENTE'
  CHECK (estado_identidad IN ('PENDIENTE','SIN_RUC','DISCREPANCIA','VALIDADA','DESCARTADA')),
 creada_en timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (ingesta_id,derechos_verificados)
  REFERENCES saly.ventas_discovery_ingestas(id,derechos_verificados) ON DELETE RESTRICT,
 UNIQUE(ingesta_id,fila_origen),
 UNIQUE(ingesta_id,external_ref)
);
CREATE INDEX ventas_hallazgos_ruc_idx ON saly.ventas_hallazgos(ruc_candidato);
CREATE INDEX ventas_hallazgos_ubigeo_idx ON saly.ventas_hallazgos(ubigeo_candidato);
COMMENT ON TABLE saly.ventas_hallazgos IS
'Fuente canonica de hallazgos Step 10; RUC opcional y no unico; integracion RUN/conector + Step 20 pendiente. No contactar.';

CREATE TABLE saly.ventas_unidades_operativas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 registro_id uuid NOT NULL UNIQUE REFERENCES saly.ventas_hallazgos(id) ON DELETE RESTRICT,
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
ALTER TABLE saly.ventas_hallazgos ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_unidades_operativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON saly.ventas_discovery_ingestas,
 saly.ventas_hallazgos,saly.ventas_unidades_operativas
 FROM PUBLIC,anon,authenticated;
-- Sin grants a runtime: necesita operacion gobernada. Sin seed ni datos personales.
COMMIT;
