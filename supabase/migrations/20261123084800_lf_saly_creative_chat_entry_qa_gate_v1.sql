-- SALY Creative: PRIVATE pending->RUN and QA->verified-delivery terminal gate.
-- Governed deploy only. Actual Native host, image generation and callbacks
-- remain unavailable; absolutely no GRANT or existing-order state change.
-- Source candidates: queue_v12 001/002 in main, tested 2026-11-22.
BEGIN;
DO $prelive$
BEGIN
 IF to_regprocedure('saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)') IS NOT NULL
 OR to_regprocedure('saly.creative_chat_save_qa_v1(uuid,bigint,text,text,text,jsonb)') IS NOT NULL
 OR to_regprocedure('saly.creative_queue_release_v1(uuid,text,text)') IS NULL
 OR to_regprocedure('saly.creative_native_render_wire_v1(uuid,bigint,text)') IS NULL
 OR to_regprocedure('saly.creative_order_sequence_dependency_met_v1(bigint)') IS NULL
 OR to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_PRECONDITION_FAILED'; END IF;
 IF EXISTS (
   SELECT 1 FROM saly.creative_orders o
   JOIN saly.creative_order_items i ON i.order_id=o.id
   WHERE o.code IN ('SALY_HOME_V015_SINGLE_20261123',
                    'SALY_ADELANTO_V015_SINGLE_20261123')
   AND (o.status<>'PLANIFICADO' OR i.status<>'PENDIENTE'
        OR o.request_kind<>'APP_SCREEN_SINGLE'
        OR o.scope_json->>'review_only'<>'true'
        OR o.scope_json->>'render_authorized'<>'false')
 ) THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_ORDER_PRESTATE_DRIFT'; END IF;
 IF (SELECT COUNT(*) FROM saly.creative_runs)<>0
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_EXISTING_RUNS_BLOCK'; END IF;
END $prelive$;

DO $pre$
BEGIN
 IF to_regprocedure('saly.creative_queue_claim_next_v1(text,integer)') IS NULL
 OR to_regprocedure('saly.creative_queue_admit_run_v1(uuid,integer,text,jsonb)') IS NULL
 OR to_regprocedure('saly.creative_queue_advance_run_v1(uuid,bigint,text,jsonb,text)') IS NULL
 OR to_regclass('saly.creative_queue_claims_v1') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_V02_REQUIRED'; END IF;
END $pre$;

