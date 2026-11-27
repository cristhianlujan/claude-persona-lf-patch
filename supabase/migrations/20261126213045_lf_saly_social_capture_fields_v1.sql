-- SALY U07: extend capture metadata; preserve event evidence and existing writer.
-- No source activation, copy rights fabricated, raw posts, grants or changes to SUNAT.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';

ALTER TABLE saly.ventas_social_publicaciones_v1
 ADD COLUMN copy_text text CHECK (copy_text IS NULL OR length(btrim(copy_text))>0),
 ADD COLUMN is_partial boolean,
 ADD COLUMN content_type text CHECK (content_type IN
   ('PUBLICACION','REEL','VIDEO','HISTORIA','ARTICULO','OTRO','NO_DETERMINADO')),
 ADD COLUMN text_origin text CHECK (text_origin IN
   ('COPY_EMISOR','DESCRIPCION_VIDEO','TITULO_VIDEO','TEXTO_ARTICULO','RESUMEN','NO_DETERMINADO')),
 ADD COLUMN alternative_url text CHECK (alternative_url IS NULL OR alternative_url ~ '^https://[^ ]+$'),
 ADD COLUMN source_published_date date,
 ADD COLUMN source_published_time time without time zone;
COMMENT ON COLUMN saly.ventas_social_publicaciones_v1.copy_text IS
 'Texto institucional del emisor, cuando su persistencia está autorizada; no sustituye el resumen factual.';
COMMENT ON COLUMN saly.ventas_social_publicaciones_v1.is_partial IS
 'TRUE: texto incompleto; FALSE: sin corte observado o recuperado y validado; NULL: no determinado. No equivale a cobertura histórica.';
COMMENT ON COLUMN saly.ventas_social_publicaciones_v1.source_published_date IS
 'Fecha literal mostrada por la fuente; no presupone zona horaria.';
COMMENT ON COLUMN saly.ventas_social_publicaciones_v1.source_published_time IS
 'Hora literal mostrada, si consta; NULL si ausente, sin inferir medianoche.';

-- Distinguish the existing rights scope for simple facts from authorization to retain copy.
ALTER TABLE saly.ventas_discovery_catalogo
 ADD COLUMN copy_text_permitted boolean NOT NULL DEFAULT false,
 ADD CONSTRAINT saly_social_copy_scope_existing_rights CHECK
  (NOT copy_text_permitted OR (persist_business_data AND habilitada AND
    rights_status='PERSISTENCIA_PERMITIDA' AND rights_checked_at IS NOT NULL AND
    length(btrim(coalesce(rights_evidence_ref,'')))>0));
COMMENT ON COLUMN saly.ventas_discovery_catalogo.copy_text_permitted IS
 'Alcance de persistencia del copy, acreditado por la evidencia de derechos de esta misma fuente. FALSE no cambia permisos existentes para hechos.';

-- Normalized read model of canonical channel codes already specified by
-- skills/ai_sales_discovery/queries/ventas_social_channel_inventory_v1.sql.
-- The operational catalog remains the sole authority; a listed channel is not admitted.
CREATE VIEW saly.v_ventas_social_fuentes_v1 WITH (security_invoker=true) AS
WITH expected(source_id,source_name,source_type,source_description) AS (VALUES
 ('PE-FACEBOOK','Facebook','RED_SOCIAL','Publicaciones institucionales en Facebook'),
 ('PE-INSTAGRAM','Instagram','RED_SOCIAL','Publicaciones institucionales en Instagram'),
 ('PE-LINKEDIN','LinkedIn','RED_SOCIAL','Publicaciones institucionales en LinkedIn'),
 ('PE-TIKTOK','TikTok','RED_SOCIAL','Publicaciones institucionales en TikTok'),
 ('PE-YOUTUBE','YouTube','RED_SOCIAL','Contenido institucional en YouTube'),
 ('PE-WEBS-CORPORATIVAS','Web corporativa','WEB','Publicaciones en sitios corporativos'),
 ('PE-NEWS-FACTS-CORREO','Diario Correo','MEDIO_DIGITAL','Hechos de reportes editoriales de Diario Correo'),
 ('PE-REVISTAS-DIGITALES','Revistas digitales','MEDIO_DIGITAL','Publicaciones de revistas digitales'),
 ('PE-FOROS','Foros','FORO','Publicaciones en foros'),
 ('PE-OTROS-MEDIOS','Otros medios digitales','MEDIO_DIGITAL','Otras publicaciones digitales'))
