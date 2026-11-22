-- V12 PostgreSQL 17 QA and closure using actual V02/V06 guards.
-- Run only on disposable fixture AFTER V12 test_pg17.sh two-connection start.
-- Positive V06 evidence is entirely SYNTHETIC; NOT a production host receipt.
\set ON_ERROR_STOP on
DO $test$
DECLARE
 c record; r record; i record; receipt jsonb; result jsonb;
 v_sha text:=repeat('a',64);
 v_host_hash text:=repeat('b',64);
 v_evidence_id bigint;
 v_claim jsonb;
 v_fail_run_id bigint;
 v_fail_token uuid;
BEGIN
 SELECT c.id,c.claim_token,c.worker_ref,c.order_id,c.item_id INTO c
 FROM saly.creative_queue_claims_v1 c
 JOIN saly.creative_orders o ON o.id=c.order_id
 WHERE o.code='V12_CHAT' AND c.state='ACTIVE';
 SELECT * INTO r FROM saly.creative_runs WHERE queue_claim_id=c.id;
 SELECT * INTO i FROM saly.creative_order_items WHERE id=c.item_id;
 IF c.id IS NULL OR r.id IS NULL OR i.status<>'PRODUCIENDO' THEN
  RAISE EXCEPTION 'V12_QA_TEST_SETUP_FAILED'; END IF;

 BEGIN
  PERFORM saly.creative_chat_save_qa_v1(c.claim_token,r.id,'test://image-home',v_sha,
    'synthetic-chat-result',
    jsonb_build_object('verdict','PASS','comment','','reviewer_ref','QA-R',
      'artifact_sha256',v_sha));
  RAISE EXCEPTION 'V12_EMPTY_QA_COMMENT_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_QA_COMMENT_OR_HASH_INVALID' THEN RAISE; END IF;
 END;

 BEGIN
  PERFORM saly.creative_chat_save_qa_v1(c.claim_token,r.id,'test://image-home',v_sha,
    'synthetic-chat-result',
    jsonb_build_object('verdict','PASS','comment','synthetic QA','reviewer_ref',c.worker_ref,
      'artifact_sha256',v_sha));
  RAISE EXCEPTION 'V12_SELF_QA_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_QA_REVIEWER_NOT_INDEPENDENT' THEN RAISE; END IF;
 END;

 BEGIN
  PERFORM saly.creative_chat_save_qa_v1(c.claim_token,r.id,'test://image-home',v_sha,
    'synthetic-chat-result',
    jsonb_build_object('verdict','PASS','comment','synthetic QA','reviewer_ref','QA-R',
      'artifact_sha256',repeat('0',64)));
  RAISE EXCEPTION 'V12_WRONG_ARTIFACT_SHA_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_QA_COMMENT_OR_HASH_INVALID' THEN RAISE; END IF;
 END;
 RAISE NOTICE 'PASS_V12_QA_NEGATIVES: empty comment, same worker, hash drift';

 receipt:=jsonb_build_object('verdict','PASS',
   'comment','QA sintético: copy y contraste comprobados en fixture; no host real.',
   'reviewer_ref','QA-R','artifact_sha256',v_sha);
 result:=saly.creative_chat_save_qa_v1(c.claim_token,r.id,'test://image-home',v_sha,
    'synthetic-chat-result',receipt);
 IF result->>'status'<>'QA_COMMENT_SAVED_AWAITING_VERIFIED_CHAT_DELIVERY'
 OR (SELECT status FROM saly.creative_order_items WHERE id=i.id)<>'APROBADO'
 OR (SELECT qa_receipt->>'comment' FROM saly.creative_order_items WHERE id=i.id)
   IS DISTINCT FROM receipt->>'comment'
 THEN RAISE EXCEPTION 'V12_QA_COMMENT_NOT_SAVED'; END IF;
 RAISE NOTICE 'PASS_V12_QA_COMMENT_SQL_PERSISTED';

 BEGIN
  PERFORM saly.creative_chat_finalize_after_verified_delivery_v1(c.claim_token,r.id);
  RAISE EXCEPTION 'V12_DONE_WITHOUT_CHAT_DELIVERY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 IF (SELECT state FROM saly.creative_queue_claims_v1 WHERE id=c.id)<>'ACTIVE'
 THEN RAISE EXCEPTION 'V12_QA_BLOCK_CHANGED_CLAIM'; END IF;
 RAISE NOTICE 'PASS_V12_NO_FALSE_DONE_WITHOUT_VERIFIED_EVIDENCE';

 INSERT INTO saly.creative_queue_native_delivery_evidence_v1
 (claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,host_surface,
  message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
 VALUES(c.id,r.id,c.order_id,i.id,'test://image-home',v_sha,'CHATGPT_CURRENT_CHAT',
  'SIMULATED-MESSAGE-ID','GPT_NATIVE','test://synthetic/image-gen-return',v_host_hash)
 RETURNING id INTO v_evidence_id;
 BEGIN
  PERFORM saly.creative_chat_finalize_after_verified_delivery_v1(c.claim_token,r.id);
  RAISE EXCEPTION 'V12_STAGED_EVIDENCE_ALLOWED_DONE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE saly.creative_queue_native_delivery_evidence_v1
    SET state='VERIFIED',verified_at=clock_timestamp(),verifier_ref=c.worker_ref
    WHERE id=v_evidence_id;
  RAISE EXCEPTION 'V12_SELF_VERIFICATION_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_NATIVE_DELIVERY_SELF_VERIFICATION' THEN RAISE; END IF;
 END;
 RAISE NOTICE 'PASS_V12_STAGED_AND_SELF_ATTESTATION_REJECTED';

 -- Synthetic PG17 owner can write the evidence directly. The production
 -- runtime cannot use this bypass: V06 denies grants to app roles.
 UPDATE saly.creative_queue_native_delivery_evidence_v1
   SET state='VERIFIED',verified_at=clock_timestamp(),
       verifier_ref='SIMULATED-INDEPENDENT-CHAT-READER'
 WHERE id=v_evidence_id;
 result:=saly.creative_chat_finalize_after_verified_delivery_v1(c.claim_token,r.id);
 IF result->>'status'<>'TERMINADO'
 OR (SELECT state FROM saly.creative_queue_claims_v1 WHERE id=c.id)<>'DONE'
 OR (SELECT status FROM saly.creative_order_items WHERE id=i.id)<>'APROBADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=c.order_id)<>'EN_PROCESO'
 THEN RAISE EXCEPTION 'V12_VERIFIED_POSITIVE_FAILED'; END IF;
 RAISE NOTICE 'PASS_V12_SYNTHETIC_VERIFIED_DONE_WITH_COMMENT';

 -- QA FAIL on next pending item: comments persist, but NOT TERMINADO.
 v_claim:=saly.creative_chat_begin_pending_v1('V12_CHAT',ARRAY['ADELANTO'],
  'CHAT-WORKER-FAIL','V12-FAIL-001',
  '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"ADELANTO"}}'::jsonb);
 IF v_claim->>'status'<>'PROCESSING_STARTED' THEN
  RAISE EXCEPTION 'V12_FAIL_CASE_BEGIN_FAILED'; END IF;
 v_fail_run_id:=(v_claim->>'run_id')::bigint;
 SELECT claim_token INTO v_fail_token FROM saly.creative_queue_claims_v1
 WHERE id=(SELECT queue_claim_id FROM saly.creative_runs WHERE id=v_fail_run_id);
 receipt:=jsonb_build_object('verdict','FAIL',
   'comment','QA sintético: texto financiero incongruente, se bloquea cierre.',
   'reviewer_ref','QA-FAIL','artifact_sha256',v_sha);
 result:=saly.creative_chat_save_qa_v1(v_fail_token,v_fail_run_id,
 'test://image-fail',v_sha,'synthetic-chat-fail-result',receipt);
 IF result->>'status'<>'QA_COMMENT_SAVED_BLOCKED'
 OR (SELECT status FROM saly.creative_order_items
     WHERE id=(SELECT item_id FROM saly.creative_runs WHERE id=v_fail_run_id))<>'BLOQUEADO'
 OR (SELECT state FROM saly.creative_queue_claims_v1
     WHERE claim_token=v_fail_token)<>'BLOCKED'
 OR (SELECT qa_receipt->>'comment' FROM saly.creative_order_items
     WHERE id=(SELECT item_id FROM saly.creative_runs WHERE id=v_fail_run_id))
   IS DISTINCT FROM receipt->>'comment'
 THEN RAISE EXCEPTION 'V12_QA_FAIL_NOT_BLOCKED_WITH_COMMENT'; END IF;
 RAISE NOTICE 'PASS_V12_QA_FAIL_COMMENT_SAVED_NO_DONE';
END $test$;