CREATE FUNCTION saly.creative_chat_begin_pending_v1(
 p_order_code text, p_allowed_item_codes text[], p_worker_ref text,
 p_idempotency_key text, p_input_snapshot jsonb
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog,saly,pg_temp
AS $f$
DECLARE
 v_order record;
 v_item record;
 v_claim jsonb;
 v_run jsonb;
 v_attempt integer;
 v_now timestamptz;
BEGIN
 IF p_order_code IS NULL OR p_order_code !~ '^[A-Z][A-Z0-9_-]{2,63}$'
 OR p_allowed_item_codes IS NULL OR cardinality(p_allowed_item_codes) NOT BETWEEN 1 AND 50
 OR EXISTS (SELECT 1 FROM unnest(p_allowed_item_codes) c
            WHERE c IS NULL OR c !~ '^[A-Z][A-Z0-9_-]{1,63}$')
 OR (SELECT count(DISTINCT c) FROM unnest(p_allowed_item_codes) c)
    IS DISTINCT FROM cardinality(p_allowed_item_codes)
 OR p_worker_ref IS NULL OR length(btrim(p_worker_ref)) NOT BETWEEN 1 AND 128
 OR p_idempotency_key IS NULL OR length(btrim(p_idempotency_key)) NOT BETWEEN 1 AND 128
 OR jsonb_typeof(p_input_snapshot) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_BAD_INPUT'; END IF;

 -- Same global lock as V02. SQL attempts, claims and policy must be checked
 -- by the V02 RPCs, not duplicated here in a second writer.
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT id,code,status,scope_json,request_kind INTO v_order FROM saly.creative_orders
 WHERE code=p_order_code FOR UPDATE;
 IF NOT FOUND OR v_order.status NOT IN ('PLANIFICADO','EN_PROCESO')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_NOT_ACTIVE'; END IF;
 IF v_order.request_kind='APP_SCREEN_SINGLE' THEN
   IF cardinality(p_allowed_item_codes)<>1
   THEN RAISE EXCEPTION 'CREATIVE_CHAT_SINGLE_ORDER_EXACTLY_ONE_SCREEN'; END IF;
   IF NOT saly.creative_order_sequence_dependency_met_v1(v_order.id)
   THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_PREDECESSOR_NOT_TERMINADO'; END IF;
 END IF;

  IF v_order.scope_json->>'queue_mode' IS DISTINCT FROM 'SERIAL_V1'
 OR v_order.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 OR coalesce(v_order.scope_json->>'review_only','false') IS DISTINCT FROM 'false'
 OR coalesce(v_order.scope_json->>'render_authorized','true') IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_RENDER_NOT_AUTHORIZED'; END IF;

 SELECT i.id,i.code,i.order_id INTO v_item
 FROM saly.creative_order_items i
 WHERE i.order_id=v_order.id AND i.code=ANY(p_allowed_item_codes)
 AND i.status='PENDIENTE'
 AND (v_order.request_kind<>'APP_SCREEN_SINGLE'
      OR (i.kind='SCREEN' AND i.ordinal=1))
 AND NOT EXISTS (
   SELECT 1 FROM saly.creative_item_dependencies d
   JOIN saly.creative_order_items prior ON prior.id=d.depends_on_item_id
   WHERE d.order_id=i.order_id AND d.item_id=i.id
     AND prior.status<>'APROBADO'
 )
 AND NOT EXISTS (
   SELECT 1 FROM saly.creative_runs r
   WHERE r.item_id=i.id AND r.state IN ('EN_COLA','EJECUTANDO','EXITOSO')
 )
 ORDER BY i.ordinal,i.id LIMIT 1 FOR UPDATE OF i;
 IF NOT FOUND
 THEN RETURN jsonb_build_object('status','NO_PENDING_IN_SCOPE',
  'order_code',v_order.code,'selected_count',0); END IF;

 -- No other eligible LISTO item is allowed to hijack the global v02 claim.
 -- Explicitly reject and roll back instead of claiming an unrelated order.
 IF EXISTS (
  SELECT 1 FROM saly.creative_orders o
  JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE i.status='LISTO'
   AND o.status IN ('PLANIFICADO','EN_PROCESO')
   AND o.scope_json->>'queue_mode'='SERIAL_V1'
   AND o.scope_json->>'rendering_authority'='true'
   AND coalesce(o.scope_json->>'review_only','false')='false'
   AND coalesce(o.scope_json->>'render_authorized','true')='true'
 ) THEN RAISE EXCEPTION 'CREATIVE_CHAT_OTHER_READY_ITEM_MUST_BE_RECONCILED'; END IF;

 UPDATE saly.creative_order_items SET status='LISTO' WHERE id=v_item.id
 AND status='PENDIENTE';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_PENDING_LOST'; END IF;

 -- Reuse V02's lease, max queue, exclusion and fencing gate.
 v_claim:=saly.creative_queue_claim_next_v1(p_worker_ref,NULL);
 IF v_claim->>'status' IS DISTINCT FROM 'CLAIMED'
 OR (v_claim->>'order_id')::bigint IS DISTINCT FROM v_order.id
 OR (v_claim->>'item_id')::bigint IS DISTINCT FROM v_item.id
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_CLAIM_SCOPE_OR_POLICY_BLOCKED'; END IF;

 SELECT coalesce(max(attempt_number),0)+1 INTO v_attempt
 FROM saly.creative_runs WHERE item_id=v_item.id;
 v_run:=saly.creative_queue_admit_run_v1(
  (v_claim->>'claim_token')::uuid,v_attempt,p_idempotency_key,p_input_snapshot);
 IF (v_run->>'run_id') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_RUN_NOT_ADMITTED'; END IF;
 PERFORM saly.creative_queue_advance_run_v1(
  (v_claim->>'claim_token')::uuid,(v_run->>'run_id')::bigint,'EJECUTANDO',
  '{}'::jsonb,NULL);
 UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=v_item.id
  AND status='LISTO';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_NOT_PROCESSING'; END IF;
 UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_order.id
 AND status IN ('PLANIFICADO','EN_PROCESO');
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_NOT_PROCESSING'; END IF;

 RETURN jsonb_build_object(
  'schema_version','SALY_CREATIVE_CHAT_BEGIN_V1',
  'status','PROCESSING_STARTED','order_id',v_order.id,'order_code',v_order.code,
  'item_id',v_item.id,'item_code',v_item.code,
  'run_id',(v_run->>'run_id')::bigint,
  'item_state','PRODUCIENDO','order_state','EN_PROCESO',
  'native_transmitted',false,'qa_completed',false,
  'db_done_allowed',false);
END $f$;

REVOKE ALL ON FUNCTION saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)
 FROM PUBLIC;
