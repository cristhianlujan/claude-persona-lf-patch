-- SALY V12: pending-only ChatGPT image processing admission. CANDIDATE ONLY.
-- Extends existing V02 serial queue, does not replace its guarded RPCs.
-- SINGLE transaction: PENDIENTE -> LISTO -> CLAIM/RUN EJECUTANDO ->
-- PRODUCIENDO + order EN_PROCESO. No image tool invocation in SQL.
-- Private SECURITY DEFINER: no GRANT, no direct Supabase execution, no deploy.
BEGIN;
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
 SELECT id,code,status,scope_json INTO v_order FROM saly.creative_orders
 WHERE code=p_order_code FOR UPDATE;
 IF NOT FOUND OR v_order.status NOT IN ('PLANIFICADO','EN_PROCESO')
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_ORDER_NOT_ACTIVE'; END IF;
 IF v_order.scope_json->>'queue_mode' IS DISTINCT FROM 'SERIAL_V1'
 OR v_order.scope_json->>'rendering_authority' IS DISTINCT FROM 'true'
 OR coalesce(v_order.scope_json->>'review_only','false') IS DISTINCT FROM 'false'
 OR coalesce(v_order.scope_json->>'render_authorized','true') IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_RENDER_NOT_AUTHORIZED'; END IF;

 SELECT i.id,i.code,i.order_id INTO v_item
 FROM saly.creative_order_items i
 WHERE i.order_id=v_order.id AND i.code=ANY(p_allowed_item_codes)
 AND i.status='PENDIENTE'
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
COMMIT;
