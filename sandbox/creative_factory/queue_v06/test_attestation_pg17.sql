-- Isolated PG17 test, only after queue_v02 fixture + queue_v06 SQL.
-- Simulated trusted verifier is the isolated DB owner, NEVER a real host receipt.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE
  claim jsonb;
  tok uuid;
  runid bigint;
  itemid bigint;
  orderid bigint;
  evidence_id bigint;
  artifact_sha text:=repeat('a',64);
  host_hash text:=repeat('b',64);
  r jsonb;
  n integer:=0;
BEGIN
 -- The text function is now inert regardless of worker's own message.
 BEGIN
   PERFORM saly.creative_queue_record_delivery_v1(gen_random_uuid(),1,'chat','user-text');
   RAISE EXCEPTION 'UNATTESTED_TEXT_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN' THEN RAISE; END IF;
 END;
 n:=n+1;

 claim:=saly.creative_queue_claim_next_v1('WORKER-A');
 IF claim->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'TEST_QUEUE_CLAIM_NOT_READY'; END IF;
 tok:=(claim->>'claim_token')::uuid;
 itemid:=(claim->>'item_id')::bigint;
 orderid:=(claim->>'order_id')::bigint;
 r:=saly.creative_queue_admit_run_v1(tok,1,'NATIVE-DELIVERY-T1',
   '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
 runid:=(r->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,runid,'EJECUTANDO');
 PERFORM saly.creative_queue_advance_run_v1(tok,runid,'EXITOSO',
    jsonb_build_object('artifact_ref','test://output','sha256',artifact_sha,'worker_receipt','synthetic-only'));
 UPDATE saly.creative_order_items SET status='EN_QA' WHERE id=itemid;
 UPDATE saly.creative_order_items SET status='APROBADO',
    approved_at=clock_timestamp(),approved_by='QA-INDEPENDENT',
    qa_receipt=jsonb_build_object('run_id',runid,'verdict','PASS','reviewer_ref','QA-INDEPENDENT')
    WHERE id=itemid;

 -- Old ledger forged by privileged synthetic test owner cannot satisfy DONE.
 INSERT INTO saly.creative_queue_delivery_receipts_v1
 (claim_id,run_id,artifact_ref,artifact_sha256,delivery_channel,delivery_receipt)
 VALUES ((claim->>'claim_id')::bigint,runid,'test://output',artifact_sha,'chat','forged-message');
 BEGIN
   PERFORM saly.creative_queue_release_v1(tok,'DONE');
   RAISE EXCEPTION 'OLD_TEXT_LEDGER_ENABLED_DONE';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 n:=n+1;

 -- Foreign claim, exact rejection before a reference can be accepted.
 BEGIN
   INSERT INTO saly.creative_queue_native_delivery_evidence_v1
   (claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,host_surface,
    message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
   VALUES (99999,runid,orderid,itemid,'test://output',artifact_sha,
           'chat','msg-x','GPT_NATIVE','test://host/proof-x',host_hash);
   RAISE EXCEPTION 'CROSS_CLAIM_EVIDENCE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_BINDING_NOT_READY' THEN RAISE; END IF;
 END;
 n:=n+1;

 INSERT INTO saly.creative_queue_native_delivery_evidence_v1
 (claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,host_surface,
    message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
 VALUES ((claim->>'claim_id')::bigint,runid,orderid,itemid,'test://output',artifact_sha,
         'chat','msg-1','GPT_NATIVE','test://host/proof-1',host_hash)
 RETURNING id INTO evidence_id;

 IF (SELECT state FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=evidence_id)<>'STAGED'
 THEN RAISE EXCEPTION 'EVIDENCE_INSERT_NOT_STAGED'; END IF;
 BEGIN
   PERFORM saly.creative_queue_release_v1(tok,'DONE');
   RAISE EXCEPTION 'STAGED_EVIDENCE_ENABLED_DONE';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
 END;
 n:=n+1;

 BEGIN
   UPDATE saly.creative_queue_native_delivery_evidence_v1
      SET state='VERIFIED',verified_at=clock_timestamp(),verifier_ref='WORKER-A'
      WHERE id=evidence_id;
   RAISE EXCEPTION 'WORKER_SELF_VERIFIED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_SELF_VERIFICATION' THEN RAISE; END IF;
 END;
 n:=n+1;

 BEGIN
   UPDATE saly.creative_queue_native_delivery_evidence_v1
      SET message_id='changed-to-evil' WHERE id=evidence_id;
   RAISE EXCEPTION 'STAGED_EVIDENCE_MUTATED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_PROMOTION_INVALID' THEN RAISE; END IF;
 END;
 n:=n+1;

 -- This POSITIVE is explicitly a simulated owner-only host verifier. It is
 -- not an actual callback and cannot authorize production or merge.
 UPDATE saly.creative_queue_native_delivery_evidence_v1
 SET state='VERIFIED',verified_at=clock_timestamp(),verifier_ref='SIMULATED-TRUSTED-HOST'
 WHERE id=evidence_id;
 IF (SELECT state FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=evidence_id)<>'VERIFIED'
 THEN RAISE EXCEPTION 'TEST_VERIFICATION_PROMOTION_MISSING'; END IF;

 BEGIN
   UPDATE saly.creative_queue_native_delivery_evidence_v1
     SET verifier_ref='CHANGED' WHERE id=evidence_id;
   RAISE EXCEPTION 'VERIFIED_EVIDENCE_MUTATED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE' THEN RAISE; END IF;
 END;
 n:=n+1;

 BEGIN
   DELETE FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=evidence_id;
   RAISE EXCEPTION 'VERIFIED_EVIDENCE_DELETED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_IMMUTABLE' THEN RAISE; END IF;
 END;
 n:=n+1;

 r:=saly.creative_queue_release_v1(tok,'DONE');
 IF r->>'status'<>'RELEASED' OR r->>'result'<>'DONE'
    OR (SELECT state FROM saly.creative_queue_claims_v1 WHERE claim_token=tok)<>'DONE'
 THEN RAISE EXCEPTION 'TEST_VERIFIED_DELIVERY_NOT_RELEASED'; END IF;
 -- Still has uncompleted ADELANTO item, so order must not close prematurely.
 IF (SELECT status FROM saly.creative_orders WHERE id=orderid)='COMPLETADO'
 THEN RAISE EXCEPTION 'TEST_PREMATURE_ORDER_CLOSE'; END IF;

 -- Native table cannot be written by application roles. Fresh fixture role
 -- is deliberately unprivileged and does not have table grants.
 IF to_regrole('service_role') IS NOT NULL AND
    has_table_privilege('service_role','saly.creative_queue_native_delivery_evidence_v1','INSERT')
 THEN RAISE EXCEPTION 'TEST_SERVICE_ROLE_EVIDENCE_WRITE_ALLOWED'; END IF;
 IF to_regrole('authenticated') IS NOT NULL AND
    has_table_privilege('authenticated','saly.creative_queue_native_delivery_evidence_v1','UPDATE')
 THEN RAISE EXCEPTION 'TEST_AUTH_EVIDENCE_PROMOTE_ALLOWED'; END IF;
 RAISE NOTICE 'PASS V06: 8 exact negative guards, positive SIMULATED owner verification, order not prematurely closed';
 RAISE NOTICE 'PASS B6/B12/B25/B30: old textual receipt cannot DONE, STAGED not VERIFIED, only future authenticated issuer can attest';
END $test$;
ROLLBACK;
