-- PG17 ISOLATED functional test. Requires L27 then L28 migrations applied.
-- NO PRODUCTION. All rows synthetic, transaction rolled back.
BEGIN;
DO $test$
DECLARE
 v_run uuid;
 v_ejec uuid;
 v_query uuid;
 v_ing uuid;
 rejected boolean;
BEGIN
 IF (SELECT count(*) FROM pg_tables WHERE schemaname='saly' AND rowsecurity
   AND tablename IN ('ventas_discovery_catalogo','ventas_discovery_runs',
    'ventas_discovery_plan_fuentes','ventas_discovery_plan_batches',
    'ventas_discovery_ejecuciones','ventas_discovery_consultas'))<>6
 THEN RAISE EXCEPTION 'L28_RLS_NOT_COMPLETE'; END IF;
 IF has_table_privilege('anon','saly.ventas_discovery_consultas','INSERT')
 OR has_table_privilege('authenticated','saly.ventas_discovery_catalogo','SELECT')
 THEN RAISE EXCEPTION 'L28_FRONTEND_GRANT_VIOLATION'; END IF;

 INSERT INTO saly.ventas_discovery_catalogo
 (catalog_version,source_id,connector_id,substep_code,step,familia,nombre)
 VALUES ('CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03',13,'ESTADO_TERRITORIAL','PTE test fixture');
 INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash)
 VALUES ('RUN-L28-FIXTURE','CAT-L28-FIXTURE','{"zone":"fixture"}'::jsonb,repeat('a',64))
 RETURNING id INTO v_run;
 INSERT INTO saly.ventas_discovery_plan_fuentes
 (run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion)
 VALUES (v_run,'CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','TEST','REQUIRED');
 INSERT INTO saly.ventas_discovery_plan_batches
 (run_id,source_id,scope_key,batch_key,query_hash)
 VALUES (v_run,'PE-PTE','TEST','BATCH-1',repeat('b',64));
 INSERT INTO saly.ventas_discovery_ejecuciones
 (run_id,catalog_version,source_id,connector_id,substep_code,scope_key,
  estado,evidencia_ref,ultima_consulta_en,total_encontrados)
 VALUES (v_run,'CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','TEST',
  'FOUND','fixture://executed',now(),3)
 RETURNING id INTO v_ejec;
 INSERT INTO saly.ventas_discovery_consultas
 (ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,substep_code,
  scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
 VALUES (v_ejec,v_run,'RUN-L28-FIXTURE','CAT-L28-FIXTURE','PE-PTE',
 'SALY-U07-S13-C03','13.03','TEST','BATCH-1',repeat('b',64),
 'PG17-SYNTHETIC',now(),now(),'FOUND',3,'fixture://query-receipt')
 RETURNING id INTO v_query;

 rejected:=false;
 BEGIN
  UPDATE saly.ventas_discovery_runs SET estado='CERRADO' WHERE id=v_run;
 EXCEPTION WHEN check_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'CLOSED_WITHOUT_COVERAGE_GATE'; END IF;

 rejected:=false;
 BEGIN
  INSERT INTO saly.ventas_discovery_ingestas
  (catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,
   query_hash,consulta_evidencia_ref,source_version,recurso_url,
   licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
   derechos_verificados,archivo_sha256,filas_reportadas,estado,consulta_id)
  VALUES ('CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','TEST','BATCH-1',
   repeat('b',64),'fixture://query-receipt','2026-08','https://example.org/pte.csv',
   'ODC-BY','Fixture','https://example.org/licence','RUN-L28-FIXTURE',
   true,repeat('d',64),3,'PARCIAL',v_query);
 EXCEPTION WHEN foreign_key_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'CATALOG_RIGHTS_BYPASS'; END IF;

 rejected:=false;
 BEGIN
  UPDATE saly.ventas_discovery_catalogo SET
   rights_status='PERSISTENCIA_PERMITIDA',persist_business_data=true,habilitada=true
  WHERE catalog_version='CAT-L28-FIXTURE' AND source_id='PE-PTE';
 EXCEPTION WHEN check_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'SOURCE_RIGHTS_WITHOUT_EVIDENCE_ACCEPTED'; END IF;

 UPDATE saly.ventas_discovery_catalogo SET
  rights_status='PERSISTENCIA_PERMITIDA',
  rights_evidence_ref='fixture://synthetic-authorization',
  rights_checked_at=now(),
  persist_business_data=true,habilitada=true
 WHERE catalog_version='CAT-L28-FIXTURE' AND source_id='PE-PTE';

 INSERT INTO saly.ventas_discovery_ingestas
 (catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,
  query_hash,consulta_evidencia_ref,source_version,recurso_url,
  licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
  derechos_verificados,archivo_sha256,filas_reportadas,estado,consulta_id)
 VALUES ('CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','TEST','BATCH-1',
 repeat('b',64),'fixture://query-receipt','2026-08','https://example.org/pte.csv',
 'ODC-BY','Fixture','https://example.org/licence','RUN-L28-FIXTURE',
 true,repeat('d',64),3,'PARCIAL',v_query)
 RETURNING id INTO v_ing;

 rejected:=false;
 BEGIN
  INSERT INTO saly.ventas_discovery_ingestas
  (catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,
   query_hash,consulta_evidencia_ref,source_version,recurso_url,
   licencia_codigo,atribucion,comprobacion_licencia_url,run_ref,
   derechos_verificados,archivo_sha256,filas_reportadas,estado,consulta_id)
  VALUES ('CAT-L28-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','TEST','BATCH-1',
   repeat('c',64),'fixture://query-receipt','2026-08','https://example.org/pte.csv',
   'ODC-BY','Fixture','https://example.org/licence','RUN-L28-FIXTURE',
   true,repeat('e',64),3,'PARCIAL',v_query);
 EXCEPTION WHEN foreign_key_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'QUERY_HASH_SPOOF_ACCEPTED'; END IF;

 INSERT INTO saly.ventas_hallazgos
 (ingesta_id,fila_origen,external_ref,tipo,nombre_provisional,
  ruc_candidato,ubigeo_candidato,evidencia_ref)
 VALUES
 (v_ing,1,'first','ENTIDAD_PUBLICA','Entidad A','20100000001','150101','fixture://r1'),
 (v_ing,2,'second','DEPENDENCIA','Dependencia A','20100000001','150101','fixture://r2'),
 (v_ing,3,'third','ENTIDAD_PUBLICA','Entidad sin RUC',NULL,'110101','fixture://r3');

 IF (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=v_ing)<>3
 OR (SELECT count(*) FROM saly.ventas_hallazgos
     WHERE ingesta_id=v_ing AND ruc_candidato='20100000001')<>2
 OR (SELECT count(*) FROM saly.ventas_hallazgos
     WHERE ingesta_id=v_ing AND ruc_candidato IS NULL)<>1
 THEN RAISE EXCEPTION 'RUC_NULL_OR_DUPLICATES_NOT_PRESERVED'; END IF;

 RAISE NOTICE 'L28 POSITIVE/NEGATIVE FIXTURE PASS; all changes rolled back';
END $test$;
ROLLBACK;
DO $readback$
BEGIN
 IF EXISTS (SELECT 1 FROM saly.ventas_discovery_runs WHERE run_ref='RUN-L28-FIXTURE')
 OR EXISTS (SELECT 1 FROM saly.ventas_discovery_catalogo WHERE catalog_version='CAT-L28-FIXTURE')
 OR EXISTS (SELECT 1 FROM saly.ventas_discovery_ingestas WHERE run_ref='RUN-L28-FIXTURE')
 THEN RAISE EXCEPTION 'L28_ROLLBACK_NOT_CLEAN'; END IF;
END $readback$;
