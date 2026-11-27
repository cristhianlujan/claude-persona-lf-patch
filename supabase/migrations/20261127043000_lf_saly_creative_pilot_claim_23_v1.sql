BEGIN;
DO $pilot$
DECLARE o record; i record; c jsonb; p jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=23 AND project_id=3 AND status='PLANIFICADO' FOR UPDATE;
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=27 AND order_id=23 AND status='PENDIENTE' FOR UPDATE;
 IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE state IN ('EN_COLA','EJECUTANDO')) THEN RAISE EXCEPTION 'LF_QUEUE_NOT_FREE'; END IF;
 c:=saly.creative_queue_claim_by_id_v1(23,'GPT_SELF_QA_LF_PILOT_23',86400);
 IF c->>'status' IS DISTINCT FROM 'CLAIMED' OR c->>'order_id' IS DISTINCT FROM '23' OR c->>'item_id' IS DISTINCT FROM '27' THEN RAISE EXCEPTION 'LF_CLAIM_MISMATCH'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1 WHERE id=(c->>'claim_id')::bigint AND order_id=23 AND item_id=27 AND state='ACTIVE' AND lease_until-claimed_at=interval '24 hours') THEN RAISE EXCEPTION 'LF_LEASE_MISMATCH'; END IF;
 p:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','LF','project_code','LF','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF p->>'status' IS DISTINCT FROM 'LF_DISCOVERY_PREPARED' OR p->>'order_id' IS DISTINCT FROM '23' OR p->>'item_id' IS DISTINCT FROM '27' OR jsonb_typeof(p->'tokens') IS DISTINCT FROM 'array' OR jsonb_typeof(p->'assets') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'LF_PREPARE_FAILED'; END IF;
 RAISE NOTICE 'LF_23_CLAIMED claim_id=% prepare=%',c->>'claim_id',p->>'status';
END $pilot$;
COMMIT;
