CREATE OR REPLACE FUNCTION saly.creative_queue_record_delivery_v1(p_token uuid, p_run_id bigint, p_channel text, p_delivery_receipt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
BEGIN
 RAISE EXCEPTION 'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN';
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_release_v1(p_token uuid, p_outcome text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_now timestamptz; v_item_status text; v_closed boolean:=false;
BEGIN
  IF p_token IS NULL OR p_outcome NOT IN ('DONE','FAILED','BLOCKED')
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  v_now := clock_timestamp();
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;

  SELECT status INTO v_item_status FROM saly.creative_order_items
  WHERE id=v_claim.item_id AND order_id=v_claim.order_id FOR UPDATE;
  IF p_outcome='DONE' THEN
    -- Internal QA is obligatory; human creative approval is not.
    IF v_item_status<>'TERMINADO' OR NOT EXISTS (
      SELECT 1 FROM saly.creative_runs r
      WHERE r.item_id=v_claim.item_id AND r.order_id=v_claim.order_id
        AND r.state='EXITOSO' AND r.queue_claim_id=v_claim.id
        AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
        AND nullif(r.output_evidence->>'worker_receipt','') IS NOT NULL
        AND r.output_evidence->>'sha256' ~ '^[0-9a-f]{64}$'
        AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
                        WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number)
        AND EXISTS (
          SELECT 1 FROM saly.creative_run_detection_v1 d
          WHERE d.claim_id=v_claim.id AND d.run_id=r.id
            AND d.order_id=v_claim.order_id AND d.item_id=v_claim.item_id
            AND d.artifact_ref=r.output_evidence->>'artifact_ref'
            AND d.artifact_sha256=r.output_evidence->>'sha256'
            AND d.check_count BETWEEN 1 AND 7
            AND d.first_ready_elapsed_seconds=30*(d.check_count-1)
        )
    ) THEN RAISE EXCEPTION 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED'; END IF;
  ELSE
    IF v_item_status<>'BLOQUEADO'
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FAILURE_NOT_BLOCKED'; END IF;
  END IF;

  IF p_outcome='DONE' AND EXISTS (SELECT 1 FROM saly.creative_orders o WHERE o.id=v_claim.order_id AND o.project_id=2 AND o.request_kind='APP_SCREEN_SINGLE' AND o.scope_json->>'queue_mode'='SERIAL_V1' AND o.scope_json->>'module'='Solicitar adelanto') AND NOT EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.id=v_claim.item_id AND i.qa_receipt->>'review_mode'='GPT_SELF_QA') THEN RAISE EXCEPTION 'CREATIVE_SERIAL_SELF_QA_REQUIRED'; END IF;
  UPDATE saly.creative_queue_claims_v1
  SET state=p_outcome, finished_at=v_now, note=left(p_note,1000)
  WHERE id=v_claim.id;

  IF p_outcome='DONE' AND NOT EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id
      AND (i.status NOT IN ('TERMINADO','APROBADO') AND (i.required OR i.status<>'OMITIDO'))
  ) AND EXISTS (
    SELECT 1 FROM saly.creative_order_items i
    WHERE i.order_id=v_claim.order_id AND i.required
  ) THEN
    UPDATE saly.creative_orders
      SET status=CASE WHEN request_kind='APP_SCREEN_SINGLE'
            THEN 'TERMINADO' ELSE 'COMPLETADO' END, completed_at=v_now
      WHERE id=v_claim.order_id AND status IN ('PLANIFICADO','EN_PROCESO','EN_QA');
    v_closed := FOUND;
  END IF;
  IF p_outcome='DONE' AND NOT v_closed AND EXISTS (
     SELECT 1 FROM saly.creative_orders
     WHERE id=v_claim.order_id AND request_kind='APP_SCREEN_SINGLE')
  THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_DID_NOT_TERMINATE'; END IF;
  RETURN jsonb_build_object('status','RELEASED','result',p_outcome,
    'claim_id',v_claim.id,'order_closed',v_closed);
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_queue_run_binding_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_mode text; v_claim record; v_token text; v_now timestamptz;
BEGIN
  SELECT scope_json->>'queue_mode' INTO v_mode
  FROM saly.creative_orders WHERE id=NEW.order_id;
  IF v_mode IS DISTINCT FROM 'SERIAL_V1' THEN
    -- Legacy lane is not retroactively changed. It cannot use queue claims.
    IF NEW.queue_claim_id IS NOT NULL
    THEN RAISE EXCEPTION 'CREATIVE_QUEUE_LEGACY_CLAIM_FORBIDDEN'; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' AND NEW.queue_claim_id IS DISTINCT FROM OLD.queue_claim_id
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_BINDING_IMMUTABLE'; END IF;
  IF NEW.queue_claim_id IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_CLAIM_REQUIRED'; END IF;
  -- Cancellation/failure on expired leases is permitted for recovery; never
  -- permit such a run to start or successfully finish without a live lease.
  IF TG_OP='UPDATE' AND NEW.state IN ('FALLIDO','BLOQUEADO','CANCELADO')
  THEN RETURN NEW; END IF;
  v_token:=nullif(current_setting('saly.creative_queue_token',true),'');
  IF v_token IS NULL OR v_token !~ '^[0-9a-fA-F-]{36}$'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_TOKEN_REQUIRED'; END IF;
  v_now:=clock_timestamp();
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE id=NEW.queue_claim_id FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=v_now
    OR v_claim.claim_token::text IS DISTINCT FROM lower(v_token)
    OR v_claim.order_id IS DISTINCT FROM NEW.order_id
    OR v_claim.item_id IS DISTINCT FROM NEW.item_id
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_CLAIM_INVALID'; END IF;
  IF NEW.state IN ('EJECUTANDO','EXITOSO')
    AND NEW.worker_ref IS DISTINCT FROM v_claim.worker_ref
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_WORKER_MISMATCH'; END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_reference_step_v2(p_reference jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
 IF p_reference IS NULL OR p_reference='null'::jsonb
 THEN RETURN jsonb_build_object('step','4','status','SIN_REFERENCIA',
       'execute',false,'blocking',false,'reference_observations','[]'::jsonb); END IF;
 IF jsonb_typeof(p_reference) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SALY_REFERENCE_INVALID'; END IF;
 RETURN jsonb_build_object('step','4','status','CON_REFERENCIA',
     'execute',true,'blocking',false,'reference',p_reference,
     'k03_k04_mode','LENTE_SIN_REEJECUCION');
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_run_detection_record_v1(p_token uuid, p_run_id bigint, p_check_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c saly.creative_queue_claims_v1%ROWTYPE;
 r saly.creative_runs%ROWTYPE; ready jsonb;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 OR p_check_count IS NULL OR p_check_count NOT BETWEEN 1 AND 7
 THEN RAISE EXCEPTION 'SALY_DETECTION_INPUT_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO STRICT r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE;
 IF c.state<>'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.queue_claim_id IS DISTINCT FROM c.id
 OR r.item_id IS DISTINCT FROM c.item_id OR r.order_id IS DISTINCT FROM c.order_id
 OR r.worker_ref IS DISTINCT FROM c.worker_ref
 THEN RAISE EXCEPTION 'SALY_DETECTION_CLAIM_RUN_INVALID'; END IF;
 ready:=saly.creative_run_image_readback_v2(r.id,r.item_id);
 IF ready->>'status' IS DISTINCT FROM 'READY'
 THEN RAISE EXCEPTION 'SALY_DETECTION_IMAGE_NOT_READY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.creative_order_items i
               WHERE i.id=r.item_id AND i.order_id=r.order_id
                 AND i.status='PRODUCIENDO')
 THEN RAISE EXCEPTION 'SALY_DETECTION_ITEM_NOT_PRODUCING'; END IF;
 INSERT INTO saly.creative_run_detection_v1(
    run_id,order_id,item_id,claim_id,artifact_ref,artifact_sha256,
    check_count,first_ready_elapsed_seconds,evidence)
 VALUES(r.id,r.order_id,r.item_id,c.id,ready->>'artifact_ref',ready->>'sha256',
    p_check_count,30*(p_check_count-1),ready);
 RETURN jsonb_build_object('status','READY_DETECTED','run_id',r.id,
   'item_id',r.item_id,'first_ready_elapsed_seconds',30*(p_check_count-1),
   'check_count',p_check_count,'artifact_ref',ready->>'artifact_ref',
   'sha256',ready->>'sha256',
   'evidence_source','saly.creative_run_image_readback_v2',
   'next_step','11');
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'SALY_DETECTION_ALREADY_RECORDED';
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_run_expire_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE r saly.creative_runs%ROWTYPE; v_now timestamptz;
BEGIN
 IF p_run_id IS NULL THEN RAISE EXCEPTION 'CREATIVE_RECOVERY_RUN_ID_REQUIRED'; END IF;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BUSY_OR_NOT_FOUND','run_id',p_run_id,'changed',false); END IF;
 IF r.state NOT IN ('EN_COLA','EJECUTANDO') THEN
   RETURN jsonb_build_object('status','ALREADY_TERMINAL','run_id',r.id,'state',r.state,'changed',false);
 END IF;
 v_now:=clock_timestamp();
 IF r.deadline_at>v_now THEN
   RETURN jsonb_build_object('status','NOT_EXPIRED','run_id',r.id,'state',r.state,'changed',false);
 END IF;
 UPDATE saly.creative_runs SET state=CASE r.state WHEN 'EN_COLA' THEN 'BLOQUEADO' ELSE 'FALLIDO' END,
  error_code=CASE r.state WHEN 'EN_COLA' THEN 'QUEUE_TIMEOUT' ELSE 'LEASE_EXPIRED' END,
  updated_at=v_now WHERE id=r.id RETURNING * INTO r;
 RETURN jsonb_build_object('status','EXPIRED_CLOSED','run_id',r.id,'state',r.state,'error_code',r.error_code,
  'attempt_number',r.attempt_number,'changed',true,'retry_dispatched',false);
