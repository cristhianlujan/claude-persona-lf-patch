-- SALY SUNAT: only commercial RUN dispatch identity differs; historical effect_scope/keys unchanged.
-- Diagnosed from real production SQLSTATE 23505 (2026-11-23 04:57:56 UTC).
-- Readback: 3/3 new batch dispatch keys collide with historical RUN effects.
-- One migration / no direct inserts / governed Train only.
BEGIN;
SET LOCAL lock_timeout='4s';
SET LOCAL statement_timeout='50s';
DO $pre$
DECLARE
  v_train text;
  v_pol jsonb;
BEGIN
  SELECT execution_id INTO v_train FROM public.lf_operation_execution
    WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
      AND target_code LIKE '%lf_saly_sunat_commercial_dispatch_key_v1'
      AND status='IN_PROGRESS'
    ORDER BY created_at DESC LIMIT 1;
  IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_DISPATCH_TRAIN_REQUIRED'; END IF;
  IF encode(sha256(convert_to(pg_get_functiondef(
      'saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)'::regprocedure),
      'UTF8')),'hex') IS DISTINCT FROM '9b9d2b5db656574ad243a23da36f6e4412b5f544bbd25a6740489f6d8dd3f7ae'
    THEN RAISE EXCEPTION 'SUNAT_DISPATCH_SOURCE_DRIFT'; END IF;
  SELECT config_value::jsonb INTO v_pol
    FROM public.lf_global_config
   WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
     AND value_type='JSON' AND value_status='REAL' AND valid_from<=now()
   ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
  IF v_pol->'commercial_mode' IS DISTINCT FROM 'true'::jsonb
    OR v_pol->'enabled' IS DISTINCT FROM 'true'::jsonb
    OR v_pol->>'commercial_run_ref' IS DISTINCT FROM 'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001'
    OR v_pol->>'manifest_digest_sha256' IS DISTINCT FROM '40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595'
    OR v_pol->'old_manifest_replay_allowed' IS DISTINCT FROM 'false'::jsonb
    OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
        JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
        WHERE r.run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001'
          AND b.estado='NOT_RUN')<>3
    OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
        WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')<>0
    OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
        WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')<>136
    OR (SELECT count(*) FROM saly.ventas_hallazgos h
        JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
        WHERE i.source_id='PE-SUNAT-RUC')<>5275
    OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
        JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
        JOIN public.lf_operation_effect_guard e
          ON e.dispatch_key='SUNAT:'||b.batch_key
        WHERE r.run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001'
          AND e.execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001')<>3
   THEN RAISE EXCEPTION 'SUNAT_DISPATCH_PRESTATE_DRIFT'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION saly.ventas_sunat_batch_execute_v1(p_exec text, p_owner text, p_fence bigint, p_batch text, p_capture text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE pol jsonb; d saly.ventas_discovery_runs%ROWTYPE; b saly.ventas_discovery_plan_batches%ROWTYPE;
 k saly.ventas_discovery_catalogo%ROWTYPE; e saly.ventas_discovery_ejecuciones%ROWTYPE;
 entry jsonb; payload jsonb; h text; n int; qid uuid; iid uuid; res jsonb; receipt jsonb; all_plan jsonb;
BEGIN
 IF coalesce(p_batch,'') !~ '^[0-9a-f]{64}$' OR p_capture IS NULL THEN RAISE EXCEPTION 'SUNAT_BATCH_CONTRACT'; END IF;
 pol:=saly.ventas_sunat_ingesta_context_v1(p_exec,p_owner,p_fence);
 IF octet_length(p_capture)>(pol->>'max_bytes')::int THEN RAISE EXCEPTION 'SUNAT_CALL_BYTES'; END IF;
 SELECT * INTO STRICT d FROM saly.ventas_discovery_runs WHERE run_ref=p_exec AND estado IN ('EN_EJECUCION','PARTIAL') FOR UPDATE;
 SELECT * INTO STRICT k FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC' AND catalog_version=d.catalog_version FOR SHARE;
 SELECT jsonb_agg(filtros ORDER BY (filtros->>'ordinal')::bigint) INTO all_plan FROM saly.ventas_discovery_plan_batches
 WHERE run_id=d.id AND source_id=k.source_id AND scope_key='LIMA_ICA';
 IF d.plan_hash IS DISTINCT FROM pol->>'manifest_digest_sha256' OR d.scope->'snapshot_sha256' IS DISTINCT FROM pol->'snapshot_sha256'
 OR encode(sha256(convert_to(saly.ventas_capture_canonical_v1(all_plan),'UTF8')),'hex') IS DISTINCT FROM d.plan_hash
 THEN RAISE EXCEPTION 'SUNAT_PLAN_DRIFT'; END IF;
 SELECT * INTO STRICT b FROM saly.ventas_discovery_plan_batches WHERE run_id=d.id AND source_id=k.source_id
 AND scope_key='LIMA_ICA' AND batch_key=p_batch FOR UPDATE;
 entry:=b.filtros; h:=encode(sha256(convert_to(p_capture,'UTF8')),'hex');
 IF h IS DISTINCT FROM entry->>'capture_sha256' OR octet_length(p_capture)<>(entry->>'bytes')::int
 OR b.query_hash IS DISTINCT FROM encode(sha256(convert_to(saly.ventas_capture_canonical_v1(entry),'UTF8')),'hex')
 THEN RAISE EXCEPTION 'SUNAT_BATCH_HASH'; END IF;
 payload:=p_capture::jsonb;
 IF jsonb_typeof(payload) IS DISTINCT FROM 'array' OR saly.ventas_capture_canonical_v1(payload) IS DISTINCT FROM p_capture
 THEN RAISE EXCEPTION 'SUNAT_BATCH_CANONICAL'; END IF;
 n:=jsonb_array_length(payload);
 IF n<>(entry->>'rows')::int OR n>(pol->>'max_rows')::int OR n<1 OR EXISTS(
 SELECT 1 FROM jsonb_array_elements(payload) x WHERE
 x#>>'{capture,observations,monthly,evidence,zip_sha256}' IS DISTINCT FROM pol#>>'{snapshot_sha256,0}'
 OR x#>>'{capture,observations,reduced,evidence,zip_sha256}' IS DISTINCT FROM pol#>>'{snapshot_sha256,1}'
 OR coalesce(x#>>'{capture,observations,monthly,raw,UBIGEO}','') !~ '^(11|15)[0-9]{4}$'
 ) THEN RAISE EXCEPTION 'SUNAT_BATCH_SCOPE'; END IF;
 res:=public.fn_lf_operation_reserve_effect_v1(p_exec,p_owner,p_fence,'SUNAT:'||p_batch,h,CASE WHEN pol->'commercial_mode'='true'::jsonb AND p_exec=pol->>'commercial_run_ref' THEN 'SUNAT:'||p_exec||':'||p_batch ELSE 'SUNAT:'||p_batch END,p_exec);
 IF res->>'result'='EFFECT_RESERVED_NEW' AND res->'dispatch_permitted'='true'::jsonb THEN
  IF b.estado IS DISTINCT FROM 'NOT_RUN' THEN RAISE EXCEPTION 'SUNAT_BATCH_STATE'; END IF;
  SELECT * INTO STRICT e FROM saly.ventas_discovery_ejecuciones WHERE run_id=d.id AND source_id=k.source_id AND scope_key='LIMA_ICA' FOR UPDATE;
  INSERT INTO saly.ventas_discovery_consultas(ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,
  substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
  VALUES(e.id,d.id,p_exec,k.catalog_version,k.source_id,k.connector_id,k.substep_code,'LIMA_ICA',p_batch,
  b.query_hash,'SUNAT_VERIFIED_DELIVERY_V1',clock_timestamp(),clock_timestamp(),'FOUND',n,entry->>'consulta_evidencia_ref')
  RETURNING id INTO qid;
  iid:=saly.ventas_sunat_ingesta_core_v1(qid,p_capture);
  receipt:=jsonb_build_object('ingesta_id',iid,'consulta_id',qid,'batch_key',p_batch,'capture_sha256',h,'rows',n);
 ELSIF res->>'result'='REPLAY_SUCCEEDED_EFFECT' THEN
  receipt:=res->'receipt'; iid:=(receipt->>'ingesta_id')::uuid; qid:=(receipt->>'consulta_id')::uuid;
  IF receipt IS DISTINCT FROM jsonb_build_object('ingesta_id',iid,'consulta_id',qid,'batch_key',p_batch,'capture_sha256',h,'rows',n)
  OR b.estado IS DISTINCT FROM 'FOUND' THEN RAISE EXCEPTION 'SUNAT_EFFECT_REPLAY_DRIFT'; END IF;
 ELSE RAISE EXCEPTION 'SUNAT_EFFECT_RECONCILIATION_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas i JOIN saly.ventas_discovery_consultas c ON c.id=i.consulta_id
 WHERE i.id=iid AND c.id=qid AND c.run_id=d.id AND c.batch_key=p_batch AND i.archivo_sha256=h AND i.filas_reportadas=n)
 OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=iid)<>n
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(payload) x WHERE NOT EXISTS(
 SELECT 1 FROM saly.ventas_hallazgos z WHERE z.ingesta_id=iid AND z.ruc_candidato=x#>>'{capture,normalized,ruc}' AND z.captura_empresarial=x))
 THEN RAISE EXCEPTION 'SUNAT_BATCH_READBACK'; END IF;
 IF res->>'result'='EFFECT_RESERVED_NEW' THEN
  UPDATE saly.ventas_discovery_plan_batches SET estado='FOUND' WHERE id=b.id;
  PERFORM public.fn_lf_operation_mark_effect_succeeded_v1(p_exec,p_owner,p_fence,'SUNAT:'||p_batch,receipt,p_exec);
 END IF;
 RETURN receipt;
END $function$;

DO $post$
BEGIN
 IF position('pol->>''commercial_run_ref''' IN
     pg_get_functiondef('saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)'::regprocedure))=0
 OR position('''SUNAT:''||p_exec||'':''||p_batch' IN
     pg_get_functiondef('saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)'::regprocedure))=0
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')<>136
 OR (SELECT count(*) FROM saly.ventas_hallazgos h
     JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id='PE-SUNAT-RUC')<>5275
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')<>0
 OR has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'SUNAT_DISPATCH_POSTSTATE_DRIFT'; END IF;
END $post$;
COMMIT;
