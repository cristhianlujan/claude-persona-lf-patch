-- Candidate SQL, not a migration or an activation. Invoker only.
-- Requires a registered and authorized native operation and a DB-owned approved policy.
CREATE FUNCTION saly.ventas_sunat_ingesta_context_v1(p_exec text,p_owner text,p_fence bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,saly,public AS $$
DECLARE e public.lf_operation_execution%ROWTYPE; pol jsonb; req jsonb;
BEGIN
 IF nullif(btrim(p_exec),'') IS NULL OR nullif(btrim(p_owner),'') IS NULL OR coalesce(p_fence,0)<=0 THEN
  RAISE EXCEPTION 'SUNAT_CALL_CONTRACT'; END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_exec FOR UPDATE;
 IF NOT FOUND OR e.operation_code IS DISTINCT FROM 'INGESTA_EMPRESARIAL_SALY'
 OR e.target_type IS DISTINCT FROM 'DISCOVERY_SOURCE' OR e.target_code IS DISTINCT FROM 'PE-SUNAT-RUC'
 OR e.status IS DISTINCT FROM 'IN_PROGRESS' THEN RAISE EXCEPTION 'SUNAT_OPERATION_REQUIRED'; END IF;
 IF e.lease_owner IS DISTINCT FROM p_owner OR e.lease_fence IS DISTINCT FROM p_fence
 OR e.lease_expires_at IS NULL OR e.lease_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'SUNAT_STALE_LEASE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code=e.operation_code
 AND status='SANDBOX_ACTIVE') OR NOT EXISTS(SELECT 1 FROM public.lf_operation_contracts
 WHERE operation_code=e.operation_code AND contract_code='SALY_BUSINESS_INGESTION_V1' AND status='ACTIVE_ENFORCEMENT') THEN
 RAISE EXCEPTION 'SUNAT_OPERATION_NOT_ENABLED'; END IF;
 SELECT config_value::jsonb INTO STRICT pol FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
 AND config_key='SUNAT_POLICY_V1' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF pol->'enabled' IS DISTINCT FROM 'true'::jsonb OR pol->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
 OR pol->>'rights_scope' IS DISTINCT FROM 'SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20'
 OR pol->>'reduced_rights_status' IS DISTINCT FROM 'PERSISTENCIA_PERMITIDA'
 OR coalesce(pol->>'manifest_digest_sha256','') !~ '^[0-9a-f]{64}$'
 OR jsonb_typeof(pol->'snapshot_sha256') IS DISTINCT FROM 'array'
 OR jsonb_array_length(pol->'snapshot_sha256')<>2
 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(pol->'snapshot_sha256') x WHERE x !~ '^[0-9a-f]{64}$')
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['max_rows','max_bytes','max_total_bytes','expected_rows','expected_batches']) k
 WHERE coalesce(pol->>k,'') !~ '^[1-9][0-9]{0,8}$')
 THEN RAISE EXCEPTION 'SUNAT_CALL_POLICY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'
 AND rights_status='PERSISTENCIA_PERMITIDA' AND rights_evidence_ref=pol->>'rights_evidence_ref'
 AND rights_checked_at IS NOT NULL AND habilitada AND persist_business_data)
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC')<>1
 THEN RAISE EXCEPTION 'SUNAT_CALL_CATALOG'; END IF;
 req:=jsonb_build_object('business','SALY','source_id','PE-SUNAT-RUC','scope_key','LIMA_ICA',
 'snapshot_sha256',pol->'snapshot_sha256','manifest_digest_sha256',pol->'manifest_digest_sha256');
 IF e.manifest->'sunat_plan' IS DISTINCT FROM req OR e.request_sha256 IS DISTINCT FROM
 encode(sha256(convert_to(saly.ventas_capture_canonical_v1(req),'UTF8')),'hex')
 THEN RAISE EXCEPTION 'SUNAT_OPERATION_PLAN_BINDING'; END IF;
 RETURN pol;
END $$;

