-- SALY Ventas | Lote 25 | Ingesta de fuentes publicas con RUC opcional.
-- CANDIDATO: requiere PR, PG17/ROLLBACK, Merge Train, readback; NO ejecutar directo.
-- Independiente del maestro saly.ventas_empresas (aun no desplegado).
-- SUPERSEDE el CREATE TABLE de hallazgos propuesto en L20, no desplegado.
-- L27: catalog/source/connector/substep/batch/query lineage; L20 FKs pending.
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
 -- Stable IDs from frozen Step10 catalog PE-SALY-DISCOVERY-2026-11-V0.2.
 -- L20 foreign keys are not created until those RUN/source/consulta tables exist.
 catalog_version text NOT NULL CHECK (length(btrim(catalog_version)) > 0),
 source_id text NOT NULL CHECK (length(btrim(source_id)) > 0),
 connector_id text NOT NULL CHECK (length(btrim(connector_id)) > 0),
 substep_code text NOT NULL CHECK (substep_code ~ '^1[2-7]\.[0-9]{2}$'),
 scope_key text NOT NULL DEFAULT 'GENERAL' CHECK (length(btrim(scope_key)) > 0),
 batch_key text NOT NULL CHECK (length(btrim(batch_key)) > 0),
 query_hash text NOT NULL CHECK (query_hash ~ '^[0-9a-f]{64}$'),
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
 -- Same file is allowed in different RUNs; repeated exact batch in same RUN is not.
 UNIQUE(run_ref,source_id,source_version,scope_key,batch_key,query_hash,archivo_sha256)
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
-- L30: user-authorized actual Supabase, via Merge Train only.
-- Exact original functional fixture in a PL/pgSQL subtransaction. No external effects.
-- Unexpected SQLSTATEs propagate and abort the migration; only the sentinel is caught.
DO $saly_l27_fixture$
DECLARE
 v_batch uuid;
 v_hallazgo uuid;
 v_duplicate uuid;
 v_repeated_run uuid;
 v_forbidden boolean;
