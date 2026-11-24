-- SALY ABC candidate: owner-requested A/B/C; PR draft only, do not deploy.
-- Changes existing function definitions without modifying existing item/order rows.
BEGIN;

-- Explicit owner authentication for legacy orders whose requested_by='CHAT_USER'
-- has no UUID. No accounts are auto-authorized; provision mapping separately.
CREATE TABLE saly.creative_owner_accounts_v1(
  requested_by text NOT NULL,
  owner_uid uuid NOT NULL,
  PRIMARY KEY(requested_by,owner_uid)
);
CREATE TABLE saly.creative_owner_decisions_v1(
  item_id bigint PRIMARY KEY REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
  owner_uid uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('APROBADO','RECHAZADO')),
  comment text NOT NULL CHECK(length(btrim(comment))>0),
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON saly.creative_owner_accounts_v1,saly.creative_owner_decisions_v1
 FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON saly.creative_owner_accounts_v1 TO service_role;
-- The owner RPC has definer privileges; no direct update to either table.

-- Detection is the timer's own persisted readback: no fictitious external verifier.
CREATE TABLE saly.creative_run_detection_v1(
 run_id bigint PRIMARY KEY REFERENCES saly.creative_runs(id) ON DELETE RESTRICT,
 order_id bigint NOT NULL,
 item_id bigint NOT NULL,
 claim_id bigint NOT NULL REFERENCES saly.creative_queue_claims_v1(id) ON DELETE RESTRICT,
 artifact_ref text NOT NULL CHECK(length(btrim(artifact_ref))>0),
 artifact_sha256 text NOT NULL CHECK(artifact_sha256~'^[0-9a-f]{64}p_token uuid, p_run_id bigint, p_artifact_ref text, p_artifact_sha256 text, p_worker_receipt text, p_qa_receipt jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c record; r record; i record; v_verdict text; v_reviewer text;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 OR nullif(btrim(coalesce(p_artifact_ref,'')),'') IS NULL
 OR p_artifact_sha256 IS NULL OR p_artifact_sha256 !~ '^[0-9a-f]{64}$'
 OR nullif(btrim(coalesce(p_worker_receipt,'')),'') IS NULL
 OR jsonb_typeof(p_qa_receipt) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_INPUT_INVALID'; END IF;
 v_verdict:=p_qa_receipt->>'verdict';
 v_reviewer:=p_qa_receipt->>'reviewer_ref';
 IF v_verdict NOT IN ('PASS','FAIL') OR v_verdict IS NULL
 OR nullif(btrim(coalesce(p_qa_receipt->>'comment','')),'') IS NULL
 OR length(p_qa_receipt->>'comment')>4000
 OR nullif(btrim(coalesce(v_reviewer,'')),'') IS NULL
 OR p_qa_receipt->>'artifact_sha256' IS DISTINCT FROM p_artifact_sha256
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_COMMENT_OR_HASH_INVALID'; END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs
 WHERE id=p_run_id FOR UPDATE;
 SELECT * INTO i FROM saly.creative_order_items
 WHERE id=c.item_id AND order_id=c.order_id FOR UPDATE;
 IF c.id IS NULL OR r.id IS NULL OR i.id IS NULL
 OR c.state<>'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.queue_claim_id IS DISTINCT FROM c.id OR r.order_id IS DISTINCT FROM c.order_id
 OR r.item_id IS DISTINCT FROM c.item_id
 OR r.state<>'EJECUTANDO' OR i.status<>'PRODUCIENDO'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_RUN_NOT_EXECUTING'; END IF;
 IF lower(btrim(v_reviewer))=lower(btrim(c.worker_ref))
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_REVIEWER_NOT_INDEPENDENT'; END IF;

 IF v_verdict='FAIL' THEN
   PERFORM saly.creative_queue_advance_run_v1(p_token,p_run_id,'BLOQUEADO','{}'::jsonb,'QA_FAIL');
   UPDATE saly.creative_order_items
   SET status='BLOQUEADO',qa_receipt=p_qa_receipt||jsonb_build_object('run_id',p_run_id)
   WHERE id=i.id AND status='PRODUCIENDO';
   PERFORM saly.creative_queue_release_v1(p_token,'BLOCKED','QA_FAIL');
   RETURN jsonb_build_object('status','QA_COMMENT_SAVED_BLOCKED',
      'run_id',p_run_id,'item_id',i.id,'qa_verdict','FAIL',
      'comment_saved',true,'db_done_allowed',false);
 END IF;

 PERFORM saly.creative_queue_advance_run_v1(
   p_token,p_run_id,'EXITOSO',
   jsonb_build_object('artifact_ref',p_artifact_ref,'sha256',p_artifact_sha256,
                      'worker_receipt',p_worker_receipt),NULL);
 UPDATE saly.creative_order_items SET status='EN_QA' WHERE id=i.id
    AND status='PRODUCIENDO';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_STAGE_NOT_READY'; END IF;
 -- Existing trigger validates independent technical QA, RUN, artifact
 -- and all sealed semantic/technical QA expectations in the real product.
 UPDATE saly.creative_order_items SET status='TERMINADO',
    approved_at=NULL,approved_by=NULL,
    qa_receipt=p_qa_receipt||jsonb_build_object('run_id',p_run_id)
 WHERE id=i.id AND status='EN_QA';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_TERMINAL_NOT_READY'; END IF;
 RETURN jsonb_build_object('status','QA_COMMENT_SAVED_AWAITING_VERIFIED_CHAT_DELIVERY',
   'run_id',p_run_id,'item_id',i.id,'qa_verdict','PASS',
   'item_state','TERMINADO','comment_saved',true,
   'native_delivery_verified',false,'db_done_allowed',false);
END $function$;
-- Legacy callable name, but the entire detected->review->TERMINADO->DONE
-- transition now lives inside this ONE database transaction/function call.
-- Image generation itself has already set RUN=EXITOSO, then timer recorded READY.
CREATE OR REPLACE FUNCTION saly.creative_chat_save_qa_v1(
 p_token uuid,p_run_id bigint,p_artifact_ref text,p_artifact_sha256 text,
 p_worker_receipt text,p_qa_receipt jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','pg_temp'
AS $function$
DECLARE c saly.creative_queue_claims_v1%ROWTYPE;
 r saly.creative_runs%ROWTYPE;
 i saly.creative_order_items%ROWTYPE;
 d saly.creative_run_detection_v1%ROWTYPE;
 v_verdict text;v_reviewer text;v_released jsonb;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 OR jsonb_typeof(p_qa_receipt) IS DISTINCT FROM 'object'
 OR p_artifact_sha256 IS NULL OR p_artifact_sha256 !~ '^[0-9a-f]{64}$'
 OR nullif(btrim(coalesce(p_artifact_ref,'')),'') IS NULL
 OR nullif(btrim(coalesce(p_worker_receipt,'')),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_INPUT_INVALID'; END IF;
 v_verdict:=p_qa_receipt->>'verdict';
 v_reviewer:=p_qa_receipt->>'reviewer_ref';
 IF v_verdict NOT IN('PASS','FAIL') OR v_verdict IS NULL
 OR nullif(btrim(coalesce(p_qa_receipt->>'comment','')),'') IS NULL
 OR length(p_qa_receipt->>'comment')>4000
 OR nullif(btrim(coalesce(v_reviewer,'')),'') IS NULL
 OR p_qa_receipt->>'artifact_sha256' IS DISTINCT FROM p_artifact_sha256
 OR p_qa_receipt->>'reviewer_kind' IS DISTINCT FROM 'AUTOMATED_MODEL'
 OR p_qa_receipt->>'generator_model_family' IS DISTINCT FROM 'GPT'
 OR p_qa_receipt->>'reviewer_model_family' IS DISTINCT FROM 'CLAUDE'
 THEN RAISE EXCEPTION 'SALY_AUTOMATED_QA_PROVENANCE_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE;
 IF c.id IS NULL OR r.id IS NULL THEN
 RAISE EXCEPTION 'SALY_CHAT_QA_RUN_NOT_FOUND'; END IF;
 SELECT * INTO i FROM saly.creative_order_items
 WHERE id=c.item_id AND order_id=c.order_id FOR UPDATE;
 IF i.id IS NULL OR c.state<>'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.queue_claim_id IS DISTINCT FROM c.id
 OR r.order_id IS DISTINCT FROM c.order_id
 OR r.item_id IS DISTINCT FROM c.item_id
 OR r.state<>'EXITOSO' OR i.status<>'PRODUCIENDO'
 OR r.output_evidence->>'artifact_ref' IS DISTINCT FROM p_artifact_ref
 OR r.output_evidence->>'sha256' IS DISTINCT FROM p_artifact_sha256
 OR r.output_evidence->>'worker_receipt' IS DISTINCT FROM p_worker_receipt
 THEN RAISE EXCEPTION 'SALY_CHAT_QA_NOT_GENERATED_OR_BINDING_INVALID'; END IF;
 IF lower(btrim(v_reviewer))=lower(btrim(c.worker_ref))
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_REVIEWER_NOT_INDEPENDENT'; END IF;
 SELECT * INTO d FROM saly.creative_run_detection_v1
 WHERE run_id=r.id AND item_id=i.id AND order_id=i.order_id
 AND claim_id=c.id AND artifact_ref=p_artifact_ref
 AND artifact_sha256=p_artifact_sha256;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_CHAT_QA_DETECTION_NOT_RECORDED'; END IF;
 IF v_verdict='FAIL' THEN
   UPDATE saly.creative_order_items
   SET status='BLOQUEADO',qa_receipt=p_qa_receipt
      ||jsonb_build_object('run_id',p_run_id,'detection_run_id',d.run_id)
   WHERE id=i.id AND status='PRODUCIENDO';
   PERFORM saly.creative_queue_release_v1(p_token,'BLOCKED','QA_FAIL_AFTER_GENERATION');
   RETURN jsonb_build_object('status','QA_FAIL_BLOCKED','item_state','BLOQUEADO',
       'run_state','EXITOSO','run_id',r.id,'item_id',i.id,
       'qa_reviewer_kind','AUTOMATED_MODEL','db_done_allowed',false);
 END IF;
 -- The independent technical+semantic QA (L3C) is not bypassed.
 IF i.acceptance_json ? 'semantic_qa' THEN
   IF r.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
      saly.creative_item_visual_contract_l3b(i.id)#>'{contract,qa_checks}'
   THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
   PERFORM saly.creative_assert_dual_qa_l3c(
      i.acceptance_json,p_qa_receipt,r.input_snapshot,r.output_evidence);
 END IF;
 UPDATE saly.creative_order_items SET status='EN_QA'
 WHERE id=i.id AND status='PRODUCIENDO';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_STAGE_NOT_READY'; END IF;
 UPDATE saly.creative_order_items SET status='TERMINADO',
  approved_at=NULL,approved_by=NULL,
  qa_receipt=p_qa_receipt||jsonb_build_object('run_id',p_run_id,
    'detection_run_id',d.run_id,
    'first_ready_elapsed_seconds',d.first_ready_elapsed_seconds,
    'check_count',d.check_count)
 WHERE id=i.id AND status='EN_QA';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_TERMINAL_NOT_READY'; END IF;
 -- No independently verified delivery row is referenced or fabricated here.
 v_released:=saly.creative_chat_finalize_after_verified_delivery_v1(p_token,p_run_id);
 RETURN jsonb_build_object('status','TERMINADO','run_id',r.id,'item_id',i.id,
    'order_closed',v_released->'order_closed','db_claim_state','DONE',
    'db_item_state','TERMINADO',
    'qa_reviewer_kind','AUTOMATED_MODEL',
    'first_ready_elapsed_seconds',d.first_ready_elapsed_seconds,
    'check_count',d.check_count,'single_transaction',true);
END; $function$;

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
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_chat_finalize_after_verified_delivery_v1(p_token uuid, p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c record; r record; i record; v_result jsonb;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_BAD_INPUT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE;
 SELECT * INTO i FROM saly.creative_order_items
 WHERE id=c.item_id AND order_id=c.order_id FOR UPDATE;
 IF c.id IS NULL OR r.id IS NULL OR i.id IS NULL
 OR c.state<>'ACTIVE' OR r.queue_claim_id IS DISTINCT FROM c.id
 OR r.state<>'EXITOSO' OR i.status<>'TERMINADO'
 OR i.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
 OR nullif(btrim(i.qa_receipt->>'comment'),'') IS NULL
 OR i.qa_receipt->>'artifact_sha256' IS DISTINCT FROM r.output_evidence->>'sha256'
 OR NOT EXISTS(SELECT 1 FROM saly.creative_run_detection_v1 d
       WHERE d.run_id=r.id AND d.order_id=c.order_id AND d.item_id=i.id
         AND d.claim_id=c.id AND d.artifact_sha256=r.output_evidence->>'sha256'
         AND d.artifact_ref=r.output_evidence->>'artifact_ref')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_QA_NOT_SAVED'; END IF;
 -- V06 verifies actual evidence. A textual "generated" or a worker receipt
 -- does not suffice. On absence the transaction fails and remains pending.
 v_result:=saly.creative_queue_release_v1(p_token,'DONE');
 IF v_result->>'status' IS DISTINCT FROM 'RELEASED'
 OR v_result->>'result' IS DISTINCT FROM 'DONE'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_FINISH_NOT_VERIFIED'; END IF;
 -- The user-approved single-screen contract requires a REAL order
 -- TERMINADO, never just a conversational alias for COMPLETADO.
 IF EXISTS (
  SELECT 1 FROM saly.creative_orders o WHERE o.id=c.order_id
    AND o.request_kind='APP_SCREEN_SINGLE'
    AND (o.status<>'TERMINADO' OR v_result->'order_closed'<>'true'::jsonb)
 ) THEN RAISE EXCEPTION 'CREATIVE_CHAT_SINGLE_ORDER_NOT_TERMINADO'; END IF;
  RETURN jsonb_build_object('status','TERMINADO','run_id',p_run_id,
    'item_id',i.id,'db_item_state','TERMINADO','db_claim_state','DONE',
    'qa_comment',i.qa_receipt->>'comment',
    'order_closed',v_result->'order_closed');
END $function$;

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
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_item_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_order_status text; v_run record; v_run_id text;
BEGIN
 SELECT status INTO v_order_status FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_CLOSED_ORDER_IMMUTABLE_ITEMS'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='APROBADO'
 THEN RAISE EXCEPTION 'CREATIVE_APPROVED_ITEM_IMMUTABLE'; END IF;
 -- Original input and interpretation cannot be silently replaced after capture.
 IF TG_OP='UPDATE' AND OLD.acceptance_json ? 'semantic_qa'
    AND NEW.acceptance_json->'semantic_qa' IS DISTINCT FROM OLD.acceptance_json->'semantic_qa'
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_CONTRACT_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF NEW.approved_at IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
      OR auth.uid() IS NULL
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_decisions_v1 d
          WHERE d.item_id=NEW.id AND d.owner_uid=auth.uid() AND d.decision='APROBADO')
      OR NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1 a
          JOIN saly.creative_orders o ON o.requested_by=a.requested_by
          WHERE o.id=NEW.order_id AND a.owner_uid=auth.uid())
   THEN RAISE EXCEPTION 'SALY_OWNER_APPROVAL_NOT_AUTHORIZED'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.status IN ('TERMINADO','APROBADO')
 AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF TG_OP='INSERT' OR OLD.status<>'EN_QA'
   THEN RAISE EXCEPTION 'CREATIVE_ITEM_NOT_IN_QA'; END IF;
   IF EXISTS (
      SELECT 1 FROM saly.creative_item_dependencies d
      JOIN saly.creative_order_items prereq ON prereq.id=d.depends_on_item_id
      WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id AND prereq.status NOT IN ('TERMINADO','APROBADO')
   ) THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_NOT_APPROVED'; END IF;
   v_run_id:=NEW.qa_receipt->>'run_id';
   IF v_run_id IS NULL OR v_run_id !~ '^[0-9]+$'
      OR (NEW.qa_receipt->>'verdict') IS DISTINCT FROM 'PASS'
      OR jsonb_typeof(NEW.qa_receipt->'reviewer_ref') IS DISTINCT FROM 'string'
      OR nullif(btrim(NEW.qa_receipt->>'reviewer_ref'),'') IS NULL
   THEN RAISE EXCEPTION 'CREATIVE_QA_RECEIPT_MISSING'; END IF;
   SELECT r.id,r.worker_ref,r.input_snapshot,r.output_evidence INTO v_run
   FROM saly.creative_runs r
   WHERE r.id=v_run_id::bigint AND r.item_id=NEW.id AND r.order_id=NEW.order_id
     AND r.state='EXITOSO' AND nullif(r.output_evidence->>'artifact_ref','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM saly.creative_runs newer
       WHERE newer.item_id=r.item_id AND newer.attempt_number>r.attempt_number);
   IF NEW.status='TERMINADO' AND NOT EXISTS (
     SELECT 1 FROM saly.creative_run_detection_v1 d
     WHERE d.run_id=v_run_id::bigint AND d.item_id=NEW.id AND d.order_id=NEW.order_id
       AND d.artifact_sha256=v_run.output_evidence->>'sha256'
   ) THEN RAISE EXCEPTION 'SALY_ITEM_TERMINADO_REQUIRES_TIMER_DETECTION'; END IF;
   IF NOT FOUND OR lower(btrim(NEW.qa_receipt->>'reviewer_ref'))=lower(btrim(v_run.worker_ref))
      OR (NEW.status='TERMINADO' AND (NEW.approved_by IS NOT NULL OR NEW.approved_at IS NOT NULL))
      OR (NEW.status='APROBADO' AND NEW.approved_by IS DISTINCT FROM NEW.qa_receipt->>'reviewer_ref')
   THEN RAISE EXCEPTION 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING'; END IF;
   IF NEW.acceptance_json ? 'semantic_qa' THEN
     IF v_run.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
        saly.creative_item_visual_contract_l3b(NEW.id)#>'{contract,qa_checks}'
     THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
     PERFORM saly.creative_assert_dual_qa_l3c(
        NEW.acceptance_json,NEW.qa_receipt,v_run.input_snapshot,v_run.output_evidence);
   END IF;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_item_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_j jsonb;
  v_a jsonb;
  v_order_status text;
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' OR EXISTS (
   SELECT 1 FROM saly.creative_orders o WHERE o.id=OLD.order_id AND o.status='TERMINADO'
  ) THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 SELECT status INTO v_order_status FROM saly.creative_orders
 WHERE id=NEW.order_id FOR UPDATE;
 -- Explicit signed owner approval may follow an already completed order.
 IF OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF auth.uid() IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
     OR NEW.approved_at IS NULL
     OR (to_jsonb(NEW) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
          IS DISTINCT FROM
        (to_jsonb(OLD) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_OWNER_TRANSITION_INVALID'; END IF;
   RETURN NEW;
 END IF;
 IF OLD.status='TERMINADO' OR v_order_status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status='EN_QA' THEN
   IF NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
      OR NEW.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
      OR NOT EXISTS(SELECT 1 FROM saly.creative_runs r
        JOIN saly.creative_run_detection_v1 d ON d.run_id=r.id
        WHERE r.item_id=NEW.id AND r.order_id=NEW.order_id AND r.state='EXITOSO'
        AND d.item_id=NEW.id AND d.order_id=NEW.order_id
        AND d.artifact_sha256=r.output_evidence->>'sha256'
        AND d.artifact_ref=r.output_evidence->>'artifact_ref'
        AND r.output_evidence->>'sha256'=NEW.qa_receipt->>'artifact_sha256')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_QA_RUN_MISSING'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status<>'PENDIENTE' OR NEW.order_id<>OLD.order_id
  OR NEW.code<>OLD.code OR NEW.acceptance_json IS DISTINCT FROM OLD.acceptance_json
  OR NEW.context_json IS DISTINCT FROM OLD.context_json
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.item_id=NEW.id)
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_NOT_ARCHIVED_PENDING'; END IF;
  v_a:=OLD.qa_receipt->'chat_artifact_reconciliation_v1';
  v_j:=NEW.qa_receipt->'chat_judge_v1';
  IF v_a IS NULL OR v_j IS NULL
  OR NEW.qa_receipt->'chat_artifact_reconciliation_v1' IS DISTINCT FROM v_a
  OR v_a->>'status' IS DISTINCT FROM 'ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE'
  OR v_a->>'avoid_regeneration' IS DISTINCT FROM 'true'
  OR v_a->>'chat_delivery_observed' IS DISTINCT FROM 'true'
  OR v_a->>'sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'artifact_sha256' IS DISTINCT FROM v_a->>'sha256'
  OR v_j->>'judge_receipt_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'source_manifest_input_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'judge_kind' IS DISTINCT FROM 'DETERMINISTIC_TECHNICAL_SEPARATE_PROCESS'
  OR v_j->>'technical_verdict' NOT IN ('PASS_TECHNICAL','PASS_TECHNICAL_WITH_OBSERVATIONS')
  OR v_j->>'technical_verdict' IS NULL
  OR v_j->>'semantic_independence_proven' IS DISTINCT FROM 'false'
  OR v_j->>'semantic_verdict' IS DISTINCT FROM 'NOT_INDEPENDENTLY_EVALUATED'
  OR v_j->>'production_approved' IS DISTINCT FROM 'false'
  OR v_j->>'run_verified' IS DISTINCT FROM 'false'
  OR v_j->>'terminal_semantics' IS DISTINCT FROM 'IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED'
  OR nullif(btrim(v_j->>'qa_comment'),'') IS NULL
  OR jsonb_typeof(v_j->'observations') IS DISTINCT FROM 'array'
  OR NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM saly.creative_item_dependencies d
    JOIN saly.creative_order_items p ON p.id=d.depends_on_item_id
    WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id
      AND p.status NOT IN ('TERMINADO','APROBADO')
  ) THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_JUDGE_OR_DEPENDENCY_MISSING';
  END IF;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_order_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 IF OLD.status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status NOT IN ('PLANIFICADO','EN_PROCESO')
  OR NEW.completed_at IS NULL
  OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                 WHERE i.order_id=NEW.id AND i.required)
  OR EXISTS (
   SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id AND
      (i.status NOT IN ('TERMINADO','APROBADO','OMITIDO')
       OR (i.required AND i.status NOT IN ('TERMINADO','APROBADO'))
       OR (i.status='TERMINADO' AND
         (
          -- The old historical chat-archive closure stays accepted exactly as before.
          (
            i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}' IS DISTINCT FROM
              i.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
            OR nullif(btrim(i.qa_receipt#>>'{chat_judge_v1,qa_comment}'),'') IS NULL
          )
          AND NOT EXISTS (
            -- Newly generated evidence: no creative human approval required.
            SELECT 1 FROM saly.creative_runs r
            WHERE r.item_id=i.id AND r.order_id=i.order_id AND r.state='EXITOSO'
              AND i.qa_receipt->>'verdict'='PASS'
              AND i.qa_receipt->>'artifact_sha256'=r.output_evidence->>'sha256'
              AND EXISTS (
                SELECT 1 FROM saly.creative_run_detection_v1 d
                WHERE d.run_id=r.id AND d.item_id=i.id AND d.order_id=i.order_id
                  AND d.artifact_sha256=r.output_evidence->>'sha256'
                  AND d.artifact_ref=r.output_evidence->>'artifact_ref'
                  AND d.check_count BETWEEN 1 AND 7
              )
          )
        )))
  )
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
              AND r.state IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_DETAILS_INCOMPLETE'; END IF;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_order_close_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
 IF NEW.status='COMPLETADO' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   IF EXISTS(SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
      AND r.state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_ACTIVE_RUNS'; END IF;
   IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                  WHERE i.order_id=NEW.id AND i.required)
      OR EXISTS (SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id
                 AND (i.status NOT IN ('TERMINADO','APROBADO','OMITIDO')
                  OR (i.required AND i.status NOT IN ('TERMINADO','APROBADO'))))
   THEN RAISE EXCEPTION 'CREATIVE_ORDER_CLOSURE_WITH_INCOMPLETE_DETAILS'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status='COMPLETADO'
 THEN RAISE EXCEPTION 'CREATIVE_COMPLETED_ORDER_IMMUTABLE'; END IF;
 RETURN NEW;
END $function$;


CREATE FUNCTION saly.creative_owner_approve_v1(
 p_item_id bigint,p_decision text,p_comment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','auth','pg_temp'
AS $f$
DECLARE uid uuid; row_i record; row_o record;
BEGIN
 uid:=auth.uid();
 IF uid IS NULL OR p_item_id IS NULL OR p_item_id<1
 OR p_decision NOT IN ('APROBADO','RECHAZADO')
 OR nullif(btrim(coalesce(p_comment,'')),'') IS NULL
 THEN RAISE EXCEPTION 'SALY_OWNER_DECISION_INPUT_INVALID'; END IF;
 SELECT * INTO row_i FROM saly.creative_order_items
 WHERE id=p_item_id FOR UPDATE;
 IF NOT FOUND OR row_i.status<>'TERMINADO'
 THEN RAISE EXCEPTION 'SALY_OWNER_REQUIRES_TERMINADO'; END IF;
 SELECT * INTO row_o FROM saly.creative_orders WHERE id=row_i.order_id;
 IF NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1 a
 WHERE a.requested_by=row_o.requested_by AND a.owner_uid=uid)
 THEN RAISE EXCEPTION 'SALY_OWNER_DECISION_UNAUTHORIZED'; END IF;
 INSERT INTO saly.creative_owner_decisions_v1(item_id,owner_uid,decision,comment)
 VALUES (p_item_id,uid,p_decision,p_comment);
 IF p_decision='APROBADO' THEN
   UPDATE saly.creative_order_items
   SET status='APROBADO', approved_at=clock_timestamp(),approved_by=uid::text,
       updated_at=clock_timestamp()
   WHERE id=p_item_id AND status='TERMINADO';
   IF NOT FOUND THEN RAISE EXCEPTION 'SALY_OWNER_APPROVAL_UPDATE_FAILED'; END IF;
 END IF;
 RETURN jsonb_build_object('item_id',p_item_id,'decision',p_decision,
    'item_state',(SELECT status FROM saly.creative_order_items WHERE id=p_item_id),
    'owner_uid',uid,'recorded',true);
END; $f$;
REVOKE ALL ON FUNCTION saly.creative_owner_approve_v1(bigint,text,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION saly.creative_owner_approve_v1(bigint,text,text)
 TO authenticated;


-- 55 actual SALY app-system versions, exactly once. Source-confirmed medium
-- is PROTOTIPO_APP only. Suggested media are never selected automatically.
CREATE TABLE saly.creative_token_medium_confirmations_v1(
 version_id bigint NOT NULL REFERENCES saly.identity_versions(id) ON DELETE RESTRICT,
 medium text NOT NULL CHECK(medium IN ('REDES_SOCIALES','IMPRESION','PAPEL')),
 confirmed_by uuid NOT NULL,
 confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 comment text NOT NULL CHECK(length(btrim(comment))>0),
 metadata_previous_sha256 text NOT NULL CHECK(metadata_previous_sha256~'^[0-9a-f]{64}$'),
 PRIMARY KEY(version_id,medium)
);
REVOKE ALL ON saly.creative_token_medium_confirmations_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- The roles list is explicit (no recursive/unknown automatic classification).
WITH roles(id,token_role,proposed) AS (
 VALUES
(7,'CTA','[]'::jsonb),
(8,'MARCA','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(10,'DUPLICADO_DE_CTA','[]'::jsonb),
(11,'TEXTO','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(12,'SUPERFICIE_BASE','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(13,'SUPERFICIE_UI','[]'::jsonb),
(14,'SUPERFICIE_UI','[]'::jsonb),
(15,'TEXTO','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(16,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(17,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(18,'SUPERFICIE_UI','[]'::jsonb),
(19,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(20,'SUPERFICIE_UI','[]'::jsonb),
(21,'CTA','[]'::jsonb),
(22,'CTA','[]'::jsonb),
(23,'TEXTO','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(24,'TEXTO','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(25,'SUPERFICIE_BASE','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(26,'SUPERFICIE_BASE','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(27,'SUPERFICIE_UI','[]'::jsonb),
(28,'SUPERFICIE_UI','[]'::jsonb),
(29,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(30,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(31,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(32,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(33,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(34,'TIPOGRAFIA_FAMILIA','["REDES_SOCIALES","IMPRESION","PAPEL"]'::jsonb),
(35,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(36,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(37,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(38,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(39,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(40,'TIPOGRAFIA_ESTILO_UI','[]'::jsonb),
(41,'CTA','[]'::jsonb),
(42,'GEOMETRIA_UI','[]'::jsonb),
(43,'GEOMETRIA_UI','[]'::jsonb),
(44,'GEOMETRIA_UI','[]'::jsonb),
(45,'GEOMETRIA_UI','[]'::jsonb),
(46,'GEOMETRIA_UI','[]'::jsonb),
(47,'GEOMETRIA_UI','[]'::jsonb),
(48,'GEOMETRIA_UI','[]'::jsonb),
(49,'GEOMETRIA_UI','[]'::jsonb),
(50,'GEOMETRIA_UI','[]'::jsonb),
(51,'CTA','[]'::jsonb),
(52,'GEOMETRIA_UI','[]'::jsonb),
(53,'ACCESIBILIDAD_UI','[]'::jsonb),
(54,'ACCESIBILIDAD_UI','[]'::jsonb),
(55,'ACCESIBILIDAD_UI','[]'::jsonb),
(57,'SUPERFICIE_UI','[]'::jsonb),
(58,'NAVEGACION_ESTADO_UI','[]'::jsonb),
(59,'NAVEGACION_ESTADO_UI','[]'::jsonb),
(60,'NAVEGACION_ESTADO_UI','[]'::jsonb),
(61,'ACENTO_MODULO','["REDES_SOCIALES"]'::jsonb),
(62,'NAVEGACION_ESTADO_UI','[]'::jsonb),
(63,'GEOMETRIA_UI','[]'::jsonb)
)
UPDATE saly.identity_versions v SET metadata=
 COALESCE(v.metadata,'{}'::jsonb)
 || jsonb_build_object(
  'token_role',r.token_role,
  'applies_to',jsonb_build_array('PROTOTIPO_APP'),
  'applies_to_proposed',r.proposed,
  'medium_provenance','SALY_DS_V1_APP_CONFIRMED_ONLY')
 FROM roles r WHERE v.id=r.id
   AND v.approval_status IN ('APPROVED','CANDIDATE');

-- Split approved roles permanently: brand #00C853 is brand-only,
-- action #008200 is CTA only. Preserve candidate raw source and approval_status.
UPDATE saly.identity_versions v SET metadata=v.metadata
 || jsonb_build_object(
   'duplicate_of_code','color.action.primary.bg',
   'duplicate_resolution','EXCLUDE_FROM_EFFECTIVE_PALETTE',
   'visual_usage','CTA_DUPLICATE_NOT_BRAND',
   'not_effective',true,
   'conflict_resolution_note','APPROVED_CTA_008200_KEPT;APPROVED_BRAND_00C853_KEPT')
 WHERE v.id=10;
UPDATE saly.identity_versions v SET metadata=v.metadata
 || jsonb_build_object(
   'kind','ALIAS',
   'alias_target_code','color.action.primary.bg',
   'resolved_role','CTA',
   'visual_usage','REFERENCE_APPROVED_CTA_NOT_SECOND_COLOR',
   'not_effective',true,
   'conflict_resolution_note','ORIGINAL_VALUE_JSON_PRESERVED;TARGET_APPROVED_CTA')
 WHERE v.id=21;

-- Authenticated owner signs precisely those proposed media already enumerated.
CREATE FUNCTION saly.creative_token_confirm_medium_v1(
 p_version_id bigint,p_medium text,p_comment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','auth','extensions','pg_temp'
AS $fn$
DECLARE uid uuid; v saly.identity_versions%ROWTYPE;
 v_role text; v_old_sha text; v_next jsonb;
BEGIN
 uid:=auth.uid();
 IF uid IS NULL OR p_version_id IS NULL OR p_version_id<1
 OR p_medium NOT IN ('REDES_SOCIALES','IMPRESION','PAPEL')
 OR nullif(btrim(coalesce(p_comment,'')),'') IS NULL
 THEN RAISE EXCEPTION 'SALY_TOKEN_CONFIRM_INPUT_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM saly.creative_owner_accounts_v1
  WHERE requested_by='CHAT_USER' AND owner_uid=uid)
 THEN RAISE EXCEPTION 'SALY_TOKEN_CONFIRM_OWNER_REQUIRED'; END IF;
 SELECT * INTO STRICT v FROM saly.identity_versions WHERE id=p_version_id FOR UPDATE;
 v_role:=v.metadata->>'token_role';
 IF v_role IN ('CTA','DUPLICADO_DE_CTA','GEOMETRIA_UI','NAVEGACION_ESTADO_UI')
 THEN RAISE EXCEPTION 'SALY_TOKEN_ROLE_APP_ONLY'; END IF;
 IF jsonb_typeof(v.metadata->'applies_to_proposed') IS DISTINCT FROM 'array'
 OR NOT (v.metadata->'applies_to_proposed' ? p_medium)
 THEN RAISE EXCEPTION 'SALY_TOKEN_MEDIUM_NOT_PROPOSED'; END IF;
 IF v.metadata->'applies_to' ? p_medium
 THEN RAISE EXCEPTION 'SALY_TOKEN_MEDIUM_ALREADY_CONFIRMED'; END IF;
 v_old_sha:=encode(extensions.digest(v.metadata::text,'sha256'),'hex');
 v_next:=jsonb_set(v.metadata,'{applies_to}',
    (v.metadata->'applies_to')||jsonb_build_array(p_medium),true);
 INSERT INTO saly.creative_token_medium_confirmations_v1(
 version_id,medium,confirmed_by,comment,metadata_previous_sha256)
 VALUES(p_version_id,p_medium,uid,p_comment,v_old_sha);
 UPDATE saly.identity_versions SET metadata=v_next WHERE id=p_version_id;
 RETURN jsonb_build_object('version_id',p_version_id,
  'medium',p_medium,'confirmed_by',uid,'confirmed_at',
  (SELECT confirmed_at FROM saly.creative_token_medium_confirmations_v1
  WHERE version_id=p_version_id AND medium=p_medium),
  'metadata_previous_sha256',v_old_sha,
  'approval_status',v.approval_status,
  'role',v_role,'status','CONFIRMADO');
END; $fn$;
REVOKE ALL ON FUNCTION saly.creative_token_confirm_medium_v1(bigint,text,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION saly.creative_token_confirm_medium_v1(bigint,text,text)
 TO authenticated;

CREATE FUNCTION saly.creative_item_context_medium_v3(
 p_item_id bigint,p_medium_override text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','pg_temp'
AS $f$
DECLARE
 i record; o record; media text;
 selections jsonb; omissions jsonb;
BEGIN
 SELECT id,order_id,context_json INTO i
 FROM saly.creative_order_items WHERE id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_MEDIUM_ITEM_NOT_FOUND'; END IF;
 SELECT id,scope_json,context_set_id INTO o FROM saly.creative_orders WHERE id=i.order_id;
 media:=COALESCE(NULLIF(p_medium_override,''),
    nullif(i.context_json->>'output_medium',''),
    nullif(o.scope_json->>'output_medium',''),
    CASE WHEN nullif(i.context_json#>>'{screen_spec,device}','') IS NOT NULL
         THEN 'PROTOTIPO_APP' ELSE NULL END);
 IF media IS NOT NULL AND media NOT IN ('PROTOTIPO_APP','IMPRESION','PAPEL','REDES_SOCIALES')
 THEN RAISE EXCEPTION 'SALY_MEDIUM_UNKNOWN'; END IF;
 IF o.context_set_id IS NULL THEN RAISE EXCEPTION 'SALY_MEDIUM_CONTEXT_MISSING'; END IF;
 WITH token_rows AS (
  SELECT e.code,v.id AS version_id,v.approval_status,t.role,v.value_json,
   v.metadata->'applies_to' applies_to,
   v.metadata->'applies_to_proposed' applies_to_proposed,
   v.metadata->>'token_role' token_role,
   v.metadata->>'duplicate_of_code' duplicate_of_code,
   v.metadata->>'alias_target_code' alias_target_code,
   v.metadata->>'kind' token_kind
  FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=o.context_set_id
    AND v.approval_status IN ('APPROVED','CANDIDATE')
 ), decision AS (
  SELECT *,
    CASE
      WHEN jsonb_typeof(applies_to) IS DISTINCT FROM 'array'
       OR jsonb_array_length(applies_to)=0 THEN 'SIN_CLASIFICAR'
      WHEN media IS NULL THEN 'MEDIO_SIN_DEFINIR'
      WHEN NOT (applies_to ? media) THEN 'MEDIO_NO_APLICA'
      ELSE NULL END AS reason
  FROM token_rows
 )
 SELECT
  COALESCE(jsonb_agg(jsonb_build_object(
   'code',code,'version_id',version_id,'approval_status',approval_status,
   'role',role,'value_json',value_json,
   'token_role',token_role,'applies_to_proposed',applies_to_proposed,
   'effective_for_palette',token_role IS DISTINCT FROM 'DUPLICADO_DE_CTA',
   'alias_target_code',alias_target_code,'duplicate_of_code',duplicate_of_code) ORDER BY code)
   FILTER(WHERE reason IS NULL),'[]'::jsonb),
  COALESCE(jsonb_agg(jsonb_build_object(
   'code',code,'version_id',version_id,'reason',reason) ORDER BY code)
   FILTER(WHERE reason IS NOT NULL),'[]'::jsonb)
 INTO selections,omissions FROM decision;
 RETURN jsonb_build_object(
 'schema_version','SALY_MEDIUM_TOKEN_SELECTION_V3',
 'item_id',p_item_id,'order_id',i.order_id,'output_medium',media,
 'selected',selections,'omitted',omissions,
 'selected_count',jsonb_array_length(selections),
 'omitted_count',jsonb_array_length(omissions),
 'candidates_promoted',false,
 'effective_color_roles',jsonb_build_object(
   'CTA',jsonb_build_object('code','color.action.primary.bg',
         'hex','#008200','version_id',7),
   'MARCA',jsonb_build_object('code','color.brand.primary',
         'hex','#00C853','version_id',8)),
 'effective_palette_exclusions',
   COALESCE((SELECT jsonb_agg(jsonb_build_object(
       'code',e->>'code','reason','DUPLICADO_DE_CTA',
       'duplicate_of_code',e->>'duplicate_of_code'))
      FROM jsonb_array_elements(selections) e
      WHERE e->>'token_role'='DUPLICADO_DE_CTA'),'[]'::jsonb)
 );
END; $f$;
REVOKE ALL ON FUNCTION saly.creative_item_context_medium_v3(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION saly.creative_item_context_medium_v3(bigint,text) TO service_role;

COMMIT;