SELECT e.source_id,e.source_name,e.source_type,e.source_description,
 c.catalog_version,c.rights_status,
 coalesce(c.habilitada,false) AS habilitada,
 coalesce(c.persist_business_data,false) AS persist_business_data,
 coalesce(c.copy_text_permitted,false) AS copy_text_permitted,
 CASE WHEN c.source_id IS NULL THEN 'NO_REGISTRADA'
      WHEN c.habilitada THEN 'REGISTRADA_HABILITADA'
      ELSE 'REGISTRADA_NO_HABILITADA' END AS estado_catalogo
FROM expected e
LEFT JOIN LATERAL (SELECT c.* FROM saly.ventas_discovery_catalogo c
 WHERE c.source_id=e.source_id ORDER BY c.created_at DESC,c.catalog_version DESC LIMIT 1) c ON true;
REVOKE ALL ON saly.v_ventas_social_fuentes_v1 FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON VIEW saly.v_ventas_social_fuentes_v1 IS
 'Nombres y tipos canónicos de canales. El catálogo operativo determina autorización, no esta vista.';

CREATE OR REPLACE FUNCTION saly.ventas_social_ingesta_execute_v1(
    p_execution text, p_owner text, p_fence bigint, p_record jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,saly,public AS $social$
DECLARE
  op public.lf_operation_execution%ROWTYPE;
  cat saly.ventas_discovery_catalogo%ROWTYPE;
  rr saly.ventas_social_runs_v1%ROWTYPE;
  ev_id uuid; original_claim uuid; original_source text;
  pub_id uuid; old_hash text; old_event_id uuid; claim_id uuid;
  v_source_id text; v_business_key text; v_external_ref text;
  v_event_key text; v_claim_key text; v_claim_state text; v_source_hash text;
  effect_key text; rec_hash text; reserv jsonb; receipt jsonb;
  v_start timestamptz; v_end timestamptz; v_date timestamptz;
  row_count integer;
BEGIN
  IF nullif(btrim(p_execution),'') IS NULL OR nullif(btrim(p_owner),'') IS NULL
     OR coalesce(p_fence,0)<=0 OR jsonb_typeof(p_record) IS DISTINCT FROM 'object'
     THEN RAISE EXCEPTION 'SOCIAL_INGESTA_CALL_CONTRACT'; END IF;
  v_source_id := p_record->>'source_id';
  v_business_key := p_record->>'business_key';
  v_external_ref := p_record->>'external_ref';
  v_event_key := p_record->>'event_key';
  v_claim_key := p_record->>'claim_key';
  v_claim_state := p_record->>'claim_state';
  v_source_hash := p_record->>'source_sha256';
  IF v_source_id IS NULL OR v_business_key IS NULL OR v_external_ref IS NULL
     OR v_event_key IS NULL OR v_claim_key IS NULL
     OR coalesce(length(btrim(v_business_key)),0)=0
     OR coalesce(length(btrim(v_event_key)),0)=0
     OR coalesce(length(btrim(v_external_ref)),0)=0
     OR v_claim_state NOT IN ('ANUNCIADO','REALIZADO','IMPLEMENTADO','NO_DETERMINADO')
     OR v_source_hash IS NULL OR v_source_hash !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(p_record->>'summary_non_personal'),'') IS NULL
     OR nullif(btrim(p_record->>'event_title'),'') IS NULL
     OR (p_record->>'url') !~ '^https://[^ ]+$'
     OR coalesce(p_record->>'identity_state','')<>'VALIDADA'
     OR coalesce(p_record->>'match_state','')<>'REVISADO'
     THEN RAISE EXCEPTION 'SOCIAL_INGESTA_RECORD_CONTRACT'; END IF;
  v_start:=(p_record->>'window_start')::timestamptz;
  v_end:=(p_record->>'window_end')::timestamptz;
  v_date:=(p_record->>'published_at')::timestamptz;
  IF v_start IS NULL OR v_end IS NULL OR v_date IS NULL
     OR v_start>=v_end OR v_date<v_start OR v_date>v_end
     THEN RAISE EXCEPTION 'SOCIAL_INGESTA_WINDOW'; END IF;

  SELECT * INTO op FROM public.lf_operation_execution
   WHERE execution_id=p_execution FOR UPDATE;
  IF NOT FOUND OR op.operation_code IS DISTINCT FROM 'INGESTA_EMPRESARIAL_SALY'
    OR op.target_type IS DISTINCT FROM 'DISCOVERY_SOURCE'
    OR op.target_code IS DISTINCT FROM v_source_id
    OR op.status IS DISTINCT FROM 'IN_PROGRESS'
    OR op.lease_owner IS DISTINCT FROM p_owner
    OR op.lease_fence IS DISTINCT FROM p_fence
    OR op.lease_expires_at IS NULL OR op.lease_expires_at<=clock_timestamp()
    THEN RAISE EXCEPTION 'SOCIAL_INGESTA_OPERATION_LEASE'; END IF;
  -- Source-specific contract: never treat SUNAT's limited contract as authority.
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_contracts
      WHERE operation_code=op.operation_code
      AND contract_code='SALY_SOCIAL_INGESTION_V1'
      AND status='ACTIVE_ENFORCEMENT') THEN
      RAISE EXCEPTION 'SOCIAL_INGESTA_CONTRACT_NOT_ENABLED'; END IF;
  IF op.manifest->'social_scope' IS DISTINCT FROM jsonb_build_object(
       'source_id',v_source_id,'business_key',v_business_key,
       'window_start',p_record->>'window_start',
       'window_end',p_record->>'window_end')
      THEN RAISE EXCEPTION 'SOCIAL_INGESTA_OPERATION_SCOPE'; END IF;
  SELECT * INTO cat FROM saly.ventas_discovery_catalogo
   WHERE saly.ventas_discovery_catalogo.source_id=v_source_id AND rights_status='PERSISTENCIA_PERMITIDA'
     AND rights_checked_at IS NOT NULL AND habilitada AND persist_business_data
     AND rights_evidence_ref=p_record->>'rights_evidence_ref' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SOCIAL_INGESTA_SOURCE_RIGHTS'; END IF;
  -- Existing rights for facts do not authorize reproduction of full copy.
  IF p_record->>'copy_text' IS NOT NULL AND NOT cat.copy_text_permitted THEN
    RAISE EXCEPTION 'SOCIAL_INGESTA_COPY_SCOPE';
  END IF;
  IF p_record->>'is_partial' IS NOT NULL
     AND jsonb_typeof(p_record->'is_partial') IS DISTINCT FROM 'boolean' THEN
    RAISE EXCEPTION 'SOCIAL_INGESTA_PARTIAL_TYPE';
  END IF;


  rec_hash:=encode(sha256(convert_to(p_record::text,'UTF8')),'hex');
  effect_key:='SOCIAL:'||encode(sha256(convert_to(
      v_source_id||':'||v_business_key||':'||v_external_ref||':'||v_claim_key||':'||v_claim_state,'UTF8')),'hex');
  reserv:=public.fn_lf_operation_reserve_effect_v1(
      p_execution,p_owner,p_fence,effect_key,rec_hash,effect_key,p_execution);
  IF reserv->>'result'='REPLAY_SUCCEEDED_EFFECT' THEN
    RETURN reserv->'receipt';
  END IF;
  IF reserv->>'result' IS DISTINCT FROM 'EFFECT_RESERVED_NEW'
      OR reserv->'dispatch_permitted' IS DISTINCT FROM 'true'::jsonb THEN
      RAISE EXCEPTION 'SOCIAL_INGESTA_RESERVATION_REQUIRED'; END IF;

  INSERT INTO saly.ventas_social_runs_v1 (
      run_ref,catalog_version,source_id,business_key,window_start,window_end,
      status,rights_evidence_ref)
    VALUES(p_execution,cat.catalog_version,v_source_id,v_business_key,
      v_start,v_end,'EN_EJECUCION',cat.rights_evidence_ref)
    ON CONFLICT (run_ref) DO NOTHING;
  SELECT * INTO STRICT rr FROM saly.ventas_social_runs_v1
    WHERE run_ref=p_execution FOR UPDATE;
  IF rr.catalog_version IS DISTINCT FROM cat.catalog_version
    OR rr.source_id IS DISTINCT FROM v_source_id
    OR rr.business_key IS DISTINCT FROM v_business_key
    OR rr.window_start IS DISTINCT FROM v_start OR rr.window_end IS DISTINCT FROM v_end
    OR rr.rights_evidence_ref IS DISTINCT FROM cat.rights_evidence_ref
    THEN RAISE EXCEPTION 'SOCIAL_INGESTA_RUN_REPLAY_DRIFT'; END IF;

  INSERT INTO saly.ventas_social_eventos_v1
      (business_key,event_key,event_title,identity_state,match_state)
  VALUES (v_business_key,v_event_key,p_record->>'event_title','VALIDADA','REVISADO')
  ON CONFLICT (business_key,event_key) DO NOTHING;
  SELECT id INTO STRICT ev_id FROM saly.ventas_social_eventos_v1
    WHERE ventas_social_eventos_v1.business_key=v_business_key
      AND ventas_social_eventos_v1.event_key=v_event_key FOR UPDATE;

  SELECT id,source_sha256,event_id INTO pub_id,old_hash,old_event_id FROM saly.ventas_social_publicaciones_v1
   WHERE ventas_social_publicaciones_v1.business_key=v_business_key
     AND ventas_social_publicaciones_v1.source_id=v_source_id
     AND ventas_social_publicaciones_v1.external_ref=v_external_ref FOR UPDATE;
  IF FOUND AND (old_hash IS DISTINCT FROM v_source_hash OR old_event_id IS DISTINCT FROM ev_id) THEN
    RAISE EXCEPTION 'SOCIAL_INGESTA_SOURCE_VERSION_CONFLICT'; END IF;

  SELECT a.id,a.source_id INTO original_claim,original_source
    FROM saly.ventas_social_afirmaciones_v1 a
   WHERE a.event_id=ev_id AND a.claim_key=v_claim_key AND a.claim_state=v_claim_state
   ORDER BY a.created_at,a.id LIMIT 1;
  IF original_claim IS NOT NULL AND original_source=v_source_id THEN
    receipt:=jsonb_build_object('result','DUPLICADO_INTRACANAL','run_ref',p_execution,
                                'source_id',v_source_id,'event_id',ev_id,'inserted_claims',0);
  ELSIF original_claim IS NOT NULL THEN
    INSERT INTO saly.ventas_social_concurrencias_v1(
      event_id,original_claim_id,confirming_source_id,confirming_external_ref,
      confirming_url,relation,match_evidence_sha256,reviewed)
    VALUES(ev_id,original_claim,v_source_id,v_external_ref,p_record->>'url',
      'MISMO_HECHO',rec_hash,true)
    ON CONFLICT (original_claim_id,confirming_source_id,confirming_external_ref,relation)
      DO NOTHING;
    receipt:=jsonb_build_object('result','CONCURRENCIA_INTERCANAL','run_ref',p_execution,
                                'source_id',v_source_id,'event_id',ev_id,'inserted_claims',0);
  ELSE
    IF pub_id IS NULL THEN
      INSERT INTO saly.ventas_social_publicaciones_v1(
        run_id,event_id,business_key,source_id,external_ref,url,published_at,
        source_sha256,summary_non_personal,copy_text,is_partial,content_type,
        text_origin,alternative_url,source_published_date,source_published_time)
      VALUES(rr.id,ev_id,v_business_key,v_source_id,v_external_ref,
        p_record->>'url',v_date,v_source_hash,p_record->>'summary_non_personal',
        p_record->>'copy_text',(p_record->>'is_partial')::boolean,
        p_record->>'content_type',p_record->>'text_origin',p_record->>'alternative_url',
        (p_record->>'source_published_date')::date,(p_record->>'source_published_time')::time)
      RETURNING id INTO pub_id;
    END IF;
    INSERT INTO saly.ventas_social_afirmaciones_v1(
       event_id,publicacion_id,source_id,claim_key,claim_state,polarity)
      VALUES(ev_id,pub_id,v_source_id,v_claim_key,v_claim_state,
        coalesce(p_record->>'polarity','NEUTRA'))
      ON CONFLICT(event_id,source_id,claim_key,claim_state) DO NOTHING
      RETURNING id INTO claim_id;
    IF claim_id IS NULL THEN
      RAISE EXCEPTION 'SOCIAL_INGESTA_CLAIM_CONFLICT'; END IF;
    -- A different channel may add a NEW phase to the same canonical event.
    SELECT a.id,a.source_id INTO original_claim,original_source
      FROM saly.ventas_social_afirmaciones_v1 a
      WHERE a.event_id=ev_id AND a.id<>claim_id AND a.source_id<>v_source_id
      ORDER BY a.created_at,a.id LIMIT 1;
    IF original_claim IS NOT NULL THEN
      INSERT INTO saly.ventas_social_concurrencias_v1 (
        event_id,original_claim_id,confirming_source_id,confirming_external_ref,
        confirming_url,relation,match_evidence_sha256,reviewed)
      VALUES(ev_id,original_claim,v_source_id,v_external_ref,p_record->>'url',
        'COMPLEMENTA',rec_hash,true)
      ON CONFLICT (original_claim_id,confirming_source_id,confirming_external_ref,relation)
        DO NOTHING;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM saly.ventas_social_afirmaciones_v1
        WHERE id=claim_id AND event_id=ev_id AND publicacion_id=pub_id)
      THEN RAISE EXCEPTION 'SOCIAL_INGESTA_READBACK'; END IF;
    receipt:=jsonb_build_object('result','INSERTADO','run_ref',p_execution,
                                'source_id',v_source_id,'event_id',ev_id,
                                'claim_id',claim_id,'inserted_claims',1);
  END IF;
  PERFORM public.fn_lf_operation_mark_effect_succeeded_v1(
      p_execution,p_owner,p_fence,effect_key,receipt,p_execution);
  RETURN receipt;
END $social$;


DO $post$
BEGIN
 IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='saly'
   AND table_name='ventas_social_publicaciones_v1' AND column_name IN
   ('copy_text','is_partial','content_type','text_origin','alternative_url',
    'source_published_date','source_published_time'))<>7
 OR (SELECT count(*) FROM saly.v_ventas_social_fuentes_v1)<>10
 OR NOT EXISTS (SELECT 1 FROM saly.v_ventas_social_fuentes_v1
   WHERE source_id='PE-FACEBOOK' AND source_name='Facebook' AND source_type='RED_SOCIAL')
 OR EXISTS (SELECT 1 FROM saly.ventas_discovery_catalogo WHERE copy_text_permitted)
 THEN RAISE EXCEPTION 'SALY_SOCIAL_CAPTURE_FIELDS_POSTSTATE'; END IF;
END $post$;
COMMIT;