BEGIN
 BEGIN
 IF (SELECT count(*) FROM pg_tables WHERE schemaname='saly' AND tablename IN
 ('ventas_discovery_ingestas','ventas_hallazgos','ventas_unidades_operativas')
 AND rowsecurity) <> 3
 THEN RAISE EXCEPTION 'RLS_MISSING'; END IF;

 IF has_table_privilege('anon','saly.ventas_hallazgos','INSERT')
 OR has_table_privilege('authenticated','saly.ventas_hallazgos','SELECT')
 THEN RAISE EXCEPTION 'UNEXPECTED_RUNTIME_GRANT'; END IF;

 INSERT INTO saly.ventas_discovery_ingestas
 (catalog_version,source_id,connector_id,substep_code,scope_key,
  batch_key,query_hash,consulta_evidencia_ref,
  source_version,recurso_url,licencia_codigo,atribucion,
  comprobacion_licencia_url,run_ref)
 VALUES('PE-SALY-DISCOVERY-2026-11-V0.2','PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA',
 'PTE-2026-08-B0001',repeat('b',64),'fixture://PG17-source-receipt',
 '2026-08','https://www.datosabiertos.gob.pe/example.csv',
 'ODC-BY','PTE / PNDA','https://www.datosabiertos.gob.pe/example-dataset',
 'test-PG17-ROLLBACK')
 RETURNING id INTO v_batch;

 IF NOT EXISTS(
   SELECT 1 FROM saly.ventas_discovery_ingestas
   WHERE id=v_batch
   AND catalog_version='PE-SALY-DISCOVERY-2026-11-V0.2'
   AND source_id='PE-PTE' AND connector_id='SALY-U07-S13-C03'
   AND substep_code='13.03' AND scope_key='LIMA_ICA'
   AND batch_key='PTE-2026-08-B0001' AND query_hash=repeat('b',64)
   AND run_ref='test-PG17-ROLLBACK'
 )
 THEN RAISE EXCEPTION 'STEP10_SOURCE_RUN_QUERY_LINEAGE_MISMATCH'; END IF;

 v_forbidden:=false;
 BEGIN
   INSERT INTO saly.ventas_discovery_ingestas
   (catalog_version,source_id,connector_id,substep_code,batch_key,
    query_hash,consulta_evidencia_ref,source_version,recurso_url,
    licencia_codigo,atribucion,comprobacion_licencia_url,run_ref)
   VALUES ('PE-SALY-DISCOVERY-2026-11-V0.2','PE-PTE','SALY-U07-S13-C03',
    '13.3','BAD-SUBSTEP',repeat('c',64),'fixture://invalid',
    'bad-version','https://example.org/bad','ODC-BY','sample',
    'https://example.org/lic','test-PG17-ROLLBACK');
 EXCEPTION WHEN check_violation THEN v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'INVALID_SUBSTEP_ACCEPTED'; END IF;

 v_forbidden:=false;
 BEGIN
   INSERT INTO saly.ventas_discovery_ingestas
   (catalog_version,source_id,connector_id,substep_code,batch_key,
    query_hash,consulta_evidencia_ref,source_version,recurso_url,
    licencia_codigo,atribucion,comprobacion_licencia_url,run_ref)
   VALUES ('PE-SALY-DISCOVERY-2026-11-V0.2','PE-PTE','SALY-U07-S13-C03',
    '13.03','BAD-HASH','not-hex','fixture://invalid',
    'bad-version2','https://example.org/bad','ODC-BY','sample',
    'https://example.org/lic','test-PG17-ROLLBACK');
 EXCEPTION WHEN check_violation THEN v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'INVALID_QUERY_HASH_ACCEPTED'; END IF;

 v_forbidden := false;
 BEGIN
  INSERT INTO saly.ventas_hallazgos
  (ingesta_id,fila_origen,external_ref,nombre_provisional,evidencia_ref)
  VALUES(v_batch,1,'1','Municipalidad de prueba','test-raw-1');
 EXCEPTION WHEN foreign_key_violation OR check_violation THEN
  v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'BYPASS_UNVERIFIED_RIGHTS'; END IF;

 UPDATE saly.ventas_discovery_ingestas
 SET derechos_verificados=true, archivo_sha256=repeat('a',64),
     filas_reportadas=3, estado='PARCIAL'
 WHERE id=v_batch;

 -- Exact same source/batch/file/run must be rejected, independently of URL.
 v_forbidden:=false;
 BEGIN
  INSERT INTO saly.ventas_discovery_ingestas
  (catalog_version,source_id,connector_id,substep_code,scope_key,
   batch_key,query_hash,consulta_evidencia_ref,source_version,recurso_url,
   licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
   derechos_verificados,archivo_sha256,filas_reportadas,estado)
  SELECT catalog_version,source_id,connector_id,substep_code,scope_key,
   batch_key,query_hash,consulta_evidencia_ref,source_version,recurso_url,
   licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
   derechos_verificados,archivo_sha256,filas_reportadas,estado
  FROM saly.ventas_discovery_ingestas WHERE id=v_batch;
 EXCEPTION WHEN unique_violation THEN v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'SAME_RUN_BATCH_DUPLICATE_ACCEPTED'; END IF;

 -- The same immutable public file can be independently audited in another RUN.
 INSERT INTO saly.ventas_discovery_ingestas
 (catalog_version,source_id,connector_id,substep_code,scope_key,
  batch_key,query_hash,consulta_evidencia_ref,source_version,recurso_url,
  licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
  derechos_verificados,archivo_sha256,filas_reportadas,estado)
 SELECT catalog_version,source_id,connector_id,substep_code,scope_key,
  batch_key,query_hash,consulta_evidencia_ref,source_version,recurso_url,
  licencia_codigo,atribucion,comprobacion_licencia_url,run_ref||'-SECOND',
  derechos_verificados,archivo_sha256,filas_reportadas,estado
 FROM saly.ventas_discovery_ingestas WHERE id=v_batch
 RETURNING id INTO v_repeated_run;
 IF v_repeated_run IS NULL THEN RAISE EXCEPTION 'REPEATED_RUN_REJECTED'; END IF;

 INSERT INTO saly.ventas_hallazgos
 (ingesta_id,fila_origen,external_ref,tipo,nombre_provisional,ruc_literal,
 ruc_candidato,ubigeo_candidato,evidencia_ref)
 VALUES
 (v_batch,1,'1','ENTIDAD_PUBLICA','Municipalidad A','20100000001','20100000001','150101','raw-line-1'),
 (v_batch,2,'2','DEPENDENCIA','Unidad de Municipalidad A','20100000001','20100000001','150101','raw-line-2'),
 (v_batch,3,'3','POR_CLASIFICAR','Municipalidad sin RUC',NULL,NULL,'110101','raw-line-3');

 IF (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=v_batch)<>3
 OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=v_batch AND ruc_candidato='20100000001')<>2
 OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=v_batch AND ruc_candidato IS NULL)<>1
 THEN RAISE EXCEPTION 'RUC_NONUNIQUE_OR_NULL_NOT_PRESERVED'; END IF;

 v_forbidden:=false;
 BEGIN
  INSERT INTO saly.ventas_hallazgos
  (ingesta_id,fila_origen,external_ref,nombre_provisional,evidencia_ref)
  VALUES(v_batch,1,'duplicate','Duplicated row','raw-line-1');
 EXCEPTION WHEN unique_violation THEN v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'DUPLICATE_SOURCE_ROW_ACCEPTED'; END IF;

 v_forbidden:=false;
 BEGIN
  UPDATE saly.ventas_discovery_ingestas
  SET derechos_verificados=false WHERE id=v_batch;
 EXCEPTION WHEN foreign_key_violation THEN v_forbidden:=true;
 END;
 IF NOT v_forbidden THEN RAISE EXCEPTION 'RIGHTS_REVOKED_WITH_INGESTED_DATA'; END IF;

 SELECT id INTO v_hallazgo FROM saly.ventas_hallazgos
 WHERE ingesta_id=v_batch AND fila_origen=1;
 INSERT INTO saly.ventas_unidades_operativas
 (registro_id,nombre_unidad,tipo_unidad)
 VALUES (v_hallazgo,'Municipalidad A','MUNICIPALIDAD') RETURNING id INTO v_duplicate;
 IF NOT EXISTS (SELECT 1 FROM saly.ventas_unidades_operativas
  WHERE id=v_duplicate AND estado_vinculacion='PENDIENTE')
 THEN RAISE EXCEPTION 'PREMATURE_VALIDATION_OF_UNIT'; END IF;

 RAISE NOTICE 'L27 functional controls passed; reverting fixture subtransaction';
  RAISE EXCEPTION USING ERRCODE='P2927', MESSAGE='SALY_L27_FIXTURE_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P2927' THEN
  IF SQLERRM <> 'SALY_L27_FIXTURE_ROLLBACK' THEN RAISE; END IF;
 END;
END $saly_l27_fixture$;
DO $saly_l27_verify$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos) <> 0
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas) <> 0
 OR (SELECT count(*) FROM saly.ventas_unidades_operativas) <> 0
 THEN RAISE EXCEPTION 'FUNCTIONAL_TEST_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'FUNCTIONAL_TEST_ROLLBACK_PASS';
END $saly_l27_verify$;
COMMIT;
