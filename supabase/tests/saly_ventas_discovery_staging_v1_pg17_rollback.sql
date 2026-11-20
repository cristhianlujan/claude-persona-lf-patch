-- PostgreSQL 17 isolated CI. Applied migration from this PR. No production connection.
-- Run with -v ON_ERROR_STOP=1.
BEGIN;
DO $check$
DECLARE
 v_batch uuid;
 v_hallazgo uuid;
 v_duplicate uuid;
 v_forbidden boolean;
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

 RAISE NOTICE 'PG17 FUNCTIONAL 12 CONTROLS PASS (transaction will rollback)';
END $check$;
ROLLBACK;
DO $check$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos) <> 0
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas) <> 0
 OR (SELECT count(*) FROM saly.ventas_unidades_operativas) <> 0
 THEN RAISE EXCEPTION 'FUNCTIONAL_TEST_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'FUNCTIONAL_TEST_ROLLBACK_PASS';
END $check$;
