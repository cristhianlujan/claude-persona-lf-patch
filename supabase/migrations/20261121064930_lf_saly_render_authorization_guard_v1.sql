BEGIN;
DO $guard$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_run_guard_l1()'::regprocedure))<>'dda82b00a3a352aefd3992a58718438b' THEN RAISE EXCEPTION 'CREATIVE_RUN_GUARD_BASE_CHANGED'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 SELECT i.status,o.status,o.scope_json INTO v_item_status,v_order_status,v_scope
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i;
 IF v_item_status IS NULL OR v_item_status IN ('APROBADO','OMITIDO')
    OR v_order_status IN ('COMPLETADO','CANCELADO')
 THEN RAISE EXCEPTION 'CREATIVE_RUN_ITEM_NOT_ELIGIBLE'; END IF;
 -- Review-only and explicitly disabled orders cannot enter or progress render.
 -- Permit cancellation/failure of an existing run so a revoked order can stop.
 IF (TG_OP='INSERT' OR NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO'))
 AND (v_scope->'review_only'='true'::jsonb
   OR (v_scope ? 'render_authorized' AND v_scope->'render_authorized' IS DISTINCT FROM 'true'::jsonb)
   OR (v_scope ? 'rendering_authority' AND v_scope->'rendering_authority' IS DISTINCT FROM 'true'::jsonb))
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_NOT_AUTHORIZED'; END IF;
 RETURN NEW;
END $function$;
DO $test$
DECLARE v_item record; v_blocked integer:=0;
BEGIN
 FOR v_item IN SELECT i.id,i.order_id FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id WHERE i.id IN (5,6,7,8,9)
 AND (o.scope_json->'review_only'='true'::jsonb OR o.scope_json->'render_authorized'='false'::jsonb OR o.scope_json->'rendering_authority'='false'::jsonb)
 LOOP
   BEGIN
    INSERT INTO saly.creative_runs(order_id,item_id,attempt_number,idempotency_key,state)
    VALUES(v_item.order_id,v_item.id,2147483647,'render-guard-negative-test-'||v_item.id,'EN_COLA');
    RAISE EXCEPTION 'UNAUTHORIZED_RENDER_TEST_UNEXPECTED_PASS';
   EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_RENDER_NOT_AUTHORIZED' THEN RAISE; END IF;
    v_blocked:=v_blocked+1;
   END;
 END LOOP;
 IF v_blocked<>5 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE idempotency_key LIKE 'render-guard-negative-test-%')
 THEN RAISE EXCEPTION 'CREATIVE_RENDER_GUARD_TEST_FAILED'; END IF;
END $test$;
COMMIT;