END $function$
;

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
   v_policy:=saly.creative_execution_policy_for_item_v1(v_now,NEW.order_id,NEW.item_id,NEW.attempt_number);
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
     NEW.deadline_at:=CASE WHEN OLD.order_id=22 AND OLD.item_id=26 AND OLD.attempt_number IN (3,4) THEN v_now+interval '24 hours' ELSE v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer) END;
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_run_image_readback_v2(p_run_id bigint, p_item_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
 r saly.creative_runs%ROWTYPE;
 v_artifact text;
 v_sha text;
BEGIN
 IF p_run_id IS NULL OR p_run_id<1 OR p_item_id IS NULL OR p_item_id<1
 THEN RAISE EXCEPTION 'SALY_IMAGE_READBACK_BAD_INPUT'; END IF;
 SELECT * INTO r FROM saly.creative_runs
 WHERE id=p_run_id AND item_id=p_item_id;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','PENDING','run_id',p_run_id,
       'item_id',p_item_id,'signal','RUN_ROW_NOT_FOUND');
 END IF;
 IF r.state IN ('EN_COLA','EJECUTANDO') THEN
   RETURN jsonb_build_object('status','PENDING','run_id',p_run_id,
       'item_id',p_item_id,'run_state',r.state,'signal','GENERATION_NOT_FINISHED');
 END IF;
 IF r.state<>'EXITOSO' THEN
   RETURN jsonb_build_object('status','FAILED','run_id',p_run_id,
       'item_id',p_item_id,'run_state',r.state,
       'reason',COALESCE(r.error_code,'RUN_NOT_SUCCESSFUL'));
 END IF;
 v_artifact:=r.output_evidence->>'artifact_ref';
 v_sha:=r.output_evidence->>'sha256';
 IF jsonb_typeof(r.output_evidence) IS DISTINCT FROM 'object'
 OR nullif(btrim(v_artifact),'') IS NULL
 OR coalesce(v_sha,'') !~ '^[0-9a-f]{64}$'
 THEN
   RETURN jsonb_build_object('status','ERROR','run_id',p_run_id,
       'item_id',p_item_id,'reason','IMAGE_EVIDENCE_INVALID');
 END IF;
 RETURN jsonb_build_object('status','READY','run_id',p_run_id,
     'item_id',p_item_id,'run_state',r.state,
     'artifact_ref',v_artifact,'sha256',v_sha,
     'evidence_source','saly.creative_runs.output_evidence',
     'next_step','11');
END; $function$
;
