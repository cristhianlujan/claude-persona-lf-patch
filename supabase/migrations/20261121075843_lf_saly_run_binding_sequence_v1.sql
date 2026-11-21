BEGIN;
DO $guard$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_run_guard_l1()'::regprocedure))<>'6b182b3deab3f668c4138ec37d7fac2a'
 THEN RAISE EXCEPTION 'CREATIVE_RUN_BASE_CHANGED'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint;
BEGIN
 IF TG_OP='UPDATE' THEN
   IF OLD.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
   THEN RAISE EXCEPTION 'CREATIVE_TERMINAL_RUN_IMMUTABLE'; END IF;
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.order_id IS DISTINCT FROM OLD.order_id
      OR NEW.item_id IS DISTINCT FROM OLD.item_id OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
      OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
   THEN RAISE EXCEPTION 'CREATIVE_RUN_BINDING_IMMUTABLE'; END IF;
   IF NEW.input_snapshot IS DISTINCT FROM OLD.input_snapshot
   THEN RAISE EXCEPTION 'CREATIVE_RUN_SNAPSHOT_IMMUTABLE'; END IF;
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
 -- The existing item row lock serializes attempt admission; existing unique
 -- indexes remain the authoritative idempotency and single-active constraints.
 IF TG_OP='INSERT' THEN
   IF NEW.state IS DISTINCT FROM 'EN_COLA' THEN RAISE EXCEPTION 'CREATIVE_RUN_INITIAL_STATE'; END IF;
   SELECT coalesce(max(attempt_number)::bigint,0)+1 INTO v_next_attempt
   FROM saly.creative_runs WHERE item_id=NEW.item_id;
   IF NEW.attempt_number IS DISTINCT FROM v_next_attempt
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE'; END IF;
 END IF;
 RETURN NEW;
END $function$;
-- Real table/trigger tests, synthetic rows in a rolled-back subtransaction.
-- Never modify an existing order's authorization or consume identity sequences.
DO $test$
DECLARE o bigint; i bigint; r bigint; ctx record; c record; n int:=0; v_constraint text;
 snapshot jsonb:='{"fixture":true,"prompt":"original"}'; fixture_key text;
BEGIN
 SELECT id,project_id,mode INTO STRICT ctx FROM saly.creative_context_sets
 WHERE state='SEALED' ORDER BY id LIMIT 1;
 SELECT least(coalesce(min(id),0),0)-1 INTO o FROM saly.creative_orders;
 SELECT least(coalesce(min(id),0),0)-1 INTO i FROM saly.creative_order_items;
 SELECT least(coalesce(min(id),0),0)-1 INTO r FROM saly.creative_runs;
 fixture_key:='TEST-RUN-BINDING-'||pg_current_xact_id()::text;
 BEGIN
  INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,requested_by,design_mode,context_set_id,scope_json,status)
  VALUES(o,ctx.project_id,fixture_key,fixture_key,'Transactional synthetic fixture','TEST_ONLY',ctx.mode,ctx.id,'{"render_authorized":true}'::jsonb,'PLANIFICADO');
  INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,status)
  VALUES(i,o,'TEST_RUN_BINDING',1,'SCREEN','Synthetic only','PENDIENTE');
  BEGIN
   INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
   VALUES(r,o,i,1,'test-1','EJECUTANDO',snapshot);
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_RUN_INITIAL_STATE' THEN RAISE; END IF; n:=n+1;
  END;
  BEGIN
   INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
   VALUES(r,o,i,2,'test-2','EN_COLA',snapshot);
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_RUN_ATTEMPT_OUT_OF_SEQUENCE' THEN RAISE; END IF; n:=n+1;
  END;
  INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
  VALUES(r,o,i,1,'test-1','EN_COLA',snapshot);
  FOR c IN SELECT * FROM (VALUES
   ('id',format('id=%s',r-10),'CREATIVE_RUN_BINDING_IMMUTABLE'),
   ('order',format('order_id=%s',o-10),'CREATIVE_RUN_BINDING_IMMUTABLE'),
   ('item',format('item_id=%s',i-10),'CREATIVE_RUN_BINDING_IMMUTABLE'),
   ('attempt','attempt_number=2','CREATIVE_RUN_BINDING_IMMUTABLE'),
   ('key','idempotency_key=''changed''','CREATIVE_RUN_BINDING_IMMUTABLE'),
   ('snapshot','input_snapshot=''{"changed":true}''::jsonb','CREATIVE_RUN_SNAPSHOT_IMMUTABLE'),
   ('transition','state=''EXITOSO''','CREATIVE_RUN_INVALID_TRANSITION')
  ) t(name,assignment,expected) LOOP
   BEGIN
    EXECUTE format('UPDATE saly.creative_runs SET %s WHERE id=$1',c.assignment) USING r;
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS:%',c.name;
   EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>c.expected THEN RAISE; END IF; n:=n+1;
   END;
  END LOOP;
  BEGIN
   INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
   VALUES(r-1,o,i,2,'test-2','EN_COLA',snapshot);
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
   IF v_constraint<>'creative_runs_one_active_per_item' THEN RAISE; END IF; n:=n+1;
  END;
  UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='SYNTHETIC',started_at=now() WHERE id=r;
  UPDATE saly.creative_runs SET state='FALLIDO',error_code='SYNTHETIC_TEST',finished_at=now() WHERE id=r;
  BEGIN
   UPDATE saly.creative_runs SET error_code='changed' WHERE id=r;
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'CREATIVE_TERMINAL_RUN_IMMUTABLE' THEN RAISE; END IF; n:=n+1;
  END;
  BEGIN
   INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
   VALUES(r-1,o,i,2,'test-1','EN_COLA',snapshot);
   RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS v_constraint=CONSTRAINT_NAME;
   IF v_constraint<>'creative_runs_item_id_idempotency_key_key' THEN RAISE; END IF; n:=n+1;
  END;
  INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
  VALUES(r-1,o,i,2,'test-2','EN_COLA',snapshot);
  IF n<>12 OR NOT EXISTS(SELECT 1 FROM saly.creative_runs WHERE id=r AND state='FALLIDO' AND input_snapshot=snapshot)
    OR NOT EXISTS(SELECT 1 FROM saly.creative_runs WHERE id=r-1 AND state='EN_COLA' AND attempt_number=2 AND input_snapshot=snapshot)
  THEN RAISE EXCEPTION 'RUN_BINDING_ASSERTION_FAILED'; END IF;
  RAISE EXCEPTION 'RUN_BINDING_ROLLBACK_FIXTURE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'RUN_BINDING_ROLLBACK_FIXTURE' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM saly.creative_orders WHERE id=o) OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=i)
 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE id IN(r,r-1))
 THEN RAISE EXCEPTION 'RUN_BINDING_FIXTURE_LEAK'; END IF;
 RAISE NOTICE 'RUN_BINDING: positive transitions PASS, negative controls %, fixture rollback PASS; not a concurrent test',n;
END $test$;
COMMIT;
