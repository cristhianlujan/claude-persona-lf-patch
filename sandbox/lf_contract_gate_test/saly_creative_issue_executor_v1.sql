\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('saly.pilot_event', :'payload', true);
DO $job$
DECLARE p jsonb:=current_setting('saly.pilot_event')::jsonb; o record; i record; c record; claim jsonb; prep jsonb; rr jsonb; rid bigint; token uuid; a jsonb; qa jsonb; result jsonb; target bigint; next_attempt integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT min(id) INTO target FROM saly.creative_orders WHERE id BETWEEN 11 AND 21 AND project_id=2 AND status<>'TERMINADO';
 IF target IS NULL THEN PERFORM set_config('saly.pilot_result','{"status":"EMPTY"}',true); RETURN; END IF;
 IF target>11 THEN
   IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items pi JOIN saly.creative_orders po ON po.id=pi.order_id WHERE po.id=target-1 AND po.status='TERMINADO' AND pi.status IN ('TERMINADO','APROBADO') AND pi.qa_receipt->>'review_mode'='GPT_SELF_QA' AND (SELECT count(*) FROM jsonb_each(pi.qa_receipt->'design_qa_v1') e WHERE e.value->>'score'='1')>=5 AND (SELECT count(*) FROM jsonb_each(pi.qa_receipt->'design_qa_v1') e WHERE e.value->>'score' IN ('0','1') AND nullif(btrim(e.value->>'evidence'),'') IS NOT NULL)=6) THEN RAISE EXCEPTION 'PILOT_PREVIOUS_DESIGN_QA_REQUIRED'; END IF;
   IF NOT EXISTS (SELECT 1 FROM saly.creative_owner_decisions_v1 d WHERE d.item_id=15 AND d.decision='APROBADO') THEN RAISE EXCEPTION 'PILOT_OWNER_VALIDATION_REQUIRED'; END IF;
 END IF;
 IF (p->>'order_id')::bigint IS DISTINCT FROM target THEN RAISE EXCEPTION 'PILOT_ORDER_NOT_NEXT'; END IF;
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=target AND project_id=2 AND scope_json->>'queue_mode'='SERIAL_V1';
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE order_id=target AND required;
 SELECT * INTO c FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE' FOR UPDATE;
 IF c.id IS NOT NULL AND c.lease_until<=clock_timestamp() THEN
   IF c.order_id<>target OR c.worker_ref<>'GPT_SELF_QA_SALY_PILOT' OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE queue_claim_id=c.id AND state IN ('EN_COLA','EJECUTANDO','EXITOSO')) THEN RAISE EXCEPTION 'PILOT_EXPIRED_CLAIM_REQUIRES_RECONCILIATION'; END IF;
   UPDATE saly.creative_queue_claims_v1 SET state='EXPIRED',finished_at=clock_timestamp(),note='PILOT_EXPIRED_WITHOUT_RUN' WHERE id=c.id;
   UPDATE saly.creative_order_items SET status='PENDIENTE' WHERE id=i.id AND status='PRODUCIENDO';
   c:=NULL;
 END IF;
 IF p->>'action'='claim' THEN
   IF c.id IS NULL THEN
     claim:=saly.creative_queue_claim_next_v1('GPT_SELF_QA_SALY_PILOT',NULL);
     IF claim->>'status'<>'CLAIMED' OR (claim->>'order_id')::bigint<>target THEN RAISE EXCEPTION 'PILOT_CLAIM_MISMATCH'; END IF;
     SELECT * INTO STRICT c FROM saly.creative_queue_claims_v1 WHERE id=(claim->>'claim_id')::bigint;
   END IF;
   IF c.order_id<>target OR c.worker_ref<>'GPT_SELF_QA_SALY_PILOT' THEN RAISE EXCEPTION 'PILOT_BUSY'; END IF;
   token:=c.claim_token;
   prep:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','SALY','project_code','SALY-001','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
   IF prep->>'status' IS DISTINCT FROM 'AUTONOMOUS_PREPARED' OR prep#>>'{logo_ref,asset_id}' IS DISTINCT FROM '9' THEN RAISE EXCEPTION 'PILOT_PREPARE_FAILED'; END IF;
   SELECT coalesce(max(attempt_number),0)+1 INTO next_attempt FROM saly.creative_runs WHERE item_id=i.id;
   SELECT id INTO rid FROM saly.creative_runs WHERE queue_claim_id=c.id AND state='EJECUTANDO';
   IF rid IS NULL THEN
     rr:=saly.creative_queue_admit_run_v1(token,next_attempt,'saly-issue-'||target||'-'||next_attempt,jsonb_build_object('identity_versions',prep->'tokens','source_refs',jsonb_build_array(prep->'logo_ref'),'screen_spec',prep->>'literal_request','prepare',prep));
     rid:=(rr->>'run_id')::bigint;
     PERFORM saly.creative_queue_advance_run_v1(token,rid,'EJECUTANDO');
   END IF;
   result:=jsonb_build_object('status','CLAIMED','order_id',target,'item_id',i.id,'run_id',rid,'claim_id',c.id,'prepare',prep);
 ELSIF p->>'action'='finish' THEN
   IF c.id IS NULL OR c.order_id<>target OR c.worker_ref<>'GPT_SELF_QA_SALY_PILOT' THEN RAISE EXCEPTION 'PILOT_NO_ACTIVE_CLAIM'; END IF;
   token:=c.claim_token; rid:=(p->>'run_id')::bigint; a:=p->'artifact'; qa:=p->'qa';
   IF a->>'sha256' !~ '^[0-9a-f]{64}$' OR nullif(a->>'artifact_ref','') IS NULL OR nullif(a->>'worker_receipt','') IS NULL OR qa->>'verdict' IS DISTINCT FROM 'PASS' THEN RAISE EXCEPTION 'PILOT_EVIDENCE_INVALID'; END IF;
   PERFORM saly.creative_queue_advance_run_v1(token,rid,'EXITOSO',a);
   PERFORM saly.creative_run_detection_record_v1(token,rid,1);
   UPDATE saly.creative_order_items SET status='EN_QA' WHERE id=i.id;
   UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=qa||jsonb_build_object('run_id',rid,'review_mode','GPT_SELF_QA','reviewer_ref',c.worker_ref,'semantic_independence_proven',false,'artifact_sha256',a->>'sha256') WHERE id=i.id;
   result:=saly.creative_chat_finalize_after_verified_delivery_v1(token,rid);
   IF result->>'status' IS DISTINCT FROM 'TERMINADO' THEN RAISE EXCEPTION 'PILOT_CLOSE_FAILED'; END IF;
   result:=result||jsonb_build_object('order_id',target);
 ELSE RAISE EXCEPTION 'PILOT_ACTION_INVALID'; END IF;
 PERFORM set_config('saly.pilot_result',result::text,true);
END $job$;
SELECT current_setting('saly.pilot_result');
COMMIT;
