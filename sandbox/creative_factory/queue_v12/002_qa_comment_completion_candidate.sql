-- SALY V12 QA / chat image completion candidate. No new host or producer.
-- SQL keeps the existing V02/V06 order, worker claim, reviewer independence,
-- verified-delivery gate and terminal order logic.
-- NOT a production migration. NO GRANT / no writer bypass.
BEGIN;
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
COMMIT;
