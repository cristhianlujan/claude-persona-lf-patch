BEGIN;
DO $pilot$
DECLARE c jsonb; p jsonb; o record; i record;
BEGIN
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=22 AND project_id=2 AND status='PLANIFICADO';
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=26 AND order_id=o.id AND status='PENDIENTE';
 c:=saly.creative_queue_claim_by_id_v1(22,'GPT_SELF_QA_SALY_PILOT_22',NULL);
 IF c->>'status' IS DISTINCT FROM 'CLAIMED' OR c->>'order_id' IS DISTINCT FROM '22' OR c->>'item_id' IS DISTINCT FROM '26' THEN RAISE EXCEPTION 'PILOT_EXPECTED_ORDER_22_NOT_CLAIMED'; END IF;
 p:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','SALY','project_code','SALY-001','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF p->>'status' IS DISTINCT FROM 'AUTONOMOUS_PREPARED' OR p->'image_generation_allowed' IS DISTINCT FROM 'true'::jsonb OR p#>>'{logo_ref,asset_id}' IS DISTINCT FROM '9' OR jsonb_typeof(p->'tokens') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'PILOT_PREPARE_FAILED: %',p->>'blocking_code'; END IF;
END $pilot$;
COMMIT;
