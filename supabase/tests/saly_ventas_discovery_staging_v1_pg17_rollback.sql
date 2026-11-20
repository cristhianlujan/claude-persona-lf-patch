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
 (source_code,source_version,recurso_url,licencia_codigo,atribucion,
  comprobacion_licencia_url,run_ref)
 VALUES('PE-PTE-ENTIDADES','2026-08','https://www.datosabiertos.gob.pe/example.csv',
 'ODC-BY','PTE / PNDA','https://www.datosabiertos.gob.pe/example-dataset',
 'test-PG17-ROLLBACK')
 RETURNING id INTO v_batch;

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

 RAISE NOTICE 'PG17 FUNCTIONAL 9 CONTROLS PASS (transaction will rollback)';
END $check$;
ROLLBACK;
SELECT CASE WHEN (SELECT count(*) FROM saly.ventas_hallazgos)<>0
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas)<>0
 OR (SELECT count(*) FROM saly.ventas_unidades_operativas)<>0
 THEN 1/0 ELSE 1 END AS transaction_rollback_verified;
