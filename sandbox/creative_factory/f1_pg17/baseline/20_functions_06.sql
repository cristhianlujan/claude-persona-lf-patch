CREATE OR REPLACE FUNCTION saly.creative_queue_admit_run_v1(p_token uuid, p_attempt integer, p_idempotency_key text, p_input_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_run_id bigint;
BEGIN
  IF p_token IS NULL OR p_attempt IS NULL OR p_attempt<1
    OR nullif(btrim(coalesce(p_idempotency_key,'')),'') IS NULL
    OR jsonb_typeof(p_input_snapshot) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  PERFORM set_config('saly.creative_queue_token',p_token::text,true);
  INSERT INTO saly.creative_runs(
      id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot,queue_claim_id)
  VALUES (nextval('saly.creative_runs_id_seq'::regclass),
      v_claim.order_id,v_claim.item_id,p_attempt,p_idempotency_key,'EN_COLA',
      p_input_snapshot,v_claim.id)
  RETURNING id INTO v_run_id;
  RETURN jsonb_build_object('run_id',v_run_id,'claim_id',v_claim.id,'state','EN_COLA');
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_advance_run_v1(p_token uuid, p_run_id bigint, p_next_state text, p_output_evidence jsonb DEFAULT '{}'::jsonb, p_error_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_run record;
BEGIN
  IF p_token IS NULL OR p_run_id IS NULL
    OR p_next_state NOT IN ('EJECUTANDO','EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
    OR jsonb_typeof(p_output_evidence) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  SELECT * INTO v_run FROM saly.creative_runs
  WHERE id=p_run_id AND queue_claim_id=v_claim.id
    AND order_id=v_claim.order_id AND item_id=v_claim.item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_NOT_BOUND'; END IF;
  IF (p_next_state='EJECUTANDO' AND v_run.state<>'EN_COLA')
     OR (p_next_state IN ('EXITOSO','FALLIDO','BLOQUEADO') AND v_run.state<>'EJECUTANDO')
     OR (p_next_state='CANCELADO' AND v_run.state NOT IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_INVALID_TRANSITION'; END IF;
  PERFORM set_config('saly.creative_queue_token',p_token::text,true);
  IF p_next_state='EJECUTANDO' THEN
    UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref=v_claim.worker_ref,
      updated_at=clock_timestamp() WHERE id=v_run.id;
  ELSE
    UPDATE saly.creative_runs SET state=p_next_state,
      output_evidence=CASE WHEN p_next_state='EXITOSO' THEN p_output_evidence ELSE output_evidence END,
      error_code=p_error_code,updated_at=clock_timestamp()
      WHERE id=v_run.id;
  END IF;
  RETURN jsonb_build_object('run_id',v_run.id,'state',p_next_state,'claim_id',v_claim.id);
END $function$
;

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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_claim_next_v1(p_worker_ref text, p_lease_seconds integer DEFAULT NULL::integer)
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
  IF length(btrim(coalesce(p_worker_ref,''))) NOT BETWEEN 1 AND 128
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;

  -- Protect selection + expired reclamation as one transaction, across workers.
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  -- Fail before claiming if an operational policy has not been published.
  -- The existing creative run admission reads the same source of truth.
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  IF p_lease_seconds IS NOT NULL AND p_lease_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT id,lease_until,item_id INTO v_active
  FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE' FOR UPDATE;
  IF FOUND THEN
    IF v_active.lease_until > v_now THEN
      RETURN jsonb_build_object('status','BUSY','claim_id',v_active.id);
    END IF;
    -- Old fencing token is invalid after this update. Preserve audit trail.
    UPDATE saly.creative_queue_claims_v1
    SET state='EXPIRED',finished_at=v_now,note='LEASE_EXPIRED'
    WHERE id=v_active.id AND state='ACTIVE';
  END IF;

  -- Admission is intentionally conservative: review-only and legacy orders excluded.
  -- Caller must still validate semantic/brand sources, generate and QA within lease.
  IF EXISTS (SELECT 1 FROM saly.creative_runs r
             WHERE r.state IN ('EN_COLA','EJECUTANDO')) THEN
    RETURN jsonb_build_object('status','RUN_ACTIVE','claim_id',NULL);
  END IF;

  SELECT i.id AS item_id,o.id AS order_id,i.code AS item_code,o.code AS order_code
  INTO v_item
  FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.status IN ('PLANIFICADO','EN_PROCESO')
    AND (i.status='LISTO' OR (i.status='PENDIENTE' AND o.project_id=2 AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1' AND o.scope_json->>'module'='Solicitar adelanto'))
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
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_heartbeat_v1(p_token uuid, p_extend_seconds integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_now timestamptz; v_policy jsonb; v_lease_seconds integer;
BEGIN
  IF p_token IS NULL THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  v_policy:=saly.creative_execution_policy_v1(v_now);
  v_lease_seconds:=(v_policy->>'LEASE_SECONDS')::integer;
  IF p_extend_seconds IS NOT NULL AND p_extend_seconds IS DISTINCT FROM v_lease_seconds
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEASE_POLICY_MISMATCH'; END IF;
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  UPDATE saly.creative_queue_claims_v1
  SET lease_until=v_now+make_interval(secs=>v_lease_seconds)
  WHERE id=v_claim.id;
  RETURN jsonb_build_object('status','EXTENDED','claim_id',v_claim.id);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_native_delivery_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c record; r record; i record;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' THEN
   IF OLD.state='VERIFIED' THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE'; END IF;
   IF OLD.state<>'STAGED' OR NEW.state<>'VERIFIED'
      OR NEW.id IS DISTINCT FROM OLD.id OR NEW.claim_id IS DISTINCT FROM OLD.claim_id
      OR NEW.run_id IS DISTINCT FROM OLD.run_id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id
      OR NEW.artifact_ref IS DISTINCT FROM OLD.artifact_ref
      OR NEW.artifact_sha256 IS DISTINCT FROM OLD.artifact_sha256
      OR NEW.host_surface IS DISTINCT FROM OLD.host_surface
      OR NEW.message_id IS DISTINCT FROM OLD.message_id
      OR NEW.executor_mode IS DISTINCT FROM OLD.executor_mode
      OR NEW.host_evidence_ref IS DISTINCT FROM OLD.host_evidence_ref
      OR NEW.host_evidence_sha256 IS DISTINCT FROM OLD.host_evidence_sha256
      OR NEW.recorded_at IS DISTINCT FROM OLD.recorded_at
   THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_PROMOTION_INVALID'; END IF;
 ELSE
   IF NEW.state<>'STAGED' OR NEW.verified_at IS NOT NULL OR NEW.verifier_ref IS NOT NULL
   THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_STAGED_ONLY'; END IF;
 END IF;

 SELECT * INTO c FROM saly.creative_queue_claims_v1 WHERE id=NEW.claim_id FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=NEW.run_id FOR UPDATE;
 SELECT status INTO i FROM saly.creative_order_items
 WHERE id=NEW.item_id AND order_id=NEW.order_id FOR UPDATE;
 IF NOT FOUND OR c.id IS NULL OR r.id IS NULL
 OR c.order_id IS DISTINCT FROM NEW.order_id OR c.item_id IS DISTINCT FROM NEW.item_id
 OR r.order_id IS DISTINCT FROM NEW.order_id OR r.item_id IS DISTINCT FROM NEW.item_id
 OR r.queue_claim_id IS DISTINCT FROM c.id
 OR c.state IS DISTINCT FROM 'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.state IS DISTINCT FROM 'EXITOSO' OR i.status IS DISTINCT FROM 'TERMINADO'
 OR r.output_evidence->>'artifact_ref' IS DISTINCT FROM NEW.artifact_ref
 OR r.output_evidence->>'sha256' IS DISTINCT FROM NEW.artifact_sha256
 THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_BINDING_NOT_READY'; END IF;
 IF TG_OP='UPDATE' THEN
    IF lower(btrim(NEW.verifier_ref))=lower(btrim(c.worker_ref))
    THEN RAISE EXCEPTION 'CREATIVE_NATIVE_DELIVERY_SELF_VERIFICATION'; END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_native_dispatch_reservation_immutable_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
BEGIN
 RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_IMMUTABLE';
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_native_reserve_dispatch_v1(p_claim_token uuid, p_run_id bigint, p_executor_mode text, p_expected_wire_sha256 text, p_archive_reported_sha256 text, p_request_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_now timestamptz;
 v_mode text;
 v_wire jsonb;
 v_claim record;
 v_existing record;
 v_rowid bigint;
 v_provider text;
BEGIN
 IF p_claim_token IS NULL OR p_run_id IS NULL OR p_run_id<1
   OR p_executor_mode IS NULL OR p_executor_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE')
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_ARGUMENT_INVALID'; END IF;
 IF p_expected_wire_sha256 IS NULL OR p_expected_wire_sha256 !~ '^[0-9a-f]{64}$'
   OR p_archive_reported_sha256 IS NULL OR p_archive_reported_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_HASH_PIN_INVALID'; END IF;
 IF p_request_key IS NULL OR length(btrim(p_request_key)) NOT BETWEEN 1 AND 128
   OR p_request_key !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_IDEMPOTENCY_KEY_INVALID'; END IF;
 v_mode:=p_executor_mode;

 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 -- Live V05 canonical reconstruction under the same serial lock.
 -- Raises on expired claim, mismatched RUN/policy/order, source drift.
 v_wire:=saly.creative_native_render_wire_v1(p_claim_token,p_run_id,v_mode);
 IF v_wire->>'schema_version' IS DISTINCT FROM 'SALY_NATIVE_RENDER_WIRE_V1'
   OR v_wire->>'status' IS DISTINCT FROM 'RENDER_WIRE_FROZEN_AUTHORIZED'
   OR v_wire->'render_authorized' IS DISTINCT FROM 'true'::jsonb
   OR v_wire->'native_transmitted' IS DISTINCT FROM 'false'::jsonb
   OR v_wire->'db_done_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_NOT_READY'; END IF;
 IF v_wire->>'wire_sha256' IS DISTINCT FROM p_expected_wire_sha256
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_DRIFT'; END IF;

 SELECT c.id AS claim_id,c.order_id,c.item_id,c.lease_until,c.state AS claim_state,
        c.worker_ref AS claim_worker,
        r.id AS run_id,r.state AS run_state,r.worker_ref AS run_worker,
        r.queue_claim_id,r.deadline_at,r.input_snapshot
 INTO v_claim
 FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_runs r ON r.queue_claim_id=c.id
 WHERE c.claim_token=p_claim_token AND r.id=p_run_id
 FOR UPDATE OF c,r;
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RUN_CLAIM_NOT_BOUND'; END IF;
 v_now:=clock_timestamp();
 IF v_claim.claim_state IS DISTINCT FROM 'ACTIVE'
   OR v_claim.run_state IS DISTINCT FROM 'EJECUTANDO'
   OR v_claim.lease_until<=v_now OR v_claim.deadline_at<=v_now
   OR v_claim.claim_worker IS DISTINCT FROM v_claim.run_worker
   OR v_wire->>'claim_id' IS DISTINCT FROM v_claim.claim_id::text
   OR v_wire->>'order_id' IS DISTINCT FROM v_claim.order_id::text
   OR v_wire->>'item_id' IS DISTINCT FROM v_claim.item_id::text
   OR v_wire->>'run_id' IS DISTINCT FROM v_claim.run_id::text
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_LIVE_FENCE_EXPIRED'; END IF;
 v_provider:=CASE v_mode WHEN 'GPT_NATIVE' THEN 'OPENAI_CHATGPT_NATIVE'
                       ELSE 'ANTHROPIC_CLAUDE_NATIVE' END;
 IF v_wire->>'executor_provider' IS DISTINCT FROM v_provider
 THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_PROVIDER_MISMATCH'; END IF;

 SELECT * INTO v_existing
 FROM saly.creative_queue_native_dispatch_reservations_v1
 WHERE run_id=v_claim.run_id OR claim_id=v_claim.claim_id
 FOR UPDATE;
 IF FOUND THEN
  IF v_existing.claim_id IS DISTINCT FROM v_claim.claim_id
    OR v_existing.run_id IS DISTINCT FROM v_claim.run_id
    OR v_existing.executor_mode IS DISTINCT FROM v_mode
    OR v_existing.request_key IS DISTINCT FROM p_request_key
    OR v_existing.wire_sha256 IS DISTINCT FROM p_expected_wire_sha256
    OR v_existing.archive_reported_sha256 IS DISTINCT FROM p_archive_reported_sha256
  THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT'; END IF;
  RETURN jsonb_build_object(
   'schema_version','SALY_NATIVE_DISPATCH_RESERVATION_V1',
   'status','ALREADY_RESERVED_NOT_DISPATCHED',
   'reservation_id',v_existing.id,'run_id',v_existing.run_id,
   'claim_id',v_existing.claim_id,'native_transmitted',false,
   'provider_attested',false,'host_delivery_verified',false,
   'db_done_allowed',false,'dispatch_authorized',false);
 END IF;
 INSERT INTO saly.creative_queue_native_dispatch_reservations_v1
 (claim_id,run_id,order_id,item_id,request_key,executor_mode,executor_provider,
  wire_sha256,prompt_sha256,input_snapshot_sha256,archive_reported_sha256,
  claim_lease_until,run_deadline_at,reserved_at)
 VALUES
 (v_claim.claim_id,v_claim.run_id,v_claim.order_id,v_claim.item_id,p_request_key,
  v_mode,v_provider,v_wire->>'wire_sha256',v_wire->>'prompt_sha256',
  v_wire->>'input_snapshot_sha256',p_archive_reported_sha256,
  v_claim.lease_until,v_claim.deadline_at,v_now)
 RETURNING id INTO v_rowid;
 RETURN jsonb_build_object(
  'schema_version','SALY_NATIVE_DISPATCH_RESERVATION_V1',
  'status','RESERVED_NOT_DISPATCHED','reservation_id',v_rowid,
  'run_id',v_claim.run_id,'claim_id',v_claim.claim_id,
  'wire_sha256',v_wire->>'wire_sha256',
  'native_transmitted',false,'provider_attested',false,
  'host_delivery_verified',false,'db_done_allowed',false,
  'dispatch_authorized',false);
END $function$
;
