-- SALY Ventas PTE: enforce one immutable source-version per discovered batch
-- across independent RUNs. Covers only PE-PTE / LIMA_ICA; no generic source changes.
-- This prevents duplicate persisted snapshots even if a second RUN arrives concurrently.
-- A new upstream content snapshot MUST be assigned a new source_version.
-- Not a commercial RUN, writer grant, profile or new caller.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'PTE_UNIQUE_PROJECT_NOT_ACTIVE'; END IF;
 IF (SELECT count(*) FROM saly.ventas_discovery_ingestas
     WHERE source_id='PE-PTE' AND scope_key='LIMA_ICA' AND source_version='2026-08')<>1
 OR (SELECT count(*) FROM saly.ventas_hallazgos h
     JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
     WHERE i.source_id='PE-PTE' AND i.scope_key='LIMA_ICA' AND i.source_version='2026-08')<>519
 THEN RAISE EXCEPTION 'PTE_UNIQUE_BASELINE_CHANGED'; END IF;
 IF EXISTS (
   SELECT 1 FROM saly.ventas_discovery_ingestas
   WHERE source_id='PE-PTE' AND scope_key='LIMA_ICA'
   GROUP BY source_id,source_version,scope_key,batch_key
   HAVING count(*)>1
 ) THEN RAISE EXCEPTION 'PTE_UNIQUE_PREEXISTING_DUPLICATES'; END IF;
 IF to_regclass('saly.saly_pte_source_batch_once_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'PTE_UNIQUE_INDEX_EXISTS'; END IF;
END $pre$;
CREATE UNIQUE INDEX saly_pte_source_batch_once_v1
 ON saly.ventas_discovery_ingestas(source_id,source_version,scope_key,batch_key)
 WHERE source_id='PE-PTE' AND scope_key='LIMA_ICA';

DO $negative$
DECLARE
 i saly.ventas_discovery_ingestas%rowtype;
 v_run uuid;
 v_execution uuid;
 v_query uuid;
 v_constraint text;
 v_rejected boolean:=false;
 v_ref constant text:='RUN-PTE-GUARD-FIXTURE';
BEGIN
 SELECT * INTO STRICT i FROM saly.ventas_discovery_ingestas
 WHERE source_id='PE-PTE' AND scope_key='LIMA_ICA' AND source_version='2026-08';

 BEGIN
  INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
  VALUES(v_ref,i.catalog_version,'{"mode":"SYNTHETIC_INDEX_NEGATIVE_TEST","scope":"LIMA_ICA"}'::jsonb,
         repeat('e',64),'EN_EJECUCION') RETURNING id INTO v_run;

  INSERT INTO saly.ventas_discovery_plan_fuentes(
   run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion,estado)
  VALUES(v_run,i.catalog_version,i.source_id,i.connector_id,i.substep_code,i.scope_key,
         'REQUIRED','EN_EJECUCION');

  INSERT INTO saly.ventas_discovery_plan_batches(
   run_id,source_id,scope_key,batch_key,query_hash,estado)
  VALUES(v_run,i.source_id,i.scope_key,i.batch_key,i.query_hash,'FOUND');

  INSERT INTO saly.ventas_discovery_ejecuciones(
   run_id,catalog_version,source_id,connector_id,substep_code,
   scope_key,estado,evidencia_ref,ultima_consulta_en,total_encontrados)
  VALUES(v_run,i.catalog_version,i.source_id,i.connector_id,i.substep_code,
         i.scope_key,'FOUND',i.consulta_evidencia_ref,now(),i.filas_reportadas)
  RETURNING id INTO v_execution;

  INSERT INTO saly.ventas_discovery_consultas(
   ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,
   substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,
   estado,cantidad_hallazgos,evidencia_ref)
  VALUES(v_execution,v_run,v_ref,i.catalog_version,i.source_id,i.connector_id,
         i.substep_code,i.scope_key,i.batch_key,i.query_hash,'PG17_NEGATIVE_FIXTURE',
         now(),now(),'FOUND',i.filas_reportadas,i.consulta_evidencia_ref)
  RETURNING id INTO v_query;

  BEGIN
   INSERT INTO saly.ventas_discovery_ingestas(
    catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,
    query_hash,consulta_evidencia_ref,source_version,recurso_url,licencia_codigo,
    atribucion,comprobacion_licencia_url,derechos_verificados,archivo_sha256,
    estado,filas_reportadas,run_ref,consulta_id,fuente_habilitada)
   SELECT i.catalog_version,i.source_id,i.connector_id,i.substep_code,i.scope_key,
    i.batch_key,i.query_hash,i.consulta_evidencia_ref,i.source_version,
    i.recurso_url,i.licencia_codigo,i.atribucion,i.comprobacion_licencia_url,
    i.derechos_verificados,i.archivo_sha256,i.estado,i.filas_reportadas,
    v_ref,v_query,i.fuente_habilitada;
   RAISE EXCEPTION 'PTE_CROSS_RUN_DUPLICATE_ACCEPTED';
  EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
   IF v_constraint<>'saly_pte_source_batch_once_v1'
   THEN RAISE EXCEPTION 'PTE_WRONG_CONSTRAINT_REJECTED:%',v_constraint; END IF;
   v_rejected:=true;
  END;

  IF NOT v_rejected THEN RAISE EXCEPTION 'PTE_CROSS_RUN_UNIQUE_NOT_TESTED'; END IF;
  RAISE EXCEPTION USING ERRCODE='P2949',MESSAGE='PTE_INDEX_TEST_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P2949' THEN
  IF SQLERRM<>'PTE_INDEX_TEST_ROLLBACK' THEN RAISE; END IF;
 END;

 IF EXISTS(SELECT 1 FROM saly.ventas_discovery_runs WHERE run_ref=v_ref)
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE run_ref=v_ref)
 THEN RAISE EXCEPTION 'PTE_INDEX_FIXTURE_LEAK'; END IF;
 IF (SELECT count(*) FROM saly.ventas_hallazgos h
     JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
     WHERE i.source_id='PE-PTE' AND i.scope_key='LIMA_ICA')<>519
 THEN RAISE EXCEPTION 'PTE_ORIGINAL_HALLAZGOS_CHANGED'; END IF;
 RAISE NOTICE 'PASS_PTE_CROSS_RUN_UNIQUE_INDEX_NEGATIVE_ROLLBACK';
END $negative$;
COMMIT;
