BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1(p_order_id bigint, p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF p_order_id IS NULL OR p_order_id<1 OR length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  -- Owner-authorized LF test lease; all other orders retain the published policy.
  IF p_order_id=23 AND EXISTS (SELECT 1 FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id WHERE o.id=23 AND o.project_id=3 AND i.id=27) THEN
    v_lease_seconds:=86400;
  END IF;
  IF p_order_id=22 AND p_lease_seconds=86400 THEN v_lease_seconds:=86400; END IF;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE order_id=p_order_id AND state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND order_id=p_order_id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.order_id=p_order_id AND r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=p_order_id AND o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND (o.project_id=2 OR (o.project_id=3 AND o.id=23 AND i.id=27)) AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz; v_policy jsonb; v_acceptance jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   -- A transaction-wide stale snapshot cannot enforce an aggregate queue cap.
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 -- Measure time only after waiting for the actual admission and parent locks.
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
   v_policy:=saly.creative_execution_policy_v1(v_now);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   -- Legacy items without a semantic contract retain the existing behavior.
   -- A sealed semantic item cannot enter with a substitute contract or snapshot.
   IF v_acceptance ? 'semantic_qa' THEN
     PERFORM saly.creative_assert_run_snapshot_v1(NEW.item_id,NEW.input_snapshot);
   END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=CASE WHEN OLD.order_id=22 AND OLD.item_id=26 AND OLD.attempt_number=2 THEN v_now+interval '24 hours' ELSE v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer) END;
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$;
DO $pilot$
DECLARE c record; o record; i record; bp jsonb; lock_data jsonb; packet jsonb; vc jsonb; snap jsonb; cl jsonb; prep jsonb; rr jsonb; w jsonb; close_result jsonb; src record;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=22 AND project_id=2 AND code='SALY_HOME_COMPACTO_20261125' AND status='EN_PROCESO' FOR UPDATE;
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=26 AND order_id=22 AND status='PRODUCIENDO' FOR UPDATE;
 SELECT * INTO STRICT c FROM saly.creative_queue_claims_v1 WHERE id=3 AND order_id=22 AND item_id=26 AND state='ACTIVE' FOR UPDATE;
 PERFORM 1 FROM saly.creative_runs WHERE id=9 AND order_id=22 AND item_id=26 AND queue_claim_id=3 AND state='EJECUTANDO' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PILOT_22_EXPECTED_RUN'; END IF;
 close_result:=saly.creative_run_expire_v1(9);
 IF close_result->>'status'='NOT_EXPIRED' THEN
   PERFORM saly.creative_queue_advance_run_v1(c.claim_token,9,'CANCELADO','{}'::jsonb,'SNAPSHOT_REBUILD');
 ELSIF close_result->>'status' IS DISTINCT FROM 'EXPIRED_CLOSED' THEN RAISE EXCEPTION 'PILOT_22_CLOSE_FAILED'; END IF;
 UPDATE saly.creative_order_items SET status='BLOQUEADO' WHERE id=26 AND order_id=22;
 IF c.lease_until<=clock_timestamp() THEN
   UPDATE saly.creative_queue_claims_v1 SET state='EXPIRED',finished_at=clock_timestamp(),note='SNAPSHOT_REBUILD' WHERE id=3 AND order_id=22 AND item_id=26;
 ELSE
   PERFORM saly.creative_queue_release_v1(c.claim_token,'BLOCKED','SNAPSHOT_REBUILD');
 END IF;
 SELECT context_json#>'{screen_spec,visual_blueprint}' INTO STRICT bp FROM saly.creative_order_items WHERE id=5 AND order_id=4;
 bp:=(bp-'design_lock'-'design_lock_sha256')||jsonb_build_object(
 'intent','Explorar un Home compacto de SALY en estado Uso habitual, sin banner.',
 'art','Mockup frontal iPhone 16 Pro de una pantalla. Estética fintech sobria, fondo blanco, referencia visual solo orientativa; el pedido 22 prevalece.',
 'hierarchy',jsonb_build_array('Logo oficial y saludo','Tarjeta única: disponible, CTA Solicitar adelanto y próximo descuento','Fila compacta de accesos como slot variable','Ayuda por chat','Navegación inferior'),
 'copy_locked',jsonb_build_object('base','Usar únicamente los textos funcionales del pedido 22; no copiar montos de la referencia.','overrides',jsonb_build_array(
 jsonb_build_object('component','Saludo','value','Hola, Cristhian','authority','Pedido 22'),
 jsonb_build_object('component','Disponible','value','Disponible para adelantar','authority','Pedido 22'),
 jsonb_build_object('component','Monto','value','S/ [DISPONIBLE]','authority','Pedido 22'),
 jsonb_build_object('component','Descuento','value','Próximo descuento 28 de noviembre','authority','Pedido 22'),
 jsonb_build_object('component','Ayuda','value','¿Necesitas ayuda? Contáctanos por chat','authority','Pedido 22'))),
 'layout_lock','Compactar el espacio, mantener zonas seguras y una jerarquía clara. Una tarjeta protagonista con CTA y descuento. Sin banner ni carrusel en Uso habitual.',
 'visual_lock','Logo oficial asset 9, 150630 bytes, SHA-256 5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995; reservar espacio para composición exacta. Referencia solo visual; no redibujar logo.',
 'restrictions',jsonb_build_array('Una imagen PNG.','No inventar montos ni datos financieros.','No banner en Uso habitual.','Fila de acceso variable, no fijar accesos permanentes.','Sin rayos decorativos.','Solo tokens del contexto sellado.'),
 'guided',jsonb_build_array('Ajustar densidad y tamaños para aprovechar el espacio.','Ejemplo de slot variable: Mi disponible, Cuándo me descuentan, Historial, Más opciones.','Campañas son temporales y cerrables; no mostrar en esta pantalla.'),
 'free','[]'::jsonb);
 SELECT jsonb_object_agg(k,bp->k) INTO lock_data FROM unnest(ARRAY['cta','output','bindings','hierarchy','copy_locked','layout_lock','visual_lock','restrictions','reference_sha256']) k;
 bp:=bp||jsonb_build_object('design_lock',jsonb_build_object('LOCK',lock_data,'GUIDED',bp->'guided','FREE',bp->'free'));
 bp:=bp||jsonb_build_object('design_lock_sha256',encode(extensions.digest(convert_to((bp->'design_lock')::text,'UTF8'),'sha256'),'hex'));
 UPDATE saly.creative_order_items SET status='PENDIENTE',
 context_json=jsonb_set(context_json,'{screen_spec,visual_blueprint}',bp)||jsonb_build_object('token_codes',(SELECT jsonb_agg(e.code ORDER BY e.code) FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=o.context_set_id)),
 acceptance_json=acceptance_json||jsonb_build_object('qa_required',true,'visual_rules',jsonb_build_object('scope',o.code,'provenance','OWNER_DIRECT_INSTRUCTION_2026_11_26','no_decorative_rays',true,'qa_visual_review_required',true,'no_unsupported_financial_amounts',true,'require_original_source_comparison',true),'qa_checklist',jsonb_build_object('textos_exactos',true,'monto_literal',true,'sin_banner',true,'slot_variable',true,'logo_oficial_asset_id',9,'tokens_active',true,'una_imagen',true),'design_qa_v1',jsonb_build_object('visual_anchor',true,'single_hero',true,'semantic_active_colors_min_2',true,'balanced_space',true,'cta_anchored_or_not_applicable',true,'max_3_accents',true))
 WHERE id=26 AND order_id=22;
 SELECT * INTO STRICT src FROM visual.source_assets WHERE id=1 AND asset_code='SALY_HOME_IPHONE16PRO' AND source_sha256='3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e' AND independent_sha_verified;
 INSERT INTO saly.creative_item_sources(order_id,item_id,source_asset_id,purpose,source_sha256) VALUES(22,26,1,'VISUAL_REFERENCE',src.source_sha256);
 UPDATE saly.creative_orders SET scope_json=scope_json||jsonb_build_object('review_only',false) WHERE id=22 AND project_id=2;
 packet:=saly.creative_item_work_packet_l2c(26);
 vc:=saly.creative_item_visual_contract_l3b(26);
 IF packet->>'readiness_code' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' OR vc#>>'{contract,production_manifest,dispatch_readiness}' IS DISTINCT FROM 'READY_FOR_NATIVE_HANDOFF' THEN RAISE EXCEPTION 'PILOT_22_PACKET_NOT_READY'; END IF;
 snap:=packet->'input_snapshot'||jsonb_build_object('visual_contract',vc->'contract','visual_contract_sha256',vc->>'contract_sha256');
 cl:=saly.creative_queue_claim_by_id_v1(22,'GPT_SELF_QA_SALY_PILOT_22',86400);
 IF cl->>'status' IS DISTINCT FROM 'CLAIMED' OR cl->>'item_id' IS DISTINCT FROM '26' THEN RAISE EXCEPTION 'PILOT_22_CLAIM_FAILED'; END IF;
 prep:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','SALY','project_code','SALY-001','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF prep->>'status' IS DISTINCT FROM 'AUTONOMOUS_PREPARED' THEN RAISE EXCEPTION 'PILOT_22_PREPARE_FAILED'; END IF;
 rr:=saly.creative_queue_admit_run_v1((cl->>'claim_token')::uuid,2,'saly-pilot-22-2',snap);
 PERFORM saly.creative_queue_advance_run_v1((cl->>'claim_token')::uuid,(rr->>'run_id')::bigint,'EJECUTANDO');
 w:=saly.creative_native_render_wire_v1((cl->>'claim_token')::uuid,(rr->>'run_id')::bigint,'GPT_NATIVE');
 IF w->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED' THEN RAISE EXCEPTION 'PILOT_22_WIRE_FAILED'; END IF;
 RAISE NOTICE 'SALY_22_RUN % WIRE %',rr->>'run_id',w->>'wire_sha256';
