BEGIN;
DO $pilot$
DECLARE o record; i record; c record; claim jsonb; prep jsonb; rr jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=22 AND project_id=2 AND status='EN_PROCESO' AND scope_json->>'queue_mode'='SERIAL_V1' FOR UPDATE;
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=26 AND order_id=22 AND status='PRODUCIENDO' FOR UPDATE;
 SELECT * INTO STRICT c FROM saly.creative_queue_claims_v1 WHERE order_id=22 AND item_id=26 AND state='ACTIVE' AND worker_ref='GPT_SELF_QA_SALY_PILOT_22' FOR UPDATE;
 IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE order_id=22 OR item_id=26) THEN RAISE EXCEPTION 'PILOT_22_RUN_ALREADY_EXISTS'; END IF;
 IF c.lease_until<=clock_timestamp() THEN
   UPDATE saly.creative_queue_claims_v1 SET state='EXPIRED',finished_at=clock_timestamp(),note='PILOT_EXPIRED_WITHOUT_RUN' WHERE id=c.id AND order_id=22;
   UPDATE saly.creative_order_items SET status='PENDIENTE' WHERE id=26 AND order_id=22 AND status='PRODUCIENDO';
   claim:=saly.creative_queue_claim_by_id_v1(22,'GPT_SELF_QA_SALY_PILOT_22',NULL);
   IF claim->>'status' IS DISTINCT FROM 'CLAIMED' OR claim->>'order_id' IS DISTINCT FROM '22' OR claim->>'item_id' IS DISTINCT FROM '26' THEN RAISE EXCEPTION 'PILOT_22_CLAIM_MISMATCH'; END IF;
   SELECT * INTO STRICT c FROM saly.creative_queue_claims_v1 WHERE id=(claim->>'claim_id')::bigint AND order_id=22 AND item_id=26;
 ELSE
   PERFORM saly.creative_queue_heartbeat_v1(c.claim_token,NULL);
 END IF;
 prep:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','SALY','project_code','SALY-001','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF prep->>'status' IS DISTINCT FROM 'AUTONOMOUS_PREPARED' OR prep->'image_generation_allowed' IS DISTINCT FROM 'true'::jsonb OR prep#>>'{logo_ref,asset_id}' IS DISTINCT FROM '9' OR jsonb_typeof(prep->'tokens') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PILOT_22_PREPARE_FAILED: %',prep->>'blocking_code'; END IF;
 rr:=saly.creative_queue_admit_run_v1(c.claim_token,1,'saly-pilot-22-1',jsonb_build_object('identity_versions',prep->'tokens','source_refs',jsonb_build_array(prep->'logo_ref'),'screen_spec',prep->>'literal_request','prepare',prep));
 IF rr->>'state' IS DISTINCT FROM 'EN_COLA' OR rr->>'claim_id' IS DISTINCT FROM c.id::text THEN RAISE EXCEPTION 'PILOT_22_ADMISSION_FAILED'; END IF;
 RAISE NOTICE 'SALY_22_ADMITTED run_id=% claim_id=%',rr->>'run_id',c.id;
END $pilot$;
COMMIT;
