-- Disposable PG17 only: exact user sequence Home -> Adelanto.
-- Positive VERIFIED evidence below is SYNTHETIC DB-owner injection, NOT host.
\set ON_ERROR_STOP on
DO $test$
DECLARE h bigint; a bigint; v jsonb; r_id bigint; claim_token uuid;
 v_sha text:=repeat('a',64); evidence_id bigint;
 v_receipt jsonb;
BEGIN
 SELECT id INTO STRICT h FROM saly.creative_orders
   WHERE code='SALY_HOME_V015_SINGLE_20261123';
 SELECT id INTO STRICT a FROM saly.creative_orders
   WHERE code='SALY_ADELANTO_V015_SINGLE_20261123';

 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1(
    'SALY_HOME_V015_SINGLE_20261123',ARRAY['HOME','OTHER'],
    'SYNTHETIC-WORKER','SYNTH-HOME-INVALID',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'TEST_MULTI_SCREEN_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_SINGLE_ORDER_EXACTLY_ONE_SCREEN' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1(
    'SALY_ADELANTO_V015_SINGLE_20261123',ARRAY['SOLICITAR_ADELANTO'],
    'SYNTHETIC-WORKER','SYNTH-ADELANTO-TOO-EARLY',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"SOLICITAR_ADELANTO"}}'::jsonb);
  RAISE EXCEPTION 'TEST_ADELANTO_STARTED_BEFORE_HOME';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_ORDER_PREDECESSOR_NOT_TERMINADO' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1(
    'SALY_HOME_V015_SINGLE_20261123',ARRAY['HOME'],
    'SYNTHETIC-WORKER','SYNTH-HOME-NOT-AUTHORIZED',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'TEST_REVIEW_ONLY_STARTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_RENDER_NOT_AUTHORIZED' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'TEST_FALSE_RUN_FROM_NEGATIVE'; END IF;

 -- From this line: SYNTHETIC permission within throwaway database ONLY.
 UPDATE saly.creative_orders SET
 scope_json=scope_json||'{"render_authorized":true,"review_only":false,"rendering_authority":true}'::jsonb
 WHERE id IN(h,a);
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1(
    'SALY_ADELANTO_V015_SINGLE_20261123',ARRAY['SOLICITAR_ADELANTO'],
    'SYNTHETIC-WORKER','SYNTH-ADELANTO-TOO-EARLY-AUTHORIZED',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"SOLICITAR_ADELANTO"}}'::jsonb);
  RAISE EXCEPTION 'TEST_ADELANTO_PREDECESSOR_BYPASS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_ORDER_PREDECESSOR_NOT_TERMINADO' THEN RAISE; END IF;
 END;

 v:=saly.creative_chat_begin_pending_v1(
 'SALY_HOME_V015_SINGLE_20261123',ARRAY['HOME'],
 'WORKER-HOME','RUN-HOME-ONE',
 '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
 IF v->>'status'<>'PROCESSING_STARTED' OR (v->>'order_id')::bigint<>h
 THEN RAISE EXCEPTION 'TEST_HOME_RUN_NOT_STARTED'; END IF;
 r_id:=(v->>'run_id')::bigint;
 SELECT c.claim_token INTO STRICT claim_token FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_runs r ON r.queue_claim_id=c.id WHERE r.id=r_id;
 v_receipt:=jsonb_build_object(
   'verdict','PASS','comment','Test synthetic Home QA; not host evidence.',
   'reviewer_ref','INDEPENDENT-QA-HOME','artifact_sha256',v_sha);
 v:=saly.creative_chat_save_qa_v1(claim_token,r_id,'test://synthetic/home.png',
   v_sha,'SYNTHETIC-WORKER-RECEIPT-HOME',v_receipt);
 IF v->>'status'<>'QA_COMMENT_SAVED_AWAITING_VERIFIED_CHAT_DELIVERY'
 THEN RAISE EXCEPTION 'TEST_HOME_QA_NOT_SAVED'; END IF;
 BEGIN
  PERFORM saly.creative_chat_finalize_after_verified_delivery_v1(claim_token,r_id);
  RAISE EXCEPTION 'TEST_FAKE_DONE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 INSERT INTO saly.creative_queue_native_delivery_evidence_v1(
   claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,
   host_surface,message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
 SELECT c.id,r.id,r.order_id,r.item_id,'test://synthetic/home.png',v_sha,
   'CHATGPT_CURRENT_CHAT','SYNTHETIC-HOME-DELIVERY','GPT_NATIVE',
   'test://synthetic/message-home',repeat('b',64)
 FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_runs r ON r.queue_claim_id=c.id WHERE r.id=r_id
 RETURNING id INTO evidence_id;
 UPDATE saly.creative_queue_native_delivery_evidence_v1
 SET state='VERIFIED',verified_at=clock_timestamp(),
 verifier_ref='SYNTHETIC-HOST-READER-UNTRUSTED'
 WHERE id=evidence_id;
 v:=saly.creative_chat_finalize_after_verified_delivery_v1(claim_token,r_id);
 IF v->>'status'<>'TERMINADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=h)<>'TERMINADO'
 OR NOT saly.creative_order_sequence_dependency_met_v1(a)
 THEN RAISE EXCEPTION 'TEST_HOME_NOT_TERMINADO_OR_ADELANTO_LOCKED'; END IF;

 v:=saly.creative_chat_begin_pending_v1(
 'SALY_ADELANTO_V015_SINGLE_20261123',ARRAY['SOLICITAR_ADELANTO'],
 'WORKER-ADELANTO','RUN-ADELANTO-TWO',
 '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"SOLICITAR_ADELANTO"}}'::jsonb);
 IF v->>'status'<>'PROCESSING_STARTED' OR (v->>'order_id')::bigint<>a
 THEN RAISE EXCEPTION 'TEST_ADELANTO_NOT_STARTED_AFTER_HOME'; END IF;
 r_id:=(v->>'run_id')::bigint;
 SELECT c.claim_token INTO STRICT claim_token FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_runs r ON r.queue_claim_id=c.id WHERE r.id=r_id;
 v_receipt:=jsonb_build_object('verdict','PASS',
   'comment','Test synthetic Adelanto QA; not host evidence.',
   'reviewer_ref','INDEPENDENT-QA-ADELANTO','artifact_sha256',v_sha);
 v:=saly.creative_chat_save_qa_v1(claim_token,r_id,
 'test://synthetic/adelanto.png',v_sha,
 'SYNTHETIC-WORKER-RECEIPT-ADELANTO',v_receipt);
 IF v->>'status'<>'QA_COMMENT_SAVED_AWAITING_VERIFIED_CHAT_DELIVERY'
 THEN RAISE EXCEPTION 'TEST_ADELANTO_QA_NOT_SAVED'; END IF;
 INSERT INTO saly.creative_queue_native_delivery_evidence_v1(
  claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,
  host_surface,message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
 SELECT c.id,r.id,r.order_id,r.item_id,'test://synthetic/adelanto.png',v_sha,
 'CHATGPT_CURRENT_CHAT','SYNTHETIC-ADELANTO-DELIVERY','GPT_NATIVE',
 'test://synthetic/message-adelanto',repeat('c',64)
 FROM saly.creative_queue_claims_v1 c JOIN saly.creative_runs r
  ON r.queue_claim_id=c.id WHERE r.id=r_id RETURNING id INTO evidence_id;
 UPDATE saly.creative_queue_native_delivery_evidence_v1
 SET state='VERIFIED',verified_at=clock_timestamp(),
   verifier_ref='SYNTHETIC-HOST-READER-UNTRUSTED'
 WHERE id=evidence_id;
 v:=saly.creative_chat_finalize_after_verified_delivery_v1(claim_token,r_id);
 IF v->>'status'<>'TERMINADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=a)<>'TERMINADO'
 OR (SELECT count(*) FROM saly.creative_runs)<>2
 OR (SELECT count(*) FROM saly.creative_queue_claims_v1 WHERE state='DONE')<>2
 THEN RAISE EXCEPTION 'TEST_TWO_SINGLE_ORDERS_NOT_TERMINADO'; END IF;
 RAISE NOTICE 'PASS_V16_TWO_SINGLE_ORDERS_SERIAL_AND_REAL_TERMINAL_SQL_SYNTHETIC_HOST_ONLY';
END $test$;