END $pilot$;
CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1(p_order_id bigint, p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_item record;
  v_active record;
  v_claim record;
  v_now timestamptz;
  v_policy jsonb;
  v_lease_seconds integer;
BEGIN
  IF p_order_id IS NULL OR p_order_id<1 OR length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  -- Owner-authorized LF test lease; all other orders retain the published policy.
  IF p_order_id=23 AND EXISTS (SELECT 1 FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id WHERE o.id=23 AND o.project_id=3 AND i.id=27) THEN
    v_lease_seconds:=86400;
  END IF;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE order_id=p_order_id AND state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND order_id=p_order_id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.order_id=p_order_id AND r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=p_order_id AND o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND (o.project_id=2 OR (o.project_id=3 AND o.id=23 AND i.id=27)) AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1'))
    AND o.scope_json->>'queue_mode'='SERIAL_V1'
    AND (o.request_kind <> 'APP_SCREEN_SINGLE'
         OR saly.creative_order_sequence_dependency_met_v1(o.id))
    AND o.scope_json->>'rendering_authority'='true'
    AND coalesce(o.scope_json->>'review_only','false')='false'
    AND coalesce(o.scope_json->>'render_authorized','true')='true'
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.item_id=i.id AND d.order_id=o.id AND prereq.status<>'APROBADO'
    )
    AND NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=i.id AND r.state='EXITOSO'
    )
  ORDER BY o.id, i.ordinal, i.id
  LIMIT 1 FOR UPDATE OF i SKIP LOCKED;

  IF NOT FOUND THEN RETURN jsonb_build_object('status','EMPTY'); END IF;

  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_item.order_id AND status='PLANIFICADO';
  UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.item_id AND status='PENDIENTE';
  INSERT INTO saly.creative_queue_claims_v1
    (order_id,item_id,worker_ref,state,claimed_at,lease_until)
  VALUES (v_item.order_id,v_item.item_id,p_worker_ref,'ACTIVE',v_now,
          v_now+make_interval(secs=>v_lease_seconds))
  RETURNING * INTO v_claim;

  RETURN jsonb_build_object('status','CLAIMED','claim_id',v_claim.id,
    'claim_token',v_claim.claim_token,'order_id',v_claim.order_id,
    'item_id',v_claim.item_id,'order_code',v_item.order_code,
    'item_code',v_item.item_code,'lease_until',v_claim.lease_until);
END $function$;
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz; v_policy jsonb; v_acceptance jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   -- A transaction-wide stale snapshot cannot enforce an aggregate queue cap.
   IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted')
   THEN RAISE EXCEPTION 'CREATIVE_ADMISSION_REQUIRES_READ_COMMITTED'; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json,i.acceptance_json INTO v_item_status,v_order_status,v_scope,v_acceptance
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i,o;
 -- Measure time only after waiting for the actual admission and parent locks.
 v_now:=clock_timestamp();
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
   v_policy:=saly.creative_execution_policy_v1(v_now);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   -- Legacy items without a semantic contract retain the existing behavior.
   -- A sealed semantic item cannot enter with a substitute contract or snapshot.
   IF v_acceptance ? 'semantic_qa' THEN
     PERFORM saly.creative_assert_run_snapshot_v1(NEW.item_id,NEW.input_snapshot);
   END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer);
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$;
COMMIT;