CREATE FUNCTION saly.ventas_sunat_plan_prepare_v1(p_exec text,p_owner text,p_fence bigint,p_plan jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,saly,public AS $$
DECLARE pol jsonb; k saly.ventas_discovery_catalogo%ROWTYPE; d saly.ventas_discovery_runs%ROWTYPE;
 h text; n bigint; total bigint; amount bigint; result uuid; item jsonb; idx bigint;
BEGIN
 pol:=saly.ventas_sunat_ingesta_context_v1(p_exec,p_owner,p_fence);
 IF jsonb_typeof(p_plan) IS DISTINCT FROM 'array' OR jsonb_array_length(p_plan)<>(pol->>'expected_batches')::int
 THEN RAISE EXCEPTION 'SUNAT_PLAN_SHAPE'; END IF;
 h:=encode(sha256(convert_to(saly.ventas_capture_canonical_v1(p_plan),'UTF8')),'hex');
 IF h IS DISTINCT FROM pol->>'manifest_digest_sha256' THEN RAISE EXCEPTION 'SUNAT_PLAN_DIGEST'; END IF;
 total:=0; amount:=0;
 FOR item,idx IN SELECT value,ordinality FROM jsonb_array_elements(p_plan) WITH ORDINALITY LOOP
  IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR item - ARRAY['batch_key','ordinal','rows','bytes','capture_sha256','consulta_evidencia_ref']<>'{}'::jsonb
  OR item->'ordinal' IS DISTINCT FROM to_jsonb(idx)
  OR coalesce(item->>'rows','') !~ '^[1-9][0-9]{0,8}$' OR coalesce(item->>'bytes','') !~ '^[1-9][0-9]{0,8}$'
  OR coalesce(item->>'capture_sha256','') !~ '^[0-9a-f]{64}$'
  OR item->>'consulta_evidencia_ref' IS DISTINCT FROM ((pol->>'monthly_url')||'#captura-json-sha256='||(item->>'capture_sha256'))
  OR item->>'batch_key' IS DISTINCT FROM encode(sha256(convert_to(saly.ventas_capture_canonical_v1(
  jsonb_build_array('PE-SUNAT-RUC',pol->'snapshot_sha256','LIMA_ICA',idx)),'UTF8')),'hex')
  THEN RAISE EXCEPTION 'SUNAT_PLAN_ENTRY'; END IF;
  IF (item->>'rows')::bigint>(pol->>'max_rows')::bigint OR (item->>'bytes')::bigint>(pol->>'max_bytes')::bigint
  THEN RAISE EXCEPTION 'SUNAT_PLAN_LIMIT'; END IF;
  total:=total+(item->>'bytes')::bigint; amount:=amount+(item->>'rows')::bigint;
 END LOOP;
 IF total>(pol->>'max_total_bytes')::bigint OR amount<>(pol->>'expected_rows')::bigint THEN RAISE EXCEPTION 'SUNAT_PLAN_TOTAL'; END IF;
 SELECT * INTO STRICT k FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC' FOR SHARE;
 SELECT * INTO d FROM saly.ventas_discovery_runs WHERE run_ref=p_exec FOR UPDATE;
 IF FOUND THEN
  IF d.plan_hash IS DISTINCT FROM h OR d.catalog_version IS DISTINCT FROM k.catalog_version
  OR (SELECT jsonb_agg(b.filtros ORDER BY (b.filtros->>'ordinal')::bigint) FROM saly.ventas_discovery_plan_batches b
  WHERE b.run_id=d.id AND b.source_id=k.source_id AND b.scope_key='LIMA_ICA') IS DISTINCT FROM p_plan
  THEN RAISE EXCEPTION 'SUNAT_PLAN_REPLAY_DRIFT'; END IF;
  RETURN d.id;
 END IF;
 INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
 VALUES(p_exec,k.catalog_version,jsonb_build_object('business','SALY','scope_key','LIMA_ICA','source_id',k.source_id,'snapshot_sha256',pol->'snapshot_sha256'),h,'EN_EJECUCION')
 RETURNING id INTO result;
 INSERT INTO saly.ventas_discovery_plan_fuentes(run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion,estado)
 VALUES(result,k.catalog_version,k.source_id,k.connector_id,k.substep_code,'LIMA_ICA','REQUIRED','EN_EJECUCION');
 INSERT INTO saly.ventas_discovery_ejecuciones(run_id,catalog_version,source_id,connector_id,substep_code,scope_key)
 VALUES(result,k.catalog_version,k.source_id,k.connector_id,k.substep_code,'LIMA_ICA');
 INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,filtros)
 SELECT result,k.source_id,'LIMA_ICA',x->>'batch_key',
 encode(sha256(convert_to(saly.ventas_capture_canonical_v1(x),'UTF8')),'hex'),x FROM jsonb_array_elements(p_plan) x;
 RETURN result;
END $$;

CREATE FUNCTION saly.ventas_sunat_batch_execute_v1(p_exec text,p_owner text,p_fence bigint,p_batch text,p_capture text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,saly,public AS $$
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
 res:=public.fn_lf_operation_reserve_effect_v1(p_exec,p_owner,p_fence,'SUNAT:'||p_batch,h,'SUNAT:'||p_batch,p_exec);
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
END $$;
REVOKE ALL ON FUNCTION saly.ventas_sunat_ingesta_context_v1(text,text,bigint),
 saly.ventas_sunat_plan_prepare_v1(text,text,bigint,jsonb),
 saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text) FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
