BEGIN;
-- Explicit operational parameters; no real values are activated in this migration.
DO $pre$ BEGIN
 IF md5(pg_get_functiondef('saly.creative_run_guard_l1()'::regprocedure))<>'2c0c39b632dda895e97724533c9a43bb'
 THEN RAISE EXCEPTION 'CREATIVE_LIFECYCLE_BASE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_runs) THEN RAISE EXCEPTION 'CREATIVE_LIFECYCLE_EXISTING_RUNS_REQUIRE_BACKFILL'; END IF;
 IF EXISTS(SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY')
 THEN RAISE EXCEPTION 'CREATIVE_LIFECYCLE_CONFIG_ALREADY_EXISTS'; END IF;
END $pre$;
ALTER TABLE saly.creative_runs
 ADD COLUMN execution_policy jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(execution_policy)='object'),
 ADD COLUMN deadline_at timestamptz NOT NULL;
CREATE INDEX creative_runs_expiry_idx ON saly.creative_runs(deadline_at,id) WHERE state IN ('EN_COLA','EJECUTANDO');

CREATE FUNCTION saly.creative_execution_policy_v1(p_asof timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,saly,pg_temp AS $fn$
DECLARE k text; c record; result jsonb:='{}'; pins jsonb:='{}';
BEGIN
 IF p_asof IS NULL THEN RAISE EXCEPTION 'CREATIVE_CONFIG_ASOF_REQUIRED'; END IF;
 FOREACH k IN ARRAY ARRAY['QUEUE_MAX','MAX_ATTEMPTS','QUEUE_TIMEOUT_SECONDS','LEASE_SECONDS'] LOOP
   SELECT config_value,value_type,value_status,valid_from INTO c FROM saly.config_global
   WHERE scope='CREATIVE_FACTORY' AND config_key=k AND valid_from<=p_asof
   ORDER BY valid_from DESC LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CONFIG_MISSING:%',k; END IF;
   IF c.value_type<>'INTEGER' OR c.value_status<>'REAL' OR c.config_value !~ '^[1-9][0-9]*$'
   THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   IF c.config_value::numeric>2147483647 THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   result:=result||jsonb_build_object(k,c.config_value::integer);
   pins:=pins||jsonb_build_object(k,c.valid_from);
 END LOOP;
 RETURN result||jsonb_build_object('schema_version','CREATIVE_EXECUTION_POLICY_V1','config_scope','CREATIVE_FACTORY','versions',pins);
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_execution_policy_v1(timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION saly.creative_run_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_item_status text; v_order_status text; v_scope jsonb; v_next_attempt bigint; v_now timestamptz:=clock_timestamp(); v_policy jsonb;
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
   IF NEW.execution_policy IS DISTINCT FROM OLD.execution_policy
      OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_IMMUTABLE'; END IF;
   IF OLD.state='EJECUTANDO' AND (NEW.worker_ref IS DISTINCT FROM OLD.worker_ref
      OR NEW.started_at IS DISTINCT FROM OLD.started_at)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_IMMUTABLE'; END IF;
   IF NEW.state<>OLD.state
     AND NOT ((OLD.state='EN_COLA' AND NEW.state IN ('EJECUTANDO','BLOQUEADO','CANCELADO'))
       OR (OLD.state='EJECUTANDO' AND NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_INVALID_TRANSITION'; END IF;
 END IF;
 -- Only admissions contend on the queue capacity lock.
 IF TG_OP='INSERT' THEN
   PERFORM pg_advisory_xact_lock(hashtextextended('saly.creative_runs:queue_capacity',0));
 END IF;
 SELECT i.status,o.status,o.scope_json INTO v_item_status,v_order_status,v_scope
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=NEW.item_id AND i.order_id=NEW.order_id FOR UPDATE OF i;
 IF v_item_status IS NULL OR
    ((v_item_status IN ('APROBADO','OMITIDO') OR v_order_status IN ('COMPLETADO','CANCELADO'))
     AND (TG_OP='INSERT' OR NEW.state NOT IN ('FALLIDO','BLOQUEADO','CANCELADO')))
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
   v_policy:=saly.creative_execution_policy_v1(v_now);
   IF NEW.attempt_number>(v_policy->>'MAX_ATTEMPTS')::integer
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ATTEMPT_LIMIT'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND idempotency_key=NEW.idempotency_key)
   THEN RAISE EXCEPTION 'CREATIVE_RUN_IDEMPOTENCY_REPLAY'; END IF;
   IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE item_id=NEW.item_id AND state IN ('EN_COLA','EJECUTANDO'))
   THEN RAISE EXCEPTION 'CREATIVE_RUN_ALREADY_ACTIVE'; END IF;
   IF (SELECT count(*) FROM saly.creative_runs WHERE state='EN_COLA') >= (v_policy->>'QUEUE_MAX')::integer
   THEN RAISE EXCEPTION 'CREATIVE_QUEUE_FULL'; END IF;
   NEW.execution_policy:=v_policy;
   NEW.deadline_at:=v_now+make_interval(secs=>(v_policy->>'QUEUE_TIMEOUT_SECONDS')::integer);
   NEW.started_at:=NULL;
   NEW.finished_at:=NULL;
 ELSE
   IF NEW.state IN ('EN_COLA','EJECUTANDO','EXITOSO') AND OLD.deadline_at<=v_now
   THEN RAISE EXCEPTION 'CREATIVE_RUN_DEADLINE_EXPIRED'; END IF;
   IF OLD.state='EN_COLA' AND NEW.state='EJECUTANDO' THEN
     IF nullif(btrim(NEW.worker_ref),'') IS NULL THEN RAISE EXCEPTION 'CREATIVE_RUN_WORKER_REQUIRED'; END IF;
     NEW.started_at:=v_now;
     NEW.deadline_at:=v_now+make_interval(secs=>(OLD.execution_policy->>'LEASE_SECONDS')::integer);
   ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
     RAISE EXCEPTION 'CREATIVE_RUN_STARTED_AT_IMMUTABLE';
   END IF;
   IF NEW.state IN ('EXITOSO','FALLIDO','BLOQUEADO','CANCELADO') THEN NEW.finished_at:=v_now; END IF;
 END IF;
 RETURN NEW;
END $function$;

-- Targeted recovery is idempotent. Does not dispatch, retry, or assert provider outcome.
CREATE FUNCTION saly.creative_run_expire_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO pg_catalog,saly,pg_temp AS $fn$
DECLARE r saly.creative_runs%ROWTYPE; v_now timestamptz;
BEGIN
 IF p_run_id IS NULL THEN RAISE EXCEPTION 'CREATIVE_RECOVERY_RUN_ID_REQUIRED'; END IF;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BUSY_OR_NOT_FOUND','run_id',p_run_id,'changed',false); END IF;
 IF r.state NOT IN ('EN_COLA','EJECUTANDO') THEN
   RETURN jsonb_build_object('status','ALREADY_TERMINAL','run_id',r.id,'state',r.state,'changed',false);
 END IF;
 v_now:=clock_timestamp();
 IF r.deadline_at>v_now THEN
   RETURN jsonb_build_object('status','NOT_EXPIRED','run_id',r.id,'state',r.state,'changed',false);
 END IF;
 UPDATE saly.creative_runs SET state=CASE r.state WHEN 'EN_COLA' THEN 'BLOQUEADO' ELSE 'FALLIDO' END,
  error_code=CASE r.state WHEN 'EN_COLA' THEN 'QUEUE_TIMEOUT' ELSE 'LEASE_EXPIRED' END,
  updated_at=v_now WHERE id=r.id RETURNING * INTO r;
 RETURN jsonb_build_object('status','EXPIRED_CLOSED','run_id',r.id,'state',r.state,'error_code',r.error_code,
  'attempt_number',r.attempt_number,'changed',true,'retry_dispatched',false);
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_run_expire_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Synthetic only, all writes rolled back in a subtransaction on the actual DB.
DO $test$
DECLARE ctx record; o bigint; i bigint; j bigint; r bigint; z jsonb; dl timestamptz; n int:=0; t timestamptz;
BEGIN
 SELECT id,project_id,mode INTO STRICT ctx FROM saly.creative_context_sets WHERE state='SEALED' ORDER BY id LIMIT 1;
 SELECT least(coalesce(min(id),0),0)-1 INTO o FROM saly.creative_orders;
 SELECT least(coalesce(min(id),0),0)-1 INTO i FROM saly.creative_order_items; j:=i-1;
 SELECT least(coalesce(min(id),0),0)-1 INTO r FROM saly.creative_runs;
 BEGIN
  INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,requested_by,design_mode,context_set_id,scope_json,status)
  VALUES(o,ctx.project_id,'TEST-LIFECYCLE-'||pg_current_xact_id()::text,'TEST-LIFECYCLE-'||pg_current_xact_id()::text,
    'Synthetic lifecycle fixture','TEST_ONLY',ctx.mode,ctx.id,'{"render_authorized":true}','PLANIFICADO');
  INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,status)
  VALUES(i,o,'TEST_LIFECYCLE_A',1,'SCREEN','Synthetic A','PENDIENTE'),
        (j,o,'TEST_LIFECYCLE_B',2,'SCREEN','Synthetic B','PENDIENTE');
  BEGIN
    INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r,o,i,1,'a1');
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_CONFIG_MISSING:QUEUE_MAX' THEN RAISE; END IF; n:=n+1;
  END;
  t:=clock_timestamp();
  INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,valid_from,description)
  SELECT 'CREATIVE_FACTORY',k,v,'INTEGER','REAL',t,'TEST_ONLY rolled back'
  FROM (VALUES('QUEUE_MAX','1'),('MAX_ATTEMPTS','2'),('QUEUE_TIMEOUT_SECONDS','4'),('LEASE_SECONDS','1')) x(k,v);
  INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r,o,i,1,'a1');
  SELECT deadline_at INTO dl FROM saly.creative_runs WHERE id=r;
  IF dl IS NULL OR (SELECT execution_policy->>'LEASE_SECONDS' FROM saly.creative_runs WHERE id=r)<>'1'
  THEN RAISE EXCEPTION 'TEST_POLICY_PIN_FAILED'; END IF;
  BEGIN
    INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r-1,o,j,1,'b1');
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_QUEUE_FULL' THEN RAISE; END IF; n:=n+1;
  END;
  BEGIN
    UPDATE saly.creative_runs SET deadline_at=dl+interval '1 day' WHERE id=r;
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_DEADLINE_IMMUTABLE' THEN RAISE; END IF; n:=n+1;
  END;
  BEGIN
    UPDATE saly.creative_runs SET state='EJECUTANDO' WHERE id=r;
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_WORKER_REQUIRED' THEN RAISE; END IF; n:=n+1;
  END;
  z:=saly.creative_run_expire_v1(r);
  IF z->>'status'<>'NOT_EXPIRED' OR z->'changed'<>'false'::jsonb THEN RAISE EXCEPTION 'TEST_EARLY_EXPIRY'; END IF;
  UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='SYNTHETIC' WHERE id=r;
  BEGIN
    UPDATE saly.creative_runs SET worker_ref='OTHER' WHERE id=r;
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_WORKER_IMMUTABLE' THEN RAISE; END IF; n:=n+1;
  END;
  PERFORM pg_sleep(1.1);
  BEGIN
    UPDATE saly.creative_runs SET state='EXITOSO' WHERE id=r;
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_DEADLINE_EXPIRED' THEN RAISE; END IF; n:=n+1;
  END;
  z:=saly.creative_run_expire_v1(r);
  IF z->>'status'<>'EXPIRED_CLOSED' OR z->>'state'<>'FALLIDO' OR z->>'error_code'<>'LEASE_EXPIRED' OR z->'retry_dispatched'<>'false'::jsonb
  THEN RAISE EXCEPTION 'TEST_LEASE_RECOVERY_FAILED'; END IF;
  z:=saly.creative_run_expire_v1(r);
  IF z->>'status'<>'ALREADY_TERMINAL' OR z->'changed'<>'false'::jsonb THEN RAISE EXCEPTION 'TEST_RECOVERY_NOT_IDEMPOTENT'; END IF;
  BEGIN
    INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r-1,o,i,2,'a1');
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_IDEMPOTENCY_REPLAY' THEN RAISE; END IF; n:=n+1;
  END;
  INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,valid_from,description)
  VALUES('CREATIVE_FACTORY','QUEUE_TIMEOUT_SECONDS','1','INTEGER','REAL',clock_timestamp(),'TEST_ONLY rolled back');
  INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r-1,o,i,2,'a2');
  BEGIN
    INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key) VALUES(r-2,o,i,3,'a3');
    RAISE EXCEPTION 'TEST_UNEXPECTED_PASS';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CREATIVE_RUN_ATTEMPT_LIMIT' THEN RAISE; END IF; n:=n+1;
  END;
  -- Recovery must still close a run after the parent is cancelled.
  UPDATE saly.creative_orders SET status='CANCELADO' WHERE id=o;
  PERFORM pg_sleep(1.1);
  z:=saly.creative_run_expire_v1(r-1);
  IF z->>'status'<>'EXPIRED_CLOSED' OR z->>'state'<>'BLOQUEADO' OR z->>'error_code'<>'QUEUE_TIMEOUT'
  THEN RAISE EXCEPTION 'TEST_QUEUE_RECOVERY_FAILED'; END IF;
  IF n<>8 THEN RAISE EXCEPTION 'TEST_NEGATIVE_COUNT:%',n; END IF;
  RAISE EXCEPTION 'LIFECYCLE_FIXTURE_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LIFECYCLE_FIXTURE_ROLLBACK' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM saly.creative_orders WHERE id=o) OR EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id IN (i,j))
 OR EXISTS(SELECT 1 FROM saly.creative_runs) OR EXISTS(SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY')
 THEN RAISE EXCEPTION 'LIFECYCLE_FIXTURE_LEAK'; END IF;
 IF has_function_privilege('service_role','saly.creative_run_expire_v1(bigint)','EXECUTE')
 OR has_function_privilege('anon','saly.creative_run_expire_v1(bigint)','EXECUTE')
 OR has_function_privilege('authenticated','saly.creative_run_expire_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'LIFECYCLE_ACL_DRIFT'; END IF;
 RAISE NOTICE 'CREATIVE_LIFECYCLE: 8 specific negatives; timed recovery, idempotence, frozen policy, parent cancellation and fixture rollback PASS';
END $test$;
COMMIT;
