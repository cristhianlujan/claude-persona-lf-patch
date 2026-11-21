-- SALY Step10, PTE pilot writer core. Not a commercial runtime grant.
-- Only an authorized caller with an existing FOUND consultation and approved source may use it.
-- archivo_sha256 identifies the exact canonical capture artifact passed as UTF-8 JSON,
-- NOT the original publisher's binary CSV. This distinction is explicit in the receipt.
BEGIN;
CREATE FUNCTION saly.ventas_pte_ingesta_core_v1(
 p_consulta_id uuid, p_capture text, p_source_version text, p_recurso_url text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog,saly
AS $writer$
DECLARE
 q record;
 v_rows jsonb;
 v_hash text;
 v_count integer;
 v_ing uuid;
 v_previous record;
 v_inserted integer;
BEGIN
 IF p_consulta_id IS NULL OR p_capture IS NULL OR
    nullif(btrim(p_source_version),'') IS NULL OR
    p_recurso_url IS NULL OR
    p_recurso_url !~ '^https://www[.]datosabiertos[.]gob[.]pe/sites/default/files/'
 THEN RAISE EXCEPTION 'PTE_INVALID_INPUT'; END IF;
 v_rows := p_capture::jsonb;
 IF jsonb_typeof(v_rows) IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'PTE_CAPTURE_NOT_ARRAY';
 END IF;
 v_count := jsonb_array_length(v_rows);
 IF v_count=0 THEN RAISE EXCEPTION 'PTE_EMPTY_CAPTURE_USE_EMPTY_QUERY'; END IF;
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_rows) AS x(r)
   WHERE jsonb_typeof(r) IS DISTINCT FROM 'object'
     OR NOT (r ?& ARRAY['fila_origen','nombre','ruc','ubigeo'])
     OR coalesce(r->>'fila_origen','') !~ '^[1-9][0-9]{0,8}$'
     OR jsonb_typeof(r->'nombre') IS DISTINCT FROM 'string'
     OR nullif(btrim(r->>'nombre'),'') IS NULL
     OR jsonb_typeof(r->'ruc') NOT IN ('null','string')
     OR jsonb_typeof(r->'ubigeo') IS DISTINCT FROM 'string'
     OR coalesce(r->>'ubigeo','') !~ '^(15|11)[0-9]{4}$'
 ) THEN RAISE EXCEPTION 'PTE_INVALID_CAPTURE_ROW'; END IF;
 IF (SELECT count(DISTINCT r->>'fila_origen') FROM jsonb_array_elements(v_rows) AS x(r))<>v_count
 THEN RAISE EXCEPTION 'PTE_DUPLICATE_SOURCE_ROW'; END IF;
 v_hash := encode(sha256(convert_to(p_capture,'UTF8')),'hex');
 SELECT c.*, k.rights_evidence_ref, k.landing_page
 INTO q
 FROM saly.ventas_discovery_consultas c
 JOIN saly.ventas_discovery_catalogo k
 ON (k.catalog_version,k.source_id,k.connector_id,k.substep_code)=
    (c.catalog_version,c.source_id,c.connector_id,c.substep_code)
 JOIN saly.ventas_discovery_runs dr ON dr.id=c.run_id
 WHERE c.id=p_consulta_id
 AND c.source_id='PE-PTE' AND c.connector_id='SALY-U07-S13-C03'
 AND c.substep_code='13.03' AND c.scope_key='LIMA_ICA'
 AND c.estado='FOUND' AND c.fin IS NOT NULL
 AND c.cantidad_hallazgos=v_count
 AND dr.estado IN ('EN_EJECUCION','PARTIAL')
 AND k.rights_status='PERSISTENCIA_PERMITIDA'
 AND k.persist_business_data AND k.habilitada AND k.rights_checked_at IS NOT NULL
 AND nullif(btrim(k.rights_evidence_ref),'') IS NOT NULL
 AND k.landing_page LIKE 'https://www.datosabiertos.gob.pe/dataset/%'
 AND c.evidencia_ref=p_recurso_url||'#captura-json-sha256='||v_hash
 FOR UPDATE OF c;
 IF NOT FOUND THEN RAISE EXCEPTION 'PTE_QUERY_OR_RIGHTS_NOT_AUTHORIZED'; END IF;

 SELECT * INTO v_previous FROM saly.ventas_discovery_ingestas
 WHERE consulta_id=p_consulta_id
 ORDER BY creada_en,id LIMIT 1;
 IF FOUND THEN
  IF v_previous.archivo_sha256 IS DISTINCT FROM v_hash
   OR v_previous.source_version IS DISTINCT FROM p_source_version
   OR v_previous.recurso_url IS DISTINCT FROM p_recurso_url
   OR v_previous.filas_reportadas IS DISTINCT FROM v_count
   OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE consulta_id=p_consulta_id)<>1
   OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=v_previous.id)<>v_count
   OR EXISTS (
     SELECT 1 FROM jsonb_array_elements(v_rows) AS x(r)
     WHERE NOT EXISTS(
      SELECT 1 FROM saly.ventas_hallazgos h WHERE h.ingesta_id=v_previous.id
       AND h.fila_origen=(r->>'fila_origen')::integer
       AND h.nombre_provisional=r->>'nombre'
       AND h.ruc_literal IS NOT DISTINCT FROM r->>'ruc'
       AND h.ubigeo_candidato=r->>'ubigeo'
     )
   ) THEN RAISE EXCEPTION 'PTE_REPLAY_DRIFT'; END IF;
  RETURN jsonb_build_object('status','REPLAY','ingesta_id',v_previous.id,
   'filas',v_count,'capture_sha256',v_hash);
 END IF;
 INSERT INTO saly.ventas_discovery_ingestas (
  catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,
  query_hash,consulta_evidencia_ref,source_version,recurso_url,licencia_codigo,
  atribucion,comprobacion_licencia_url,derechos_verificados,archivo_sha256,
  estado,filas_reportadas,run_ref,consulta_id)
 VALUES (
  q.catalog_version,q.source_id,q.connector_id,q.substep_code,q.scope_key,q.batch_key,
  q.query_hash,q.evidencia_ref,p_source_version,p_recurso_url,'ODC-BY',
  'PCM — Plataforma Nacional de Datos Abiertos / DSPTE01',
  q.landing_page,true,v_hash,'PARCIAL',v_count,q.run_ref,q.id)
 RETURNING id INTO v_ing;
 INSERT INTO saly.ventas_hallazgos (
  ingesta_id,fila_origen,external_ref,nombre_provisional,ruc_literal,
  ruc_candidato,ubigeo_candidato,evidencia_ref,estado_identidad)
 SELECT v_ing,(r->>'fila_origen')::integer,
  'DSPTE01:row:'||(r->>'fila_origen'),r->>'nombre',r->>'ruc',
  CASE WHEN r->>'ruc' ~ '^[0-9]{11}$' THEN r->>'ruc' ELSE NULL END,
  r->>'ubigeo',q.evidencia_ref||'&row='||(r->>'fila_origen'),
  CASE WHEN nullif(btrim(r->>'ruc'),'') IS NULL THEN 'SIN_RUC'
       WHEN r->>'ruc' ~ '^[0-9]{11}$' THEN 'PENDIENTE' ELSE 'DISCREPANCIA' END
 FROM jsonb_array_elements(v_rows) AS x(r);
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 IF v_inserted<>v_count THEN RAISE EXCEPTION 'PTE_ROW_COUNT_MISMATCH'; END IF;
 RETURN jsonb_build_object('status','INSERTED','ingesta_id',v_ing,
  'filas',v_count,'capture_sha256',v_hash);
