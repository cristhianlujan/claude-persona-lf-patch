-- Correct only PostgreSQL/Python whitespace normalization of SUNAT business name.
-- Real batch 9: 1/1000 names has Unicode whitespace that Python .strip() handles
-- but SQL default btrim() does not. Raw name, RUC, SHA and manifest remain intact.
-- Proven in GitHub action 45048992851 job 137289722308, and 8 lot readback.
BEGIN;
SET LOCAL lock_timeout='4s';
DO $guard$
DECLARE v_train text;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
 AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_name_whitespace_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_NORMALIZE_TRAIN_REQUIRED'; END IF;
 IF encode(sha256(convert_to(pg_get_functiondef(
      'saly.ventas_sunat_ingesta_core_v1(uuid,text)'::regprocedure),'UTF8')),'hex')
   <> 'cae8c68f7b60b9e06c9f62d0665c4f116598899e5cb2a0130ae5068207d9f471'
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')<>8
 OR (SELECT coalesce(sum(filas_reportadas),0) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')<>8000
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
  JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
  WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND b.estado='FOUND')<>8
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
  JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
  WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND b.estado='NOT_RUN')<>471
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
  WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
  AND rights_status='PERSISTENCIA_PERMITIDA'
  AND runtime_status='CONTROLLED_SEQUENTIAL_INGESTION')<>1
 OR (SELECT config_value::jsonb->>'pilot_scope' FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
  ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM 'SEQUENTIAL_ALL_REMAINING_479'
 THEN RAISE EXCEPTION 'SUNAT_NORMALIZE_PRESTATE_DRIFT'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION saly.ventas_sunat_ingesta_core_v1(p_consulta uuid, p_capture text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE
 policy jsonb;
 q record;
 payload jsonb;
 n integer;
 capture_hash text;
 first_obs jsonb;
 snap text;
 prior record;
 result uuid;
BEGIN
 SELECT config_value::jsonb INTO STRICT policy FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
 AND valid_from <= now() ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF jsonb_typeof(policy) IS DISTINCT FROM 'object'
 OR (policy->'enabled') IS DISTINCT FROM 'true'::jsonb
 OR coalesce(policy->>'max_rows','') !~ '^[1-9][0-9]{0,8}$'
 OR coalesce(policy->>'max_bytes','') !~ '^[1-9][0-9]{0,8}$'
 OR EXISTS (SELECT FROM unnest(ARRAY['source_id','monthly_url','reduced_url','license','attribution',
 'monthly_rights','reduced_rights']) k WHERE nullif(btrim(policy->>k),'') IS NULL)
 THEN RAISE EXCEPTION 'SUNAT_POLICY_INVALID'; END IF;
 IF p_capture IS NULL OR octet_length(p_capture) > (policy->>'max_bytes')::integer
 THEN RAISE EXCEPTION 'SUNAT_BATCH_BYTES'; END IF;
 payload := p_capture::jsonb;
 IF jsonb_typeof(payload) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'SUNAT_BATCH_SHAPE'; END IF;
 n := jsonb_array_length(payload);
 IF n NOT BETWEEN 1 AND (policy->>'max_rows')::integer THEN RAISE EXCEPTION 'SUNAT_BATCH_ROWS'; END IF;
 capture_hash := encode(sha256(convert_to(p_capture,'UTF8')),'hex');
 SELECT c.*, k.landing_page INTO q FROM saly.ventas_discovery_consultas c
 JOIN saly.ventas_discovery_catalogo k USING(catalog_version,source_id,connector_id,substep_code)
 JOIN saly.ventas_discovery_runs r ON r.id=c.run_id
 WHERE c.id=p_consulta AND c.source_id=policy->>'source_id' AND c.estado='FOUND' AND c.fin IS NOT NULL
 AND r.estado IN ('EN_EJECUCION','PARTIAL') AND c.cantidad_hallazgos=n
 AND c.evidencia_ref=(policy->>'monthly_url')||'#captura-json-sha256='||capture_hash
 AND k.habilitada AND k.persist_business_data AND k.rights_status='PERSISTENCIA_PERMITIDA'
 AND k.rights_checked_at IS NOT NULL AND k.rights_evidence_ref IS NOT NULL
 FOR UPDATE OF c FOR SHARE OF k,r;
 IF NOT FOUND THEN RAISE EXCEPTION 'SUNAT_QUERY_OR_RIGHTS'; END IF;
 first_obs := payload #> '{0,capture,observations}';
 IF EXISTS (
  SELECT FROM jsonb_array_elements(payload) x
  CROSS JOIN LATERAL (SELECT x->'capture' AS c) c0
  CROSS JOIN LATERAL (SELECT c#>'{observations,monthly}' AS m,c#>'{observations,reduced}' AS d) s
  WHERE c->>'version' IS DISTINCT FROM 'sunat.company.v1' OR c->>'source' IS DISTINCT FROM 'SUNAT'
  OR x->>'capture_sha256' IS DISTINCT FROM encode(sha256(convert_to(saly.ventas_capture_canonical_v1(c),'UTF8')),'hex')
  OR NOT (coalesce(m->'raw','{}') ?& ARRAY['Tipo','NroTrab','Departamento','Provincia','Distrito','PERIODO_PUBLICACION','Estado','Condicion','UBIGEO','Actividad_Economica_CIIU_revision3_Principal','Actividad_Economica_CIIU_revision3_Secundaria','Actividad_Economica_CIIU_revision4_Principal'])
  OR NOT (coalesce(d->'raw','{}') ?& ARRAY['estado','condicion','ubigeo'])
  OR (m->'raw') - ARRAY['RUC','Tipo','NroTrab','Departamento','Provincia','Distrito','PERIODO_PUBLICACION','Estado','Condicion','UBIGEO','Actividad_Economica_CIIU_revision3_Principal','Actividad_Economica_CIIU_revision3_Secundaria','Actividad_Economica_CIIU_revision4_Principal'] <> '{}'::jsonb
  OR (d->'raw') - ARRAY['RUC','nombre','estado','condicion','ubigeo'] <> '{}'::jsonb
  OR EXISTS(SELECT FROM jsonb_each((m->'raw')||(d->'raw')) f WHERE jsonb_typeof(f.value)<>'string')
  OR (x - ARRAY['capture','capture_sha256']) <> '{}'::jsonb
  OR (c - ARRAY['version','source','normalized','derived','observations']) <> '{}'::jsonb
  OR ((c->'observations') - ARRAY['monthly','reduced']) <> '{}'::jsonb
  OR ((c->'normalized') - ARRAY['ruc','razon_social','workers_integer_literal']) <> '{}'::jsonb
  OR ((c->'derived') - ARRAY['identity','quality','discrepancies']) <> '{}'::jsonb
  OR ((c#>'{derived,discrepancies}') - ARRAY['estado','condicion','ubigeo']) <> '{}'::jsonb
  OR jsonb_typeof(c#>'{derived,discrepancies,estado}') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(c#>'{derived,discrepancies,condicion}') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(c#>'{derived,discrepancies,ubigeo}') IS DISTINCT FROM 'boolean'
  OR c#>'{normalized,workers_integer_literal}' IS DISTINCT FROM
     CASE WHEN btrim(m#>>'{raw,NroTrab}') ~ '^[0-9]{1,9}$' THEN to_jsonb(btrim(m#>>'{raw,NroTrab}')::int) ELSE 'null'::jsonb END
  OR c#>>'{derived,identity}' IS DISTINCT FROM 'CANDIDATE'
  OR coalesce(c#>>'{normalized,ruc}','') !~ '^20[0-9]{9}$'
  OR btrim(m#>>'{raw,RUC}') IS DISTINCT FROM c#>>'{normalized,ruc}'
  OR btrim(d#>>'{raw,RUC}') IS DISTINCT FROM c#>>'{normalized,ruc}'
  OR nullif(btrim(d#>>'{raw,nombre}',chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(28)||chr(29)||chr(30)||chr(31)||chr(32)||chr(133)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)),'') IS NULL
  OR btrim(d#>>'{raw,nombre}',chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(28)||chr(29)||chr(30)||chr(31)||chr(32)||chr(133)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)) IS DISTINCT FROM c#>>'{normalized,razon_social}'
  OR m#>>'{evidence,url}' IS DISTINCT FROM policy->>'monthly_url'
  OR d#>>'{evidence,url}' IS DISTINCT FROM policy->>'reduced_url'
  OR EXISTS (SELECT FROM (VALUES ('monthly',m),('reduced',d)) AS v(variant,obs)
    WHERE (obs - ARRAY['raw','evidence']) <> '{}'::jsonb
    OR ((obs->'evidence') - ARRAY['url','ordinal','header_sha256','zip_sha256']) <> '{}'::jsonb
    OR coalesce(obs#>>'{evidence,ordinal}','') !~ '^[1-9][0-9]{0,8}$'
    OR coalesce(obs#>>'{evidence,zip_sha256}','') !~ '^[0-9a-f]{64}$'
    OR coalesce(obs#>>'{evidence,header_sha256}','') !~ '^[0-9a-f]{64}$'
    OR ((obs->'evidence')-'ordinal') IS DISTINCT FROM ((first_obs->variant->'evidence')-'ordinal'))
 ) THEN RAISE EXCEPTION 'SUNAT_CAPTURE_INVALID'; END IF;
 IF (SELECT count(DISTINCT x#>>'{capture,normalized,ruc}') FROM jsonb_array_elements(payload) x) <> n
 THEN RAISE EXCEPTION 'SUNAT_DUPLICATE_RUC'; END IF;
 snap := (first_obs#>>'{monthly,evidence,zip_sha256}')||'.'||(first_obs#>>'{reduced,evidence,zip_sha256}');
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array(q.source_id,snap,q.scope_key)::text,0));
 SELECT id,archivo_sha256 INTO prior FROM saly.ventas_discovery_ingestas WHERE
 (source_id,source_version,scope_key,batch_key)=(q.source_id,snap,q.scope_key,q.batch_key);
 IF FOUND THEN
  IF prior.archivo_sha256<>capture_hash OR (SELECT count(*) FROM saly.ventas_hallazgos
    WHERE ingesta_id=prior.id)<>n OR EXISTS(SELECT FROM jsonb_array_elements(payload) x WHERE
    NOT EXISTS(SELECT FROM saly.ventas_hallazgos h WHERE h.ingesta_id=prior.id AND
      h.ruc_candidato=x#>>'{capture,normalized,ruc}' AND h.captura_empresarial=x))
  THEN RAISE EXCEPTION 'SUNAT_REPLAY_DRIFT'; END IF;
  RETURN prior.id;
 END IF;
 IF EXISTS(SELECT FROM jsonb_array_elements(payload) x JOIN saly.ventas_hallazgos h
 ON h.ruc_candidato=x#>>'{capture,normalized,ruc}' JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE (i.source_id,i.source_version,i.scope_key)=(q.source_id,snap,q.scope_key))
 THEN RAISE EXCEPTION 'SUNAT_OVERLAPPING_BATCH'; END IF;
 INSERT INTO saly.ventas_discovery_ingestas(catalog_version,source_id,connector_id,substep_code,scope_key,
 batch_key,query_hash,consulta_evidencia_ref,source_version,recurso_url,licencia_codigo,atribucion,
 comprobacion_licencia_url,derechos_verificados,archivo_sha256,estado,filas_reportadas,run_ref,consulta_id)
 VALUES(q.catalog_version,q.source_id,q.connector_id,q.substep_code,q.scope_key,q.batch_key,q.query_hash,
 q.evidencia_ref,snap,policy->>'monthly_url',policy->>'license',policy->>'attribution',q.landing_page,
 true,capture_hash,'VALIDADA',n,q.run_ref,q.id) RETURNING id INTO result;
 INSERT INTO saly.ventas_hallazgos(ingesta_id,fila_origen,external_ref,nombre_provisional,ruc_literal,
 ruc_candidato,ubigeo_candidato,evidencia_ref,estado_identidad,captura_empresarial)
 SELECT result,(x#>>'{capture,observations,monthly,evidence,ordinal}')::integer,
 x#>>'{capture,normalized,ruc}',x#>>'{capture,normalized,razon_social}',x#>>'{capture,observations,monthly,raw,RUC}',
 x#>>'{capture,normalized,ruc}',CASE WHEN x#>>'{capture,observations,monthly,raw,UBIGEO}' ~ '^[0-9]{6}$'
 AND x#>>'{capture,observations,monthly,raw,UBIGEO}'=x#>>'{capture,observations,reduced,raw,ubigeo}'
 THEN x#>>'{capture,observations,monthly,raw,UBIGEO}' END,q.evidencia_ref,
 CASE WHEN x#>'{capture,derived,discrepancies}' @> '{"ubigeo":true}' THEN 'DISCREPANCIA' ELSE 'PENDIENTE' END,x
 FROM jsonb_array_elements(payload) x;
 RETURN result;
END $function$


DO $post$
BEGIN
 IF (SELECT count(*) FROM pg_proc WHERE oid='saly.ventas_sunat_ingesta_core_v1(uuid,text)'::regprocedure
 AND NOT prosecdef)<>1
 OR has_function_privilege('service_role','saly.ventas_sunat_ingesta_core_v1(uuid,text)','EXECUTE')
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')<>8
 OR (SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i
  ON h.ingesta_id=i.id WHERE i.source_id='PE-SUNAT-RUC')<>8000
 THEN RAISE EXCEPTION 'SUNAT_NORMALIZE_POSTSTATE_DRIFT'; END IF;
END $post$;
COMMIT;