DO $acl$
DECLARE p text;
BEGIN
 FOREACH p IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user'] LOOP
  IF to_regrole(p) IS NOT NULL THEN
   EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb) FROM %I',p);
  END IF;
 END LOOP;
END $acl$;
DO $pre$
BEGIN
 IF to_regprocedure('saly.creative_queue_advance_run_v1(uuid,bigint,text,jsonb,text)') IS NULL
 OR to_regprocedure('saly.creative_queue_release_v1(uuid,text,text)') IS NULL
 OR to_regclass('saly.creative_queue_native_delivery_evidence_v1') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_REQUIRES_V02_V06'; END IF;
END $pre$;

CREATE FUNCTION saly.creative_chat_save_qa_v1(
 p_token uuid, p_run_id bigint, p_artifact_ref text,
 p_artifact_sha256 text, p_worker_receipt text, p_qa_receipt jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET search_path TO pg_catalog,saly,pg_temp
AS $f$
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
 -- Existing trigger validates independent QA, approved_by, RUN, artifact
 -- and all sealed semantic/technical QA expectations in the real product.
 UPDATE saly.creative_order_items SET status='APROBADO',
    approved_at=clock_timestamp(),approved_by=v_reviewer,
    qa_receipt=p_qa_receipt||jsonb_build_object('run_id',p_run_id)
 WHERE id=i.id AND status='EN_QA';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_APPROVAL_NOT_READY'; END IF;
 RETURN jsonb_build_object('status','QA_COMMENT_SAVED_AWAITING_VERIFIED_CHAT_DELIVERY',
   'run_id',p_run_id,'item_id',i.id,'qa_verdict','PASS',
   'item_state','APROBADO','comment_saved',true,
   'native_delivery_verified',false,'db_done_allowed',false);
END $f$;

-- Called only after the existing V06 verified-evidence gate has been
-- fulfilled by an authorized source. Does NOT create host evidence.
CREATE FUNCTION saly.creative_chat_finalize_after_verified_delivery_v1(
 p_token uuid, p_run_id bigint
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET search_path TO pg_catalog,saly,pg_temp
AS $f$
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
 OR r.state<>'EXITOSO' OR i.status<>'APROBADO'
 OR i.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
 OR nullif(btrim(i.qa_receipt->>'comment'),'') IS NULL
 OR i.qa_receipt->>'artifact_sha256' IS DISTINCT FROM r.output_evidence->>'sha256'
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
    'item_id',i.id,'db_item_state','APROBADO','db_claim_state','DONE',
    'qa_comment',i.qa_receipt->>'comment',
    'order_closed',v_result->'order_closed');
END $f$;

REVOKE ALL ON FUNCTION saly.creative_chat_save_qa_v1(uuid,bigint,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION saly.creative_chat_finalize_after_verified_delivery_v1(uuid,bigint) FROM PUBLIC;
DO $acl$
DECLARE p text;
BEGIN
 FOREACH p IN ARRAY ARRAY['anon','authenticated','service_role','supabase_read_only_user'] LOOP
  IF to_regrole(p) IS NOT NULL THEN
   EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_chat_save_qa_v1(uuid,bigint,text,text,text,jsonb) FROM %I',p);
   EXECUTE format('REVOKE ALL ON FUNCTION saly.creative_chat_finalize_after_verified_delivery_v1(uuid,bigint) FROM %I',p);
  END IF;
 END LOOP;
END $acl$;
-- Readback the guards, current two orders and absence of any runtime grants.
DO $post$
DECLARE v_src text;
BEGIN
 v_src:=pg_get_functiondef('saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)'::regprocedure);
 IF strpos(v_src,'creative_order_sequence_dependency_met_v1')=0
 OR strpos(v_src,'CREATIVE_CHAT_SINGLE_ORDER_EXACTLY_ONE_SCREEN')=0
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_SCOPE_GUARDS_MISSING'; END IF;
 v_src:=pg_get_functiondef('saly.creative_chat_finalize_after_verified_delivery_v1(uuid,bigint)'::regprocedure);
 IF strpos(v_src,'CREATIVE_CHAT_SINGLE_ORDER_NOT_TERMINADO')=0
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_TERMINAL_GUARD_MISSING'; END IF;
 IF has_function_privilege('service_role',
    'saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)','EXECUTE')
 OR has_function_privilege('anon',
    'saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated',
    'saly.creative_chat_save_qa_v1(uuid,bigint,text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_RUNTIME_GRANT_LEAK'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1)
 OR EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_GATE_V16_FALSE_EXECUTION'; END IF;
END $post$;
COMMIT;