END $writer$;
REVOKE ALL ON FUNCTION saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)
 FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
COMMENT ON FUNCTION saly.ventas_pte_ingesta_core_v1(uuid,text,text,text) IS
 'Technical core only. No runtime grant; authorized parent operation and source review remain separate. Hash of UTF-8 capture JSON, not original CSV bytes.';
-- Functional test uses local synthetic lineage only and rolls everything back.
DO $fixture$
DECLARE
 v_run uuid; v_ejec uuid; v_query uuid; v_hash text; v_receipt text; v_res jsonb;
 v_url constant text:='https://www.datosabiertos.gob.pe/sites/default/files/fixture.csv';
 v_landing constant text:='https://www.datosabiertos.gob.pe/dataset/fixture';
 v_capture constant text:='[{"fila_origen":1,"nombre":"Fixture A","ruc":"20100000001","ubigeo":"150101"},{"fila_origen":2,"nombre":"Fixture B","ruc":"20100000001","ubigeo":"110101"},{"fila_origen":3,"nombre":"Fixture C","ruc":null,"ubigeo":"110102"}]';
 v_rejected boolean;
BEGIN
 IF has_function_privilege('anon','saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)','EXECUTE')
 OR has_function_privilege('authenticated','saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)','EXECUTE')
 OR has_function_privilege('service_role','saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)','EXECUTE')
 OR has_function_privilege('supabase_read_only_user','saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'PTE_UNEXPECTED_RUNTIME_GRANT'; END IF;
 BEGIN
  v_hash:=encode(sha256(convert_to(v_capture,'UTF8')),'hex');
  v_receipt:=v_url||'#captura-json-sha256='||v_hash;
  INSERT INTO saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code,step,familia,nombre,landing_page)
  VALUES('CAT-PTE-WRITER-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03',13,'ESTADO_TERRITORIAL','Fixture',v_landing);
  INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
  VALUES('RUN-PTE-WRITER-FIXTURE','CAT-PTE-WRITER-FIXTURE','{"scope":"LIMA_ICA"}',repeat('a',64),'EN_EJECUCION') RETURNING id INTO v_run;
  INSERT INTO saly.ventas_discovery_plan_fuentes(run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion)
  VALUES(v_run,'CAT-PTE-WRITER-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','REQUIRED');
  INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
  VALUES(v_run,'PE-PTE','LIMA_ICA','FIXTURE',repeat('b',64),'FOUND');
  INSERT INTO saly.ventas_discovery_ejecuciones(run_id,catalog_version,source_id,connector_id,substep_code,scope_key,estado,evidencia_ref,ultima_consulta_en,total_encontrados)
  VALUES(v_run,'CAT-PTE-WRITER-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','FOUND',v_receipt,now(),3) RETURNING id INTO v_ejec;
  INSERT INTO saly.ventas_discovery_consultas(ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
  VALUES(v_ejec,v_run,'RUN-PTE-WRITER-FIXTURE','CAT-PTE-WRITER-FIXTURE','PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','FIXTURE',repeat('b',64),'SYNTHETIC',now(),now(),'FOUND',3,v_receipt) RETURNING id INTO v_query;
  v_rejected:=false;
  BEGIN PERFORM saly.ventas_pte_ingesta_core_v1(v_query,v_capture,'fixture',v_url);
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'PTE_QUERY_OR_RIGHTS_NOT_AUTHORIZED' THEN RAISE; END IF;
   v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'PTE_UNAUTHORIZED_RIGHTS_ACCEPTED'; END IF;
  UPDATE saly.ventas_discovery_catalogo SET rights_status='PERSISTENCIA_PERMITIDA',
   rights_evidence_ref='fixture://synthetic-rights',rights_checked_at=now(),persist_business_data=true,habilitada=true
   WHERE catalog_version='CAT-PTE-WRITER-FIXTURE' AND source_id='PE-PTE';
  v_res:=saly.ventas_pte_ingesta_core_v1(v_query,v_capture,'fixture',v_url);
  IF v_res->>'status'<>'INSERTED' OR (v_res->>'filas')::integer<>3 THEN RAISE EXCEPTION 'PTE_INSERT_FAILED'; END IF;
  IF (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=(v_res->>'ingesta_id')::uuid AND ruc_candidato='20100000001')<>2
  OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=(v_res->>'ingesta_id')::uuid AND estado_identidad='SIN_RUC')<>1
  THEN RAISE EXCEPTION 'PTE_RUC_LOSS'; END IF;
  v_res:=saly.ventas_pte_ingesta_core_v1(v_query,v_capture,'fixture',v_url);
  IF v_res->>'status'<>'REPLAY' THEN RAISE EXCEPTION 'PTE_REPLAY_FAILED'; END IF;
  v_rejected:=false;
  BEGIN PERFORM saly.ventas_pte_ingesta_core_v1(v_query,replace(v_capture,'Fixture A','Changed A'),'fixture',v_url);
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'PTE_QUERY_OR_RIGHTS_NOT_AUTHORIZED' THEN RAISE; END IF;
   v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'PTE_HASH_DRIFT_ACCEPTED'; END IF;
  RAISE EXCEPTION USING ERRCODE='P2936',MESSAGE='PTE_FIXTURE_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P2936' THEN IF SQLERRM<>'PTE_FIXTURE_ROLLBACK' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM saly.ventas_discovery_runs WHERE run_ref='RUN-PTE-WRITER-FIXTURE')
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_catalogo WHERE catalog_version='CAT-PTE-WRITER-FIXTURE')
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE run_ref='RUN-PTE-WRITER-FIXTURE')
 THEN RAISE EXCEPTION 'PTE_FIXTURE_NOT_ROLLED_BACK'; END IF;
 RAISE NOTICE 'PASS_PTE_WRITER_CORE_FIXTURE_ROLLBACK';
END $fixture$;
COMMIT;
